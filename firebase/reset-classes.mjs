import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { cliAccessToken, projectId } from "./admin-client.mjs";

if (projectId !== "fap-attendance-71655")
  throw new Error("This reset is restricted to fap-attendance-71655.");
const apply = process.argv.includes("--apply");
const backupArg = process.argv
  .find((arg) => arg.startsWith("--backup="))
  ?.slice(9);
if (apply && (!backupArg || !path.isAbsolute(backupArg)))
  throw new Error(
    "--apply requires an absolute --backup= path outside the repository.",
  );
if (
  backupArg &&
  path.resolve(backupArg).startsWith(path.resolve(".") + path.sep)
)
  throw new Error("Keep the private backup outside the source repository.");
const { access_token } = await cliAccessToken();
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const headers = {
  Authorization: `Bearer ${access_token}`,
  "Content-Type": "application/json",
};
async function api(suffix, body) {
  const response = await fetch(base + suffix, {
    method: body ? "POST" : "GET",
    headers,
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok)
    throw new Error(
      `Firestore reset HTTP ${response.status} at ${suffix.split("?")[0]}`,
    );
  return response.json();
}
async function list(collection) {
  const documents = [];
  let pageToken;
  do {
    const params = new URLSearchParams({
      pageSize: "1000",
      showMissing: "true",
      ...(pageToken ? { pageToken } : {}),
    });
    const page = await api(`/${collection}?${params}`);
    documents.push(...(page.documents || []));
    pageToken = page.nextPageToken;
  } while (pageToken);
  return documents;
}
const collections = [
  "classes",
  "attendanceSessions",
  "attendanceRequests",
  "announcements",
  "reportMetadata",
];
const groups = Object.fromEntries(
  await Promise.all(collections.map(async (name) => [name, await list(name)])),
);
const workspaces = (await list("workspaces")).filter((d) => d.fields);
const teachers = await list("teachers"),
  users = await list("users");
const legacy = (
  await Promise.all(
    teachers.map((d) => list(`${d.name.split("/documents/")[1]}/workspaces`)),
  )
)
  .flat()
  .filter((d) => d.fields);
const nested = [
  ...(
    await Promise.all(
      groups.classes.map((d) =>
        list(`${d.name.split("/documents/")[1]}/meetings`),
      ),
    )
  ).flat(),
  ...(
    await Promise.all(
      groups.attendanceSessions.map((d) =>
        list(`${d.name.split("/documents/")[1]}/checkIns`),
      ),
    )
  ).flat(),
];
const deleted = [...nested, ...Object.values(groups).flat()].filter(
  (d) => d.fields,
);
const summary = {
  projectId,
  deleteCounts: Object.fromEntries(
    Object.entries(groups).map(([k, v]) => [
      k,
      v.filter((d) => d.fields).length,
    ]),
  ),
  nestedDocuments: nested.filter((d) => d.fields).length,
  resetWorkspaces: workspaces.length,
  resetLegacyWorkspaces: legacy.length,
  preservedUserProfiles: users.filter((d) => d.fields).length,
};
console.log(JSON.stringify({ mode: apply ? "apply" : "plan", ...summary }));
if (!apply) process.exit(0);
const at = new Date().toISOString();
await mkdir(path.dirname(backupArg), { recursive: true });
await writeFile(
  backupArg,
  JSON.stringify({
    projectId,
    createdAt: at,
    summary,
    documents: [...workspaces, ...legacy, ...deleted],
  }),
  { flag: "wx" },
);
console.log(`Private recovery snapshot saved: ${backupArg}`);
const barrier = [
  ...workspaces.map((d) => {
    const fields = structuredClone(d.fields);
    fields.layout = { mapValue: { fields: {} } };
    fields.revision = {
      integerValue: String(Number(fields.revision?.integerValue || 0) + 1),
    };
    fields.mutationId = { stringValue: randomUUID() };
    fields.updatedAt = { timestampValue: at };
    return {
      update: { name: d.name, fields },
      currentDocument: { updateTime: d.updateTime },
    };
  }),
  ...legacy.map((d) => {
    const fields = structuredClone(d.fields);
    if (!fields.workspace?.mapValue?.fields)
      throw new Error("Unexpected legacy workspace shape; nothing deleted.");
    fields.workspace.mapValue.fields.classes = { arrayValue: { values: [] } };
    fields.revision = {
      integerValue: String(Number(fields.revision?.integerValue || 0) + 1),
    };
    fields.mutationId = { stringValue: randomUUID() };
    fields.updatedAt = { stringValue: at };
    return {
      update: { name: d.name, fields },
      currentDocument: { updateTime: d.updateTime },
    };
  }),
];
for (let i = 0; i < barrier.length; i += 400)
  await api(":commit", { writes: barrier.slice(i, i + 400) });
for (let i = 0; i < deleted.length; i += 400)
  await api(":commit", {
    writes: deleted
      .slice(i, i + 400)
      .map((d) => ({
        delete: d.name,
        currentDocument: { updateTime: d.updateTime },
      })),
  });
const remaining = Object.fromEntries(
  await Promise.all(
    collections.map(async (name) => [
      name,
      (await list(name)).filter((d) => d.fields).length,
    ]),
  ),
);
const manifests = await list("workspaces");
if (
  Object.values(remaining).some(Boolean) ||
  manifests.some(
    (d) => Object.keys(d.fields?.layout?.mapValue?.fields || {}).length,
  )
)
  throw new Error(
    "Reset did not reach an empty class state. See the private snapshot; no success claimed.",
  );
console.log(
  JSON.stringify({
    resetComplete: true,
    deletedDocuments: deleted.length,
    remaining,
    emptyWorkspaces: workspaces.length,
    preservedUserProfiles: (await list("users")).filter((d) => d.fields).length,
  }),
);
