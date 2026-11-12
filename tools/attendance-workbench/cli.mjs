#!/usr/bin/env node
// A local, opt-in command-line interface. Commands read named inputs and write
// results to stdout; they never start the application's server or contact it.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
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

const usage = `Attendance workbench (Node.js 22+)

  node cli.mjs init ROSTER.csv SESSIONS.json ATTENDANCE.csv
  node cli.mjs report SNAPSHOT.json
  node cli.mjs report-html SNAPSHOT.json [TITLE]
  node cli.mjs rolling SNAPSHOT.json WINDOW_SIZE
  node cli.mjs absence-runs SNAPSHOT.json MINIMUM
  node cli.mjs forecast SNAPSHOT.json REMAINING TARGET
  node cli.mjs policy SNAPSHOT.json POLICY.json
  node cli.mjs scenario-new SNAPSHOT.json TITLE [POLICY.json]
  node cli.mjs scenario-set SCENARIO.json STUDENT_ID SESSION_ID present|absent|missing
  node cli.mjs scenario-remove SCENARIO.json STUDENT_ID SESSION_ID
  node cli.mjs scenario-evaluate SCENARIO.json [CURRENT_SNAPSHOT.json]
  node cli.mjs scenario-csv SCENARIO.json [CURRENT_SNAPSHOT.json]
  node cli.mjs audit SNAPSHOT.json [OPTIONS.json]
  node cli.mjs audit-csv SNAPSHOT.json [OPTIONS.json]
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
