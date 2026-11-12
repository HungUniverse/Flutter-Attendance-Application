#!/usr/bin/env node
// A local, opt-in command-line interface. Commands read named inputs and write
// results to stdout; they never start the application's server or contact it.
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { importRosterCsv } from '../../backend/roster-csv-import.mjs';
import { importAttendanceCsv } from '../../backend/attendance-csv-import.mjs';
import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';
import { forecastRoster } from '../../backend/attendance-forecast.mjs';
import { applyAttendanceBatch } from '../../backend/attendance-batch.mjs';
import { compareAttendanceSnapshots } from '../../backend/attendance-snapshot-diff.mjs';
import { attendanceToCsv } from '../../backend/attendance-analytics.mjs';
import { createBundle, parseBundle, serializeBundle, putClass, removeClass, summarizeBundle,
  getClassSnapshot, summarizeStudentsAcrossClasses } from './bundle.mjs';
import { reviseSnapshot } from './revise.mjs';
import { renderHtmlReport } from './html-report.mjs';
import { generateRecurringSessions } from '../../backend/session-recurrence.mjs';
import { findScheduleConflicts } from '../../backend/session-schedule.mjs';
import { sessionsToICalendar } from '../../backend/session-icalendar.mjs';
import { rollingAttendance } from '../../backend/attendance-trends.mjs';
import { findConsecutiveAbsences } from '../../backend/attendance-streaks.mjs';
import { evaluatePolicy } from './policy.mjs';
import { createScenario, evaluateScenario, parseScenario, removeScenarioChange, scenarioToCsv,
  serializeScenario, setScenarioChange } from './scenario.mjs';
import { auditAttendanceSnapshot, auditToCsv } from './audit.mjs';
import { previewAttendanceImport } from './import-preview.mjs';
import { planSchedule } from './schedule-planner.mjs';
import { appendArchiveRevision, archiveToCsv, compareArchiveRevisions, createArchive, listArchiveRevisions,
  parseArchive, restoreArchiveRevision, serializeArchive } from './archive.mjs';
import { generateSyntheticDataset, listSyntheticProfiles, summarizeDatasetSnapshot } from './dataset-lab.mjs';
import { anonymizeArchive, anonymizeBundle, anonymizeSnapshot, anonymizationReport } from './privacy.mjs';
import { mappedImportIssuesToCsv, parseDelimitedCsv, previewMappedImport, suggestHeaderMapping } from './import-studio.mjs';
import { allocateReviewCases, buildReviewPlan, reviewPlanToCsv } from './review-plan.mjs';
import { auditCasebookHistory, casebookEventsToCsv, casebookHistoryAuditToCsv, casebookToCsv, createCasebook,
  listCasebookEvents, parseCasebook, reconcileCasebook, serializeCasebook, summarizeCasebook, updateCasebook } from './casebook.mjs';
import { buildReportStudio, renderReportStudioHtml, reportStudioToCsv } from './report-studio.mjs';
import { buildCloseoutPackage, closeoutComparisonToCsv, closeoutInspectionToCsv, compareCloseoutPackages,
  inspectCloseoutPackage, readCloseoutFile, serializeCloseoutPackage } from './closeout-pack.mjs';
import { buildPolicyLab, createPolicyGrid, policyLabToCsv } from './policy-lab.mjs';
import { buildCohortExplorer, cohortExplorerToCsv } from './cohort-explorer.mjs';
import { analyzeScheduleInsights, scheduleInsightsToCsv } from './schedule-insights.mjs';
import { reconcileAttendanceSources, reconciliationToCsv, summarizeReconciliation } from './source-reconciliation.mjs';
import { attendanceQueryDiffToCsv, attendanceQueryToCsv, compareAttendanceQueryResults, queryAttendanceSnapshot } from './snapshot-query.mjs';
import { applyApprovedCorrections, auditCorrectionReview, correctionAuditToCsv, correctionReviewToCsv,
  createCorrectionReview, parseCorrectionReview, serializeCorrectionReview, summarizeCorrectionReview, updateCorrectionCase } from './correction-review.mjs';
import { buildRetentionPlan, retentionPlanToCsv } from './retention-planner.mjs';
import { approveGovernedExport, governedExportToCsv, planGovernedExport } from './export-gate.mjs';
import { createExemptionLedger, evaluateExemptionLedger, exemptionToCsv, parseExemptionLedger,
  serializeExemptionLedger, summarizeExemptionLedger, updateExemption } from './exemption-ledger.mjs';
import { analyzeAttendancePatterns, attendancePatternsToCsv } from './attendance-patterns.mjs';
import { evaluateAttendanceForecasts, forecastEvaluationToCsv } from './forecast-evaluation.mjs';
import { planSnapshotMigration, snapshotMigrationToCsv } from './snapshot-migration.mjs';
import { parseSnapshotContract, snapshotContractToCsv, validateSnapshotContract } from './snapshot-contract.mjs';
import { allocateReviewCasesConstrained, reviewAllocationToCsv } from './review-allocator.mjs';
import { casebookSlaToCsv, reportCasebookSla } from './casebook-sla.mjs';
import { planAttendanceRecovery, recoveryPlanToCsv } from './recovery-planner.mjs';
import { casebookWorkloadToCsv, reportCasebookWorkload } from './casebook-workload.mjs';
import { applyCasebookBatch } from './casebook-batch.mjs';
import { casebookActivityToCsv, reportCasebookActivity } from './casebook-activity.mjs';
import { attendanceImpactDiffToCsv, compareAttendanceImpact } from './attendance-impact-diff.mjs';
import { casebookServiceLevelsToCsv, evaluateCasebookServiceLevels } from './casebook-service-level.mjs';
import { decideSnapshotRelease, planSnapshotRelease, snapshotReleaseToCsv,
  verifySnapshotReleaseReceipt, compareSnapshotReleaseReceipts, snapshotReleaseDiffToCsv } from './snapshot-release-gate.mjs';
import { planReviewBoard, reviewBoardToCsv } from './review-board.mjs';
import { anomaliesToCsv, detectAttendanceAnomalies } from './anomaly-detector.mjs';
import { evaluateFptAttendancePolicy, fptPolicyReportToCsv } from '../../backend/attendance-fpt-policy.mjs';

const usage = `Attendance workbench (Node.js 22+)

  node cli.mjs init ROSTER.csv SESSIONS.json ATTENDANCE.csv
  node cli.mjs report SNAPSHOT.json
  node cli.mjs report-html SNAPSHOT.json [TITLE]
  node cli.mjs rolling SNAPSHOT.json WINDOW_SIZE
  node cli.mjs absence-runs SNAPSHOT.json MINIMUM
  node cli.mjs forecast SNAPSHOT.json REMAINING TARGET
  node cli.mjs policy SNAPSHOT.json POLICY.json
  node cli.mjs policy-grid GRID.json
  node cli.mjs policy-lab SNAPSHOT.json OPTIONS.json
  node cli.mjs policy-lab-csv SNAPSHOT.json OPTIONS.json summary|cohorts|students|comparisons
  node cli.mjs snapshot-query SNAPSHOT.json QUERY.json
  node cli.mjs snapshot-query-csv SNAPSHOT.json QUERY.json rows|groups
  node cli.mjs snapshot-query-diff BEFORE.json AFTER.json [QUERY.json]
  node cli.mjs snapshot-query-diff-csv BEFORE.json AFTER.json SECTION [QUERY.json]
  node cli.mjs attendance-impact-diff BEFORE.json AFTER.json [OPTIONS.json]
  node cli.mjs attendance-impact-diff-csv BEFORE.json AFTER.json SECTION [OPTIONS.json]
  node cli.mjs cohort-explore SNAPSHOT.json OPTIONS.json
  node cli.mjs cohort-explore-csv SNAPSHOT.json OPTIONS.json SECTION
  node cli.mjs schedule-insights SCHEDULE.json [OPTIONS.json]
  node cli.mjs schedule-insights-csv SCHEDULE.json SECTION [OPTIONS.json]
  node cli.mjs source-reconcile SOURCES.json [OPTIONS.json]
  node cli.mjs source-reconcile-csv SOURCES.json SECTION [OPTIONS.json]
  node cli.mjs correction-new SNAPSHOT.json PROPOSALS.json [OPTIONS.json]
  node cli.mjs correction-update REVIEW.json CASE_ID UPDATE.json
  node cli.mjs correction-apply REVIEW.json CURRENT_SNAPSHOT.json [REVIEW_REVISION]
  node cli.mjs correction-audit REVIEW.json CURRENT_SNAPSHOT.json
  node cli.mjs correction-audit-csv REVIEW.json CURRENT_SNAPSHOT.json
  node cli.mjs correction-summary REVIEW.json
  node cli.mjs correction-csv REVIEW.json [--include-notes]
  node cli.mjs retention-plan INVENTORY.json POLICIES.json [OPTIONS.json]
  node cli.mjs retention-plan-csv INVENTORY.json POLICIES.json SECTION [OPTIONS.json]
  node cli.mjs export-plan SNAPSHOT.json POLICY.json REQUEST.json [OPTIONS.json]
  node cli.mjs export-approve SNAPSHOT.json POLICY.json REQUEST.json APPROVAL.json [OPTIONS.json]
  node cli.mjs governed-export-csv APPROVED_PLAN.json
  node cli.mjs exemption-new SNAPSHOT.json PROPOSALS.json [OPTIONS.json]
  node cli.mjs exemption-update LEDGER.json EXEMPTION_ID UPDATE.json
  node cli.mjs exemption-report LEDGER.json CURRENT_SNAPSHOT.json
  node cli.mjs exemption-report-csv LEDGER.json CURRENT_SNAPSHOT.json class|students|sessions
  node cli.mjs exemption-summary LEDGER.json
  node cli.mjs exemption-csv LEDGER.json
  node cli.mjs patterns SNAPSHOT.json OPTIONS.json
  node cli.mjs patterns-csv SNAPSHOT.json OPTIONS.json windows|cohorts|sessions|students
  node cli.mjs forecast-evaluate SNAPSHOT.json OPTIONS.json
  node cli.mjs forecast-evaluate-csv SNAPSHOT.json OPTIONS.json metrics|cohorts|calibration|comparisons|students
  node cli.mjs recovery-plan SNAPSHOT.json POLICY.json OPTIONS.json
  node cli.mjs recovery-plan-csv SNAPSHOT.json POLICY.json OPTIONS.json summary|cohorts|students
  node cli.mjs migration-plan SNAPSHOT.json OPTIONS.json
  node cli.mjs migration-plan-csv SNAPSHOT.json OPTIONS.json issues|conflicts|records
  node cli.mjs contract-check SNAPSHOT.json CONTRACT.json
  node cli.mjs contract-check-csv SNAPSHOT.json CONTRACT.json checks|summary
  node cli.mjs release-plan SNAPSHOT.json CONTRACT.json [OPTIONS.json]
  node cli.mjs release-decide PLAN.json APPROVAL.json
  node cli.mjs release-verify RECEIPT.json SNAPSHOT.json CONTRACT.json
  node cli.mjs release-csv RECEIPT.json
  node cli.mjs release-compare BEFORE_RECEIPT.json AFTER_RECEIPT.json
  node cli.mjs release-compare-csv BEFORE_RECEIPT.json AFTER_RECEIPT.json
  node cli.mjs scenario-new SNAPSHOT.json TITLE [POLICY.json]
  node cli.mjs scenario-set SCENARIO.json STUDENT_ID SESSION_ID present|absent|missing
  node cli.mjs scenario-remove SCENARIO.json STUDENT_ID SESSION_ID
  node cli.mjs scenario-evaluate SCENARIO.json [CURRENT_SNAPSHOT.json]
  node cli.mjs scenario-csv SCENARIO.json [CURRENT_SNAPSHOT.json]
  node cli.mjs audit SNAPSHOT.json [OPTIONS.json]
  node cli.mjs audit-csv SNAPSHOT.json [OPTIONS.json]
  node cli.mjs anomaly-scan SNAPSHOT.json [OPTIONS.json]
  node cli.mjs anomaly-scan-csv SNAPSHOT.json [OPTIONS.json]
  node cli.mjs fpt-policy SNAPSHOT.json [OPTIONS.json]
  node cli.mjs fpt-policy-csv SNAPSHOT.json [OPTIONS.json]
  node cli.mjs preview-import ROSTER.csv SESSIONS.json ATTENDANCE.csv
  node cli.mjs schedule-plan PLAN.json
  node cli.mjs archive-new SNAPSHOT.json TITLE
  node cli.mjs archive-add ARCHIVE.json SNAPSHOT.json MESSAGE [AUTHOR]
  node cli.mjs archive-list ARCHIVE.json
  node cli.mjs archive-compare ARCHIVE.json BEFORE_ID AFTER_ID
  node cli.mjs archive-restore ARCHIVE.json REVISION_ID MESSAGE [AUTHOR]
  node cli.mjs archive-csv ARCHIVE.json
  node cli.mjs demo-generate [OPTIONS.json]
  node cli.mjs demo-manifest [OPTIONS.json]
  node cli.mjs demo-profiles
  node cli.mjs demo-summary SNAPSHOT.json
  node cli.mjs anonymize-snapshot SNAPSHOT.json OPTIONS.json
  node cli.mjs anonymize-bundle BUNDLE.json OPTIONS.json
  node cli.mjs anonymize-archive ARCHIVE.json OPTIONS.json
  node cli.mjs anonymize-report SNAPSHOT.json OPTIONS.json
  node cli.mjs map-suggest CSV.csv roster|attendance [DELIMITER]
  node cli.mjs map-preview ROSTER.csv ATTENDANCE.csv SESSIONS.json [OPTIONS.json]
  node cli.mjs map-issues-csv ROSTER.csv ATTENDANCE.csv SESSIONS.json [OPTIONS.json]
  node cli.mjs review-plan SNAPSHOT.json [OPTIONS.json]
  node cli.mjs review-plan-csv SNAPSHOT.json [OPTIONS.json]
  node cli.mjs review-allocate PLAN.json REVIEWERS.json
  node cli.mjs review-allocate-constrained PLAN.json REVIEWERS.json [OPTIONS.json]
  node cli.mjs review-allocate-csv ALLOCATION.json assignments|reviewers|unassigned
  node cli.mjs review-board CASEBOOK.json PLAN.json REVIEWERS.json [OPTIONS.json]
  node cli.mjs review-board-csv CASEBOOK.json PLAN.json REVIEWERS.json SECTION [OPTIONS.json]
  node cli.mjs casebook-new PLAN.json [OPTIONS.json]
  node cli.mjs casebook-batch CASEBOOK.json BATCH.json
  node cli.mjs casebook-update CASEBOOK.json CASE_ID UPDATE.json
  node cli.mjs casebook-reconcile CASEBOOK.json PLAN.json [OPTIONS.json]
  node cli.mjs casebook-summary CASEBOOK.json
  node cli.mjs casebook-sla CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-sla-csv CASEBOOK.json cases|priority|assignee|summary [OPTIONS.json]
  node cli.mjs casebook-workload CASEBOOK.json REVIEWERS.json [OPTIONS.json]
  node cli.mjs casebook-workload-csv CASEBOOK.json REVIEWERS.json SECTION [OPTIONS.json]
  node cli.mjs casebook-activity CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-activity-csv CASEBOOK.json SECTION [OPTIONS.json]
  node cli.mjs casebook-service-level CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-service-level-csv CASEBOOK.json summary|priority|cases [OPTIONS.json]
  node cli.mjs casebook-csv CASEBOOK.json [--include-notes]
  node cli.mjs casebook-events CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-events-csv CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-history-audit CASEBOOK.json [OPTIONS.json]
  node cli.mjs casebook-history-audit-csv CASEBOOK.json [OPTIONS.json]
  node cli.mjs report-studio SNAPSHOT.json [OPTIONS.json]
  node cli.mjs report-html-studio SNAPSHOT.json [OPTIONS.json]
  node cli.mjs report-csv-studio SNAPSHOT.json SECTION [OPTIONS.json]
  node cli.mjs closeout-pack SNAPSHOT.json [OPTIONS.json]
  node cli.mjs closeout-inspect PACKAGE.json
  node cli.mjs closeout-inspect-csv PACKAGE.json
  node cli.mjs closeout-extract PACKAGE.json FILE_NAME
  node cli.mjs closeout-compare BEFORE_PACKAGE.json AFTER_PACKAGE.json
  node cli.mjs closeout-compare-csv BEFORE_PACKAGE.json AFTER_PACKAGE.json
  node cli.mjs apply SNAPSHOT.json CHANGES.json
  node cli.mjs compare BEFORE.json AFTER.json
  node cli.mjs export-csv SNAPSHOT.json
  node cli.mjs set-roster SNAPSHOT.json ROSTER.csv [--drop-records]
  node cli.mjs set-sessions SNAPSHOT.json SESSIONS.json [--drop-records]
  node cli.mjs bundle-new
  node cli.mjs bundle-put BUNDLE.json CLASS_ID CLASS_NAME SNAPSHOT.json
  node cli.mjs bundle-remove BUNDLE.json CLASS_ID
  node cli.mjs bundle-report BUNDLE.json
  node cli.mjs bundle-students BUNDLE.json
  node cli.mjs bundle-extract BUNDLE.json CLASS_ID
  node cli.mjs schedule-generate OPTIONS.json
  node cli.mjs schedule-conflicts SCHEDULE.json
  node cli.mjs schedule-calendar SCHEDULE.json DOMAIN GENERATED_AT [TITLE]

Commands print results to stdout. Redirect stdout to a new file to save it.
Sessions is a JSON array of session IDs in chronological order. Changes is a
JSON array of {studentId, sessionId, expected, status}, where null represents
an unrecorded result. Target is a fraction from 0 to 1.
`;

function json(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

async function readText(path) {
  return readFile(path, 'utf8');
}

async function snapshot(path) {
  return parseAttendanceSnapshot(await readText(path));
}

function requireArgs(args, count) {
  if (args.length !== count) throw new TypeError(`expected ${count} arguments; use --help`);
}

/** Execute without writing files, so callers can select their own output path. */
export async function runCommand(args) {
  const [command, ...values] = args;
  if (command === '--help' || command === '-h' || command === undefined) {
    requireArgs(values, 0);
    return usage;
  }
  switch (command) {
    case 'init': {
      requireArgs(values, 3);
      const [rosterText, sessionsText, attendanceText] = await Promise.all(values.map(readText));
      const roster = importRosterCsv(rosterText);
      const attendance = importAttendanceCsv(attendanceText);
      if (roster.errors.length || attendance.errors.length) {
        throw new Error(`CSV validation failed: ${JSON.stringify({ roster: roster.errors, attendance: attendance.errors })}`);
      }
      return `${serializeAttendanceSnapshot(createAttendanceSnapshot(roster.students,
        JSON.parse(sessionsText), attendance.records))}\n`;
    }
    case 'report': {
      requireArgs(values, 1);
      const data = await snapshot(values[0]);
      return json(attendanceQualityReport(data.roster, data.sessionIds, data.records));
    }
    case 'report-html': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional title');
      return renderHtmlReport(await snapshot(values[0]), values[1]);
    }
    case 'rolling':
    case 'absence-runs': {
      requireArgs(values, 2);
      if (!/^[1-9]\d*$/.test(values[1])) throw new TypeError('count must be a positive integer');
      const data = await snapshot(values[0]);
      const analyze = command === 'rolling' ? rollingAttendance : findConsecutiveAbsences;
      return json(analyze(data.roster, data.sessionIds, data.records, Number(values[1])));
    }
    case 'forecast': {
      requireArgs(values, 3);
      const data = await snapshot(values[0]);
      if (!/^\d+$/.test(values[1]) || !/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/.test(values[2])) {
        throw new TypeError('remaining must be a non-negative integer and target a fraction from 0 to 1');
      }
      return json(forecastRoster(data.roster, data.sessionIds, data.records, Number(values[1]), Number(values[2])));
    }
    case 'policy': {
      requireArgs(values, 2);
      const [data, policy] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      return json(evaluatePolicy(data, JSON.parse(policy)));
    }
    case 'scenario-new': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected snapshot, title and optional policy file');
      const [data, policyText] = await Promise.all([
        snapshot(values[0]), values[2] ? readText(values[2]) : Promise.resolve(null),
      ]);
      return serializeScenario(createScenario(data, { title: values[1], policy: policyText ? JSON.parse(policyText) : null }));
    }
    case 'scenario-set': {
      requireArgs(values, 4);
      const scenario = parseScenario(await readText(values[0]));
      return serializeScenario(setScenarioChange(scenario, values[1], values[2], values[3]));
    }
    case 'scenario-remove': {
      requireArgs(values, 3);
      const scenario = parseScenario(await readText(values[0]));
      return serializeScenario(removeScenarioChange(scenario, values[1], values[2]));
    }
    case 'scenario-evaluate':
    case 'scenario-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected scenario and optional current snapshot');
      const scenario = parseScenario(await readText(values[0]));
      const evaluation = values[1]
        ? evaluateScenario(scenario, await snapshot(values[1]))
        : evaluateScenario(scenario);
      if (command === 'scenario-csv') return scenarioToCsv(evaluation);
      return json(evaluation);
    }
    case 'audit':
    case 'audit-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional audit options file');
      const [data, optionsText] = await Promise.all([
        snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve(null),
      ]);
      const result = auditAttendanceSnapshot(data, optionsText ? JSON.parse(optionsText) : {});
      return command === 'audit-csv' ? auditToCsv(result) : json(result);
    }
    case 'anomaly-scan':
    case 'anomaly-scan-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional anomaly options file');
      const [data, optionsText] = await Promise.all([
        snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve(null),
      ]);
      const result = detectAttendanceAnomalies(data, optionsText ? JSON.parse(optionsText) : {});
      return command === 'anomaly-scan-csv' ? anomaliesToCsv(result) : json(result);
    }
    case 'fpt-policy':
    case 'fpt-policy-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional FPT policy options file');
      const [data, optionsText] = await Promise.all([
        snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve(null),
      ]);
      const result = evaluateFptAttendancePolicy(
        data.roster,
        data.sessionIds,
        data.records,
        optionsText ? JSON.parse(optionsText) : {},
      );
      return command === 'fpt-policy-csv' ? `${fptPolicyReportToCsv(result)}\r\n` : json(result);
    }
    case 'preview-import': {
      requireArgs(values, 3);
      const [rosterCsv, sessions, attendanceCsv] = await Promise.all(values.map(readText));
      return json(previewAttendanceImport({ rosterCsv, sessions, attendanceCsv }));
    }
    case 'apply': {
      requireArgs(values, 2);
      const [data, changes] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const result = applyAttendanceBatch(data, JSON.parse(changes));
      if (result.conflicts.length) throw new Error(`conflicting changes: ${JSON.stringify(result.conflicts)}`);
      return `${serializeAttendanceSnapshot(result.snapshot)}\n`;
    }
    case 'compare': {
      requireArgs(values, 2);
      const [before, after] = await Promise.all(values.map(snapshot));
      return json(compareAttendanceSnapshots(before, after));
    }
    case 'export-csv': {
      requireArgs(values, 1);
      const data = await snapshot(values[0]);
      return `${attendanceToCsv(data.records)}\r\n`;
    }
    case 'set-roster':
    case 'set-sessions': {
      if (values.length < 2 || values.length > 3 || (values.length === 3 && values[2] !== '--drop-records')) {
        throw new TypeError('expected snapshot, input file and optional --drop-records');
      }
      const [data, source] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const options = { dropRecords: values.length === 3 };
      if (command === 'set-roster') {
        const result = importRosterCsv(source);
        if (result.errors.length) throw new Error(`CSV validation failed: ${JSON.stringify(result.errors)}`);
        options.roster = result.students;
      } else {
        options.sessionIds = JSON.parse(source);
      }
      return `${serializeAttendanceSnapshot(reviseSnapshot(data, options).snapshot)}\n`;
    }
    case 'bundle-new': {
      requireArgs(values, 0);
      return `${serializeBundle(createBundle())}\n`;
    }
    case 'bundle-put': {
      requireArgs(values, 4);
      const [source, data] = await Promise.all([readText(values[0]), snapshot(values[3])]);
      return `${serializeBundle(putClass(parseBundle(source), values[1], values[2], data))}\n`;
    }
    case 'bundle-remove': {
      requireArgs(values, 2);
      return `${serializeBundle(removeClass(parseBundle(await readText(values[0])), values[1]))}\n`;
    }
    case 'bundle-report': {
      requireArgs(values, 1);
      return json(summarizeBundle(parseBundle(await readText(values[0]))));
    }
    case 'bundle-students': {
      requireArgs(values, 1);
      return json(summarizeStudentsAcrossClasses(parseBundle(await readText(values[0]))));
    }
    case 'bundle-extract': {
      requireArgs(values, 2);
      return `${serializeAttendanceSnapshot(getClassSnapshot(parseBundle(await readText(values[0])), values[1]))}\n`;
    }
    case 'schedule-generate': {
      requireArgs(values, 1);
      return json(generateRecurringSessions(JSON.parse(await readText(values[0]))));
    }
    case 'schedule-conflicts': {
      requireArgs(values, 1);
      return json(findScheduleConflicts(JSON.parse(await readText(values[0]))));
    }
    case 'schedule-calendar': {
      if (values.length < 3 || values.length > 4) throw new TypeError('expected schedule, domain, timestamp and optional title');
      return sessionsToICalendar(JSON.parse(await readText(values[0])),
        { uidDomain: values[1], generatedAt: values[2], title: values[3] });
    }
    case 'schedule-plan': {
      requireArgs(values, 1);
      return json(planSchedule(JSON.parse(await readText(values[0]))));
    }
    case 'archive-new': {
      requireArgs(values, 2);
      return serializeArchive(createArchive(await snapshot(values[0]), { title: values[1] }));
    }
    case 'archive-add': {
      if (values.length < 3 || values.length > 4) throw new TypeError('expected archive, snapshot, message and optional author');
      const [archiveText, data] = await Promise.all([readText(values[0]), snapshot(values[1])]);
      return serializeArchive(appendArchiveRevision(parseArchive(archiveText), data, { message: values[2], author: values[3] }));
    }
    case 'archive-list': {
      requireArgs(values, 1);
      return json(listArchiveRevisions(parseArchive(await readText(values[0]))));
    }
    case 'archive-compare': {
      requireArgs(values, 3);
      return json(compareArchiveRevisions(parseArchive(await readText(values[0])), values[1], values[2]));
    }
    case 'archive-restore': {
      if (values.length < 3 || values.length > 4) throw new TypeError('expected archive, revision ID, message and optional author');
      const archive = parseArchive(await readText(values[0]));
      return serializeArchive(restoreArchiveRevision(archive, values[1], { message: values[2], author: values[3] }));
    }
    case 'archive-csv': {
      requireArgs(values, 1);
      return archiveToCsv(parseArchive(await readText(values[0])));
    }
    case 'demo-generate':
    case 'demo-manifest': {
      if (values.length > 1) throw new TypeError('expected optional synthetic dataset options file');
      const options = values[0] ? JSON.parse(await readText(values[0])) : {};
      const dataset = generateSyntheticDataset(options);
      return command === 'demo-manifest' ? json(dataset.manifest) : `${serializeAttendanceSnapshot(dataset.snapshot)}\n`;
    }
    case 'demo-profiles': {
      requireArgs(values, 0);
      return json(listSyntheticProfiles());
    }
    case 'demo-summary': {
      requireArgs(values, 1);
      return json(summarizeDatasetSnapshot(await snapshot(values[0])));
    }
    case 'anonymize-snapshot':
    case 'anonymize-report': {
      requireArgs(values, 2);
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const options = JSON.parse(optionsText);
      const anonymized = anonymizeSnapshot(data, options);
      return command === 'anonymize-report' ? json(anonymizationReport(data, anonymized))
        : `${serializeAttendanceSnapshot(anonymized)}\n`;
    }
    case 'anonymize-bundle': {
      requireArgs(values, 2);
      const [bundle, optionsText] = await Promise.all([readText(values[0]), readText(values[1])]);
      const anonymized = anonymizeBundle(bundle, JSON.parse(optionsText));
      return `${JSON.stringify(anonymized, null, 2)}\n`;
    }
    case 'anonymize-archive': {
      requireArgs(values, 2);
      const [archive, optionsText] = await Promise.all([readText(values[0]), readText(values[1])]);
      return `${JSON.stringify(anonymizeArchive(archive, JSON.parse(optionsText)), null, 2)}\n`;
    }
    case 'map-suggest': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected CSV file, roster or attendance, and optional delimiter');
      const parsed = parseDelimitedCsv(await readText(values[0]), { delimiter: values[2] });
      if (!parsed.rows.length) throw new TypeError('CSV must have a header');
      return json(suggestHeaderMapping(parsed.rows[0].fields.map((field) => field.trim()), values[1]));
    }
    case 'map-preview':
    case 'map-issues-csv': {
      if (values.length < 3 || values.length > 4) throw new TypeError('expected roster CSV, attendance CSV, sessions JSON and optional mapping options JSON');
      const [rosterCsv, attendanceCsv, sessionsText, optionsText] = await Promise.all([
        readText(values[0]), readText(values[1]), readText(values[2]), values[3] ? readText(values[3]) : Promise.resolve('{}'),
      ]);
      const config = JSON.parse(optionsText);
      if (!config || typeof config !== 'object' || Array.isArray(config)) throw new TypeError('mapping options must be an object');
      const preview = previewMappedImport({ rosterCsv, attendanceCsv, sessions: sessionsText,
        rosterOptions: config.rosterOptions, attendanceOptions: config.attendanceOptions });
      return command === 'map-issues-csv' ? mappedImportIssuesToCsv(preview) : json(preview);
    }
    case 'review-plan':
    case 'review-plan-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional review options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      const plan = buildReviewPlan(data, JSON.parse(optionsText));
      return command === 'review-plan-csv' ? reviewPlanToCsv(plan) : json(plan);
    }
    case 'review-allocate': {
      requireArgs(values, 2);
      const [planText, reviewersText] = await Promise.all(values.map(readText));
      return json(allocateReviewCases(JSON.parse(planText), JSON.parse(reviewersText)));
    }
    case 'review-allocate-constrained': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected plan, reviewers and optional allocation options JSON');
      const [planText, reviewersText, optionsText] = await Promise.all([
        readText(values[0]), readText(values[1]), values[2] ? readText(values[2]) : Promise.resolve('{}'),
      ]);
      return json(allocateReviewCasesConstrained(JSON.parse(planText), JSON.parse(reviewersText), JSON.parse(optionsText)));
    }
    case 'review-allocate-csv': {
      requireArgs(values, 2);
      const allocationText = await readText(values[0]);
      return reviewAllocationToCsv(JSON.parse(allocationText), values[1]);
    }
    case 'review-board':
    case 'review-board-csv': {
      const csvMode = command === 'review-board-csv';
      if (values.length < (csvMode ? 4 : 3) || values.length > (csvMode ? 5 : 4)) {
        throw new TypeError(csvMode
          ? 'expected casebook, review plan, reviewers, section and optional options JSON'
          : 'expected casebook, review plan, reviewers and optional options JSON');
      }
      const optionsPath = values[csvMode ? 4 : 3];
      const [bookText, planText, reviewersText, optionsText] = await Promise.all([
        readText(values[0]), readText(values[1]), readText(values[2]),
        optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = planReviewBoard(JSON.parse(bookText), JSON.parse(planText), JSON.parse(reviewersText), JSON.parse(optionsText));
      return csvMode ? reviewBoardToCsv(report, values[3]) : json(report);
    }
    case 'casebook-new': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected review plan and optional casebook options JSON');
      const [planText, optionsText] = await Promise.all([readText(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      return serializeCasebook(createCasebook(JSON.parse(planText), JSON.parse(optionsText)));
    }
    case 'casebook-batch': {
      requireArgs(values, 2);
      const [bookText, batchText] = await Promise.all(values.map(readText));
      return serializeCasebook(applyCasebookBatch(parseCasebook(bookText), JSON.parse(batchText)));
    }
    case 'casebook-update': {
      requireArgs(values, 3);
      const [bookText, actionText] = await Promise.all([readText(values[0]), readText(values[2])]);
      const update = JSON.parse(actionText);
      if (!update || typeof update !== 'object' || Array.isArray(update)) throw new TypeError('casebook update must be an object');
      const { action, ...options } = update;
      return serializeCasebook(updateCasebook(parseCasebook(bookText), values[1], action, options));
    }
    case 'casebook-reconcile': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected casebook, review plan and optional options JSON');
      const [bookText, planText, optionsText] = await Promise.all([readText(values[0]), readText(values[1]),
        values[2] ? readText(values[2]) : Promise.resolve('{}')]);
      return serializeCasebook(reconcileCasebook(parseCasebook(bookText), JSON.parse(planText), JSON.parse(optionsText)));
    }
    case 'casebook-summary': {
      requireArgs(values, 1);
      return json(summarizeCasebook(parseCasebook(await readText(values[0]))));
    }
    case 'casebook-sla':
    case 'casebook-sla-csv': {
      if (command === 'casebook-sla' && (values.length < 1 || values.length > 2)) {
        throw new TypeError('expected casebook and optional SLA options JSON');
      }
      if (command === 'casebook-sla-csv' && (values.length < 2 || values.length > 3)) {
        throw new TypeError('expected casebook, CSV section and optional SLA options JSON');
      }
      const optionsPath = values[command === 'casebook-sla' ? 1 : 2];
      const [bookText, optionsText] = await Promise.all([
        readText(values[0]), optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = reportCasebookSla(JSON.parse(bookText), JSON.parse(optionsText));
      return command === 'casebook-sla-csv' ? casebookSlaToCsv(report, values[1]) : json(report);
    }
    case 'casebook-workload':
    case 'casebook-workload-csv': {
      const csvMode = command === 'casebook-workload-csv';
      if (values.length < (csvMode ? 3 : 2) || values.length > (csvMode ? 4 : 3)) {
        throw new TypeError(csvMode
          ? 'expected casebook, reviewers, CSV section and optional options JSON'
          : 'expected casebook, reviewers and optional options JSON');
      }
      const optionsPath = values[csvMode ? 3 : 2];
      const [bookText, reviewerText, optionsText] = await Promise.all([
        readText(values[0]), readText(values[1]), optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = reportCasebookWorkload(JSON.parse(bookText), JSON.parse(reviewerText), JSON.parse(optionsText));
      return csvMode ? casebookWorkloadToCsv(report, values[2]) : json(report);
    }
    case 'casebook-activity':
    case 'casebook-activity-csv': {
      const csvMode = command === 'casebook-activity-csv';
      if (values.length < (csvMode ? 2 : 1) || values.length > (csvMode ? 3 : 2)) {
        throw new TypeError(csvMode
          ? 'expected casebook, CSV section and optional activity options JSON'
          : 'expected casebook and optional activity options JSON');
      }
      const optionsPath = values[csvMode ? 2 : 1];
      const [bookText, optionsText] = await Promise.all([
        readText(values[0]), optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = reportCasebookActivity(JSON.parse(bookText), JSON.parse(optionsText));
      return csvMode ? casebookActivityToCsv(report, values[1]) : json(report);
    }
    case 'casebook-service-level':
    case 'casebook-service-level-csv': {
      const csvMode = command === 'casebook-service-level-csv';
      if (values.length < (csvMode ? 2 : 1) || values.length > (csvMode ? 3 : 2)) {
        throw new TypeError(csvMode
          ? 'expected casebook, CSV section and optional service-level options JSON'
          : 'expected casebook and optional service-level options JSON');
      }
      const optionsPath = values[csvMode ? 2 : 1];
      const [bookText, optionsText] = await Promise.all([
        readText(values[0]), optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = evaluateCasebookServiceLevels(JSON.parse(bookText), JSON.parse(optionsText));
      return csvMode ? casebookServiceLevelsToCsv(report, values[1]) : json(report);
    }
    case 'casebook-csv': {
      if (values.length < 1 || values.length > 2 || (values.length === 2 && values[1] !== '--include-notes')) {
        throw new TypeError('expected casebook and optional --include-notes');
      }
      return casebookToCsv(parseCasebook(await readText(values[0])), { includeNotes: values.length === 2 });
    }
    case 'casebook-events':
    case 'casebook-events-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected casebook and optional event filter options JSON');
      const [bookText, optionsText] = await Promise.all([readText(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      const events = listCasebookEvents(parseCasebook(bookText), JSON.parse(optionsText));
      return command === 'casebook-events' ? json(events) : casebookEventsToCsv(events);
    }
    case 'casebook-history-audit':
    case 'casebook-history-audit-csv': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected casebook and optional audit options JSON');
      const [bookText, optionsText] = await Promise.all([readText(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      const audit = auditCasebookHistory(parseCasebook(bookText), JSON.parse(optionsText));
      return command === 'casebook-history-audit' ? json(audit) : casebookHistoryAuditToCsv(audit);
    }
    case 'report-studio':
    case 'report-html-studio': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional report options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      const report = buildReportStudio(data, JSON.parse(optionsText));
      return command === 'report-html-studio' ? renderReportStudioHtml(report) : json(report);
    }
    case 'report-csv-studio': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected snapshot, report section and optional options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), values[2] ? readText(values[2]) : Promise.resolve('{}')]);
      return reportStudioToCsv(buildReportStudio(data, JSON.parse(optionsText)), values[1]);
    }
    case 'closeout-pack': {
      if (values.length < 1 || values.length > 2) throw new TypeError('expected snapshot and optional closeout options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), values[1] ? readText(values[1]) : Promise.resolve('{}')]);
      return serializeCloseoutPackage(buildCloseoutPackage(data, JSON.parse(optionsText)));
    }
    case 'closeout-inspect':
    case 'closeout-inspect-csv': {
      requireArgs(values, 1);
      const inspection = inspectCloseoutPackage(await readText(values[0]));
      return command === 'closeout-inspect' ? json(inspection) : closeoutInspectionToCsv(inspection);
    }
    case 'closeout-extract': {
      requireArgs(values, 2);
      return readCloseoutFile(await readText(values[0]), values[1]);
    }
    case 'closeout-compare':
    case 'closeout-compare-csv': {
      requireArgs(values, 2);
      const [before, after] = await Promise.all(values.map(readText));
      const comparison = compareCloseoutPackages(before, after);
      return command === 'closeout-compare' ? json(comparison) : closeoutComparisonToCsv(comparison);
    }
    case 'policy-grid': {
      requireArgs(values, 1);
      return json(createPolicyGrid(JSON.parse(await readText(values[0]))));
    }
    case 'policy-lab':
    case 'policy-lab-csv': {
      if (values.length !== (command === 'policy-lab' ? 2 : 3)) {
        throw new TypeError(command === 'policy-lab' ? 'expected snapshot and options JSON' : 'expected snapshot, options JSON and summary, cohorts, students or comparisons section');
      }
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const lab = buildPolicyLab(data, JSON.parse(optionsText));
      return command === 'policy-lab' ? json(lab) : policyLabToCsv(lab, values[2]);
    }
    case 'snapshot-query':
    case 'snapshot-query-csv': {
      if (values.length !== (command === 'snapshot-query' ? 2 : 3)) {
        throw new TypeError(command === 'snapshot-query' ? 'expected snapshot and query JSON' : 'expected snapshot, query JSON and rows or groups section');
      }
      const [data, queryText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const result = queryAttendanceSnapshot(data, JSON.parse(queryText));
      return command === 'snapshot-query' ? json(result) : attendanceQueryToCsv(result, values[2]);
    }
    case 'snapshot-query-diff':
    case 'snapshot-query-diff-csv': {
      const csvMode = command === 'snapshot-query-diff-csv';
      if (values.length < (csvMode ? 3 : 2) || values.length > (csvMode ? 4 : 3)) {
        throw new TypeError(csvMode ? 'expected before, after, section and optional query JSON' : 'expected before, after and optional query JSON');
      }
      const [before, after, queryText] = await Promise.all([snapshot(values[0]), snapshot(values[1]),
        values[csvMode ? 3 : 2] ? readText(values[csvMode ? 3 : 2]) : Promise.resolve('{}')]);
      const diff = compareAttendanceQueryResults(before, after, JSON.parse(queryText));
      return csvMode ? attendanceQueryDiffToCsv(diff, values[2]) : json(diff);
    }
    case 'attendance-impact-diff':
    case 'attendance-impact-diff-csv': {
      const csvMode = command === 'attendance-impact-diff-csv';
      if (values.length < (csvMode ? 3 : 2) || values.length > (csvMode ? 4 : 3)) {
        throw new TypeError(csvMode
          ? 'expected before, after, section and optional impact options JSON'
          : 'expected before, after and optional impact options JSON');
      }
      const optionsPath = values[csvMode ? 3 : 2];
      const [before, after, optionsText] = await Promise.all([
        snapshot(values[0]), snapshot(values[1]), optionsPath === undefined ? Promise.resolve('{}') : readText(optionsPath),
      ]);
      const report = compareAttendanceImpact(before, after, JSON.parse(optionsText));
      return csvMode ? attendanceImpactDiffToCsv(report, values[2]) : json(report);
    }
    case 'cohort-explore':
    case 'cohort-explore-csv': {
      const csvMode = command === 'cohort-explore-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected snapshot, options JSON and cohorts, sessions, comparisons or students section'
        : 'expected snapshot and cohort options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const report = buildCohortExplorer(data, JSON.parse(optionsText));
      return csvMode ? cohortExplorerToCsv(report, values[2]) : json(report);
    }
    case 'schedule-insights':
    case 'schedule-insights-csv': {
      const csvMode = command === 'schedule-insights-csv';
      if (values.length < (csvMode ? 2 : 1) || values.length > (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected schedule, section and optional options JSON' : 'expected schedule and optional options JSON');
      const [scheduleText, optionsText] = await Promise.all([readText(values[0]), values[csvMode ? 2 : 1]
        ? readText(values[csvMode ? 2 : 1]) : Promise.resolve('{}')]);
      const report = analyzeScheduleInsights(JSON.parse(scheduleText), JSON.parse(optionsText));
      return csvMode ? scheduleInsightsToCsv(report, values[1]) : json(report);
    }
    case 'source-reconcile':
    case 'source-reconcile-csv': {
      const csvMode = command === 'source-reconcile-csv';
      if (values.length < (csvMode ? 2 : 1) || values.length > (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected source list, section and optional options JSON' : 'expected source list and optional options JSON');
      const configPath = resolve(values[0]);
      const [sourceText, optionsText] = await Promise.all([readText(configPath), values[csvMode ? 2 : 1]
        ? readText(values[csvMode ? 2 : 1]) : Promise.resolve('{}')]);
      const definitions = JSON.parse(sourceText);
      if (!Array.isArray(definitions)) throw new TypeError('source list must be a JSON array');
      const sources = await Promise.all(definitions.map(async (definition) => {
        if (definition.snapshotFile === undefined) return definition;
        const snapshotFile = resolve(dirname(configPath), definition.snapshotFile);
        const { snapshotFile: ignored, ...source } = definition;
        return { ...source, snapshot: await snapshot(snapshotFile) };
      }));
      const plan = reconcileAttendanceSources(sources, JSON.parse(optionsText));
      return csvMode ? reconciliationToCsv(plan, values[1]) : json(plan);
    }
    case 'correction-new': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected snapshot, proposals JSON and optional review options JSON');
      const [data, proposalsText, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1]),
        values[2] ? readText(values[2]) : Promise.resolve('{}')]);
      return serializeCorrectionReview(createCorrectionReview(data, JSON.parse(proposalsText), JSON.parse(optionsText)));
    }
    case 'correction-update': {
      requireArgs(values, 3);
      const [reviewText, updateText] = await Promise.all([readText(values[0]), readText(values[2])]);
      const update = JSON.parse(updateText);
      if (!update || typeof update !== 'object' || Array.isArray(update)) throw new TypeError('correction update must be an object');
      const { action, ...options } = update;
      return serializeCorrectionReview(updateCorrectionCase(parseCorrectionReview(reviewText), values[1], action, options));
    }
    case 'correction-apply': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected review, current snapshot and optional review revision');
      const [reviewText, data] = await Promise.all([readText(values[0]), snapshot(values[1])]);
      const options = values[2] === undefined ? {} : { expectedReviewRevision: Number(values[2]) };
      return json(applyApprovedCorrections(parseCorrectionReview(reviewText), data, options));
    }
    case 'correction-audit':
    case 'correction-audit-csv': {
      requireArgs(values, 2);
      const [reviewText, data] = await Promise.all([readText(values[0]), snapshot(values[1])]);
      const audit = auditCorrectionReview(parseCorrectionReview(reviewText), data);
      return command === 'correction-audit-csv' ? correctionAuditToCsv(audit) : json(audit);
    }
    case 'correction-summary': {
      requireArgs(values, 1);
      return json(summarizeCorrectionReview(parseCorrectionReview(await readText(values[0]))));
    }
    case 'correction-csv': {
      if (values.length < 1 || values.length > 2 || (values.length === 2 && values[1] !== '--include-notes')) {
        throw new TypeError('expected review and optional --include-notes');
      }
      return correctionReviewToCsv(parseCorrectionReview(await readText(values[0])), { includeNotes: values.length === 2 });
    }
    case 'retention-plan':
    case 'retention-plan-csv': {
      const csvMode = command === 'retention-plan-csv';
      if (values.length < (csvMode ? 3 : 2) || values.length > (csvMode ? 4 : 3)) throw new TypeError(csvMode
        ? 'expected inventory, policies, section and optional options JSON' : 'expected inventory, policies and optional options JSON');
      const [inventoryText, policiesText, optionsText] = await Promise.all([readText(values[0]), readText(values[1]),
        values[csvMode ? 3 : 2] ? readText(values[csvMode ? 3 : 2]) : Promise.resolve('{}')]);
      const plan = buildRetentionPlan(JSON.parse(inventoryText), JSON.parse(policiesText), JSON.parse(optionsText));
      return csvMode ? retentionPlanToCsv(plan, values[2]) : json(plan);
    }
    case 'export-plan':
    case 'export-approve': {
      const approve = command === 'export-approve';
      const minimum = approve ? 4 : 3;
      if (values.length < minimum || values.length > minimum + 1) throw new TypeError(approve
        ? 'expected snapshot, policy, request, approval and optional options JSON'
        : 'expected snapshot, policy, request and optional options JSON');
      const [data, policyText, requestText, approvalText, optionsText] = await Promise.all([
        snapshot(values[0]), readText(values[1]), readText(values[2]),
        approve ? readText(values[3]) : Promise.resolve(null),
        values[approve ? 4 : 3] ? readText(values[approve ? 4 : 3]) : Promise.resolve('{}'),
      ]);
      const policy = JSON.parse(policyText);
      const request = JSON.parse(requestText);
      const options = JSON.parse(optionsText);
      const result = approve
        ? approveGovernedExport(data, policy, request, JSON.parse(approvalText), options)
        : planGovernedExport(data, policy, request, options);
      return json(result);
    }
    case 'governed-export-csv': {
      requireArgs(values, 1);
      return governedExportToCsv(JSON.parse(await readText(values[0])));
    }
    case 'exemption-new': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected snapshot, proposals JSON and optional ledger options JSON');
      const [data, proposalText, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1]),
        values[2] ? readText(values[2]) : Promise.resolve('{}')]);
      return serializeExemptionLedger(createExemptionLedger(data, JSON.parse(proposalText), JSON.parse(optionsText)));
    }
    case 'exemption-update': {
      requireArgs(values, 3);
      const [ledgerText, updateText] = await Promise.all([readText(values[0]), readText(values[2])]);
      const update = JSON.parse(updateText);
      if (!update || typeof update !== 'object' || Array.isArray(update)) throw new TypeError('exemption update must be an object');
      const { action, ...options } = update;
      return serializeExemptionLedger(updateExemption(parseExemptionLedger(ledgerText), values[1], action, options));
    }
    case 'exemption-report':
    case 'exemption-report-csv': {
      const csvMode = command === 'exemption-report-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected ledger, snapshot and class, students or sessions section' : 'expected ledger and current snapshot');
      const [ledgerText, data] = await Promise.all([readText(values[0]), snapshot(values[1])]);
      const report = evaluateExemptionLedger(parseExemptionLedger(ledgerText), data);
      return csvMode ? exemptionToCsv(report, values[2]) : json(report);
    }
    case 'exemption-summary': {
      requireArgs(values, 1);
      return json(summarizeExemptionLedger(parseExemptionLedger(await readText(values[0]))));
    }
    case 'exemption-csv': {
      requireArgs(values, 1);
      return exemptionToCsv(parseExemptionLedger(await readText(values[0])));
    }
    case 'patterns':
    case 'patterns-csv': {
      const csvMode = command === 'patterns-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected snapshot, options JSON and windows, cohorts, sessions or students section'
        : 'expected snapshot and pattern options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const report = analyzeAttendancePatterns(data, JSON.parse(optionsText));
      return csvMode ? attendancePatternsToCsv(report, values[2]) : json(report);
    }
    case 'forecast-evaluate':
    case 'forecast-evaluate-csv': {
      const csvMode = command === 'forecast-evaluate-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected snapshot, options JSON and metrics, cohorts, calibration, comparisons or students section'
        : 'expected snapshot and forecast evaluation options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const report = evaluateAttendanceForecasts(data, JSON.parse(optionsText));
      return csvMode ? forecastEvaluationToCsv(report, values[2]) : json(report);
    }
    case 'recovery-plan':
    case 'recovery-plan-csv': {
      const csvMode = command === 'recovery-plan-csv';
      if (values.length !== (csvMode ? 4 : 3)) throw new TypeError(csvMode
        ? 'expected snapshot, policy, options JSON and summary, cohorts or students section'
        : 'expected snapshot, policy and recovery options JSON');
      const [data, policyText, optionsText] = await Promise.all([
        snapshot(values[0]), readText(values[1]), readText(values[2]),
      ]);
      const report = planAttendanceRecovery(data, JSON.parse(policyText), JSON.parse(optionsText));
      return csvMode ? recoveryPlanToCsv(report, values[3]) : json(report);
    }
    case 'migration-plan':
    case 'migration-plan-csv': {
      const csvMode = command === 'migration-plan-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected snapshot, migration options JSON and issues, conflicts or records section'
        : 'expected snapshot and migration options JSON');
      const [data, optionsText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const plan = planSnapshotMigration(data, JSON.parse(optionsText));
      return csvMode ? snapshotMigrationToCsv(plan, values[2]) : json(plan);
    }
    case 'contract-check':
    case 'contract-check-csv': {
      const csvMode = command === 'contract-check-csv';
      if (values.length !== (csvMode ? 3 : 2)) throw new TypeError(csvMode
        ? 'expected snapshot, contract and checks or summary section' : 'expected snapshot and contract JSON');
      const [data, contractText] = await Promise.all([snapshot(values[0]), readText(values[1])]);
      const report = validateSnapshotContract(data, parseSnapshotContract(contractText));
      return csvMode ? snapshotContractToCsv(report, values[2]) : json(report);
    }
    case 'release-plan': {
      if (values.length < 2 || values.length > 3) throw new TypeError('expected snapshot, contract and optional release options JSON');
      const [data, contractText, optionsText] = await Promise.all([
        snapshot(values[0]), readText(values[1]), values[2] ? readText(values[2]) : Promise.resolve('{}'),
      ]);
      return json(planSnapshotRelease(data, contractText, JSON.parse(optionsText)));
    }
    case 'release-decide': {
      requireArgs(values, 2);
      const [planText, approvalText] = await Promise.all(values.map(readText));
      return json(decideSnapshotRelease(JSON.parse(planText), JSON.parse(approvalText)));
    }
    case 'release-verify': {
      requireArgs(values, 3);
      const [receiptText, data, contractText] = await Promise.all([
        readText(values[0]), snapshot(values[1]), readText(values[2]),
      ]);
      return json(verifySnapshotReleaseReceipt(receiptText, data, contractText));
    }
    case 'release-csv': {
      requireArgs(values, 1);
      return snapshotReleaseToCsv(JSON.parse(await readText(values[0])));
    }
    case 'release-compare':
    case 'release-compare-csv': {
      requireArgs(values, 2);
      const [beforeText, afterText] = await Promise.all(values.map(readText));
      const diff = compareSnapshotReleaseReceipts(beforeText, afterText);
      return command === 'release-compare-csv' ? snapshotReleaseDiffToCsv(diff) : json(diff);
    }
    default:
      throw new TypeError(`unknown command: ${command}; use --help`);
  }
}

// Keep importing the module side-effect free for tests and other local tools.
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    process.stdout.write(await runCommand(process.argv.slice(2)));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
