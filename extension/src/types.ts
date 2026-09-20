export type AttendanceStatus = 'P' | 'A';

export interface AttendanceCsvRow {
  schema_version: string;
  semester: string;
  course_code: string;
  class_code: string;
  schedule_code: string;
  meeting_id: string;
  meeting_number: string;
  meeting_date: string;
  start_time: string;
  end_time: string;
  roll_number: string;
  member_code: string;
  email: string;
  full_name: string;
  status: AttendanceStatus;
  recorded_at: string;
  source: string;
}

export interface MappingPreview {
  pageCount: number;
  csvCount: number;
  present: number;
  absent: number;
  missingOnPage: string[];
  missingInCsv: string[];
  duplicates: string[];
  metadataWarnings: string[];
}
