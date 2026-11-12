import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const severityOrder = { high: 0, medium: 1, low: 2 };

function rate(value, name) {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${name} must be between 0 and 1`);
  }
  return value;
}

function count(value, name, minimum = 1) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    throw new RangeError(`${name} must be an integer of at least ${minimum}`);
  }
  return value;
}

function normalizeOptions(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('options must be an object');
  }
  return {
    sessionDropThreshold: rate(value.sessionDropThreshold ?? 0.35, 'sessionDropThreshold'),
    studentDropoffThreshold: rate(value.studentDropoffThreshold ?? 0.5, 'studentDropoffThreshold'),
    minimumSessionRecords: count(value.minimumSessionRecords ?? 2, 'minimumSessionRecords', 1),
    alternationLength: count(value.alternationLength ?? 4, 'alternationLength', 3),
  };
}

function anomaly(code, severity, subject, description, details = {}) {
  return {
    id: `${code}:${subject}`,
    code,
    severity,
    subject,
    description,
    ...details,
  };
}

function longestAlternatingRun(statuses) {
  if (statuses.length === 0) return 0;
  let longest = 1;
  let current = 1;
  for (let i = 1; i < statuses.length; i++) {
    if (statuses[i] !== statuses[i - 1]) {
      current++;
      if (current > longest) longest = current;
    } else {
      current = 1;
    }
  }
  return longest;
}

/**
 * Scan an attendance snapshot for statistical and behavioral anomalies:
 * - sudden session-to-session attendance rate drops
 * - sessions where every recorded student is marked absent
 * - students with severe second-half attendance drop-off
 * - students with long alternating Present/Absent sequences
 */
export function detectAttendanceAnomalies(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = normalizeOptions(optionsValue);
  const quality = attendanceQualityReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const anomalies = [];

  let previousSessionRate = null;
  let previousSessionId = null;

  for (const session of quality.sessions) {
    const recorded = session.present + session.absent;
    if (recorded < options.minimumSessionRecords) continue;
    const currentRate = session.present / recorded;

    if (session.present === 0 && session.absent >= options.minimumSessionRecords) {
      anomalies.push(anomaly(
        'session_uniform_absent',
        'high',
        session.sessionId,
        `Session ${session.sessionId} has 100% absent across all ${recorded} recorded students.`,
        { sessionId: session.sessionId, present: 0, absent: session.absent, rate: 0 },
      ));
    }

    if (previousSessionRate !== null && previousSessionRate - currentRate >= options.sessionDropThreshold) {
      anomalies.push(anomaly(
        'session_sudden_drop',
        'medium',
        session.sessionId,
        `Session ${session.sessionId} attendance dropped from ${Math.round(previousSessionRate * 100)}% (${previousSessionId}) to ${Math.round(currentRate * 100)}%.`,
        {
          sessionId: session.sessionId,
          previousSessionId,
          previousRate: Number(previousSessionRate.toFixed(4)),
          currentRate: Number(currentRate.toFixed(4)),
          drop: Number((previousSessionRate - currentRate).toFixed(4)),
        },
      ));
    }

    previousSessionRate = currentRate;
    previousSessionId = session.sessionId;
  }

  const recordMap = new Map();
  for (const record of snapshot.records) {
    recordMap.set(`${record.studentId}\0${record.sessionId}`, record.status);
  }

  for (const student of snapshot.roster) {
    const orderedStatuses = [];
    for (const sessionId of snapshot.sessionIds) {
      const status = recordMap.get(`${student.id}\0${sessionId}`);
      if (status === 'present' || status === 'absent') {
        orderedStatuses.push({ sessionId, status });
      }
    }

    if (orderedStatuses.length >= 4) {
      const midpoint = Math.floor(orderedStatuses.length / 2);
      const firstHalf = orderedStatuses.slice(0, midpoint);
      const secondHalf = orderedStatuses.slice(midpoint);
      const firstRate = firstHalf.filter((item) => item.status === 'present').length / firstHalf.length;
      const secondRate = secondHalf.filter((item) => item.status === 'present').length / secondHalf.length;
      if (firstRate >= 0.75 && firstRate - secondRate >= options.studentDropoffThreshold) {
        anomalies.push(anomaly(
          'late_semester_dropoff',
          'high',
          student.id,
          `${student.name} (${student.id}) dropped from ${Math.round(firstRate * 100)}% in early sessions to ${Math.round(secondRate * 100)}% in later sessions.`,
          {
            studentId: student.id,
            firstHalfRate: Number(firstRate.toFixed(4)),
            secondHalfRate: Number(secondRate.toFixed(4)),
            dropoff: Number((firstRate - secondRate).toFixed(4)),
          },
        ));
      }
    }

    const altRun = longestAlternatingRun(orderedStatuses.map((item) => item.status));
    if (altRun >= options.alternationLength) {
      anomalies.push(anomaly(
        'status_alternation',
        'low',
        student.id,
        `${student.name} (${student.id}) has an alternating present/absent pattern of length ${altRun}.`,
        {
          studentId: student.id,
          alternationLength: altRun,
        },
      ));
    }
  }

  anomalies.sort((a, b) =>
    severityOrder[a.severity] - severityOrder[b.severity] ||
    a.code.localeCompare(b.code) ||
    a.subject.localeCompare(b.subject));

  const summary = {
    total: anomalies.length,
    high: anomalies.filter((item) => item.severity === 'high').length,
    medium: anomalies.filter((item) => item.severity === 'medium').length,
    low: anomalies.filter((item) => item.severity === 'low').length,
  };

  return {
    version: 1,
    options,
    summary,
    anomalies,
  };
}

/** Export anomaly scan report as formula-safe CSV. */
export function anomaliesToCsv(report) {
  if (!report || report.version !== 1 || !Array.isArray(report.anomalies)) {
    throw new TypeError('invalid anomaly report');
  }
  const csvCell = (value) => {
    let textValue = String(value ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(textValue)) textValue = `'${textValue}`;
    return `"${textValue.replaceAll('"', '""')}"`;
  };
  const header = ['severity', 'code', 'subject', 'description'];
  const rows = report.anomalies.map((item) => [
    item.severity,
    item.code,
    item.subject,
    item.description,
  ]);
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}
