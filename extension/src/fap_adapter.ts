import { normalizeId } from './csv';
import type { AttendanceCsvRow, AttendanceStatus, MappingPreview } from './types';

interface PageRow { ids: string[]; element: HTMLTableRowElement; }

export class FapPageAdapter {
  constructor(private readonly document: Document) {}

  rows(): PageRow[] {
    const tables = [...this.document.querySelectorAll('table')];
    for (const table of tables) {
      const found = [...table.querySelectorAll('tr')]
        .map((element) => ({ element, ids: this.studentIds(element) }))
        .filter((row) => row.ids.length > 0);
      if (found.length) return found;
    }
    return [];
  }

  preview(csv: AttendanceCsvRow[]): MappingPreview {
    const pageRows = this.rows();
    const primaryKeys = csv.map((row) => row.roll_number);
    const allCsvIds = new Set(csv.flatMap((row) => [row.roll_number, row.member_code].filter(Boolean)));
    const duplicates = primaryKeys.filter((id, index) => primaryKeys.indexOf(id) !== index);
    const first = csv[0];
    const rawPageText = this.document.body.innerText ?? this.document.body.textContent ?? '';
    const pageText = normalizeId(rawPageText);
    const warnings: string[] = [];
    const metadata = this.document.querySelector<HTMLElement>('[data-attendance-class]')?.dataset;
    if (metadata?.attendanceFinalized === 'true') {
      warnings.push('Slot này đã chốt danh sách; không thể điền lại.');
    }
    const visibleClassCodes: string[] =
      rawPageText.toUpperCase().match(/\b[A-Z]{2,5}\d{4}/g) ?? [];
    if (metadata?.attendanceClass && normalizeId(metadata.attendanceClass) !== normalizeId(first.class_code)) {
      warnings.push(`Trang đang mở lớp ${metadata.attendanceClass}, file là ${first.class_code}.`);
    } else if (!metadata?.attendanceClass && visibleClassCodes.length && first.class_code &&
        !visibleClassCodes.includes(normalizeId(first.class_code))) {
      warnings.push(`Không tìm thấy mã lớp ${first.class_code} trên trang.`);
    }
    const visibleDates = rawPageText.match(/\b(?:\d{4}-\d{2}-\d{2}|\d{2}\/\d{2}\/\d{4})\b/g) ?? [];
    if (metadata?.attendanceDate && metadata.attendanceDate !== first.meeting_date) {
      warnings.push(`Trang đang mở ngày ${metadata.attendanceDate}, file là ${first.meeting_date}.`);
    } else if (!metadata?.attendanceDate && visibleDates.length && first.meeting_date && !pageText.includes(first.meeting_date) &&
        !pageText.includes(first.meeting_date.split('-').reverse().join('/'))) {
      warnings.push(`Không xác nhận được ngày ${first.meeting_date} trên trang.`);
    }
    const visibleSlot = /\bslot\s*([1-4])\b/i.exec(rawPageText)?.[1];
    const expectedSlot = first.schedule_code?.trim().slice(-1);
    if (metadata?.attendanceSlot && expectedSlot && metadata.attendanceSlot !== expectedSlot) {
      warnings.push(`Trang đang mở slot ${metadata.attendanceSlot}, file là slot ${expectedSlot}.`);
    }
    if (!metadata?.attendanceSlot && visibleSlot && expectedSlot && visibleSlot !== expectedSlot) {
      warnings.push(`CSV là slot ${expectedSlot} nhưng trang FAP là slot ${visibleSlot}.`);
    }
    return {
      pageCount: pageRows.length,
      csvCount: csv.length,
      present: csv.filter((row) => row.status === 'P').length,
      absent: csv.filter((row) => row.status === 'A').length,
      missingOnPage: csv
        .filter((record) => !pageRows.some((row) => this.rowMatches(row, record)))
        .map((record) => record.roll_number),
      missingInCsv: pageRows
        .filter((row) => !row.ids.some((id) => allCsvIds.has(id)))
        .map((row) => row.ids[0]),
      duplicates: [...new Set(duplicates)],
      metadataWarnings: warnings,
    };
  }

  apply(csv: AttendanceCsvRow[]): void {
    const preview = this.preview(csv);
    if (preview.missingOnPage.length || preview.missingInCsv.length ||
        preview.duplicates.length || preview.metadataWarnings.length) {
      throw new Error('Dữ liệu chưa khớp hai chiều với trang FAP.');
    }
    const pageRows = this.rows();
    for (const record of csv) {
      const row = pageRows.find((candidate) => this.rowMatches(candidate, record));
      if (!row) throw new Error(`Không tìm thấy ${record.roll_number}.`);
      this.setStatus(row.element, record.status);
    }
    for (const record of csv) {
      const row = pageRows.find((candidate) => this.rowMatches(candidate, record))!;
      if (this.readStatus(row.element) !== record.status) {
        throw new Error(`Không thể đặt trạng thái cho ${record.roll_number}.`);
      }
    }
  }

  async submit(): Promise<boolean> {
    const controls = [...this.document.querySelectorAll<HTMLInputElement | HTMLButtonElement>('button,input[type=submit],input[type=button]')];
    const submit = controls.find((element) => !element.disabled && !element.closest('[hidden]') &&
      /submit|save|lưu|chốt/i.test(element.textContent || element.value || ''));
    if (!submit) throw new Error('Không tìm thấy nút Submit gốc của FAP.');
    submit.click();
    return new Promise((resolve) => {
      const successPattern = /success|successful|thành công|saved/i;
      const successful = () => {
        const visibleStatus = [...this.document.querySelectorAll('[role=status],.alert-success')]
          .some((element) => !element.closest('[hidden]') && successPattern.test(element.textContent ?? ''));
        return visibleStatus || successPattern.test(this.document.body.innerText ?? '');
      };
      if (successful()) return resolve(true);
      const observer = new MutationObserver(() => {
        if (successful()) { observer.disconnect(); resolve(true); }
      });
      observer.observe(this.document.body, { childList: true, subtree: true, characterData: true });
      setTimeout(() => { observer.disconnect(); resolve(successful()); }, 8000);
    });
  }

  private studentIds(row: HTMLTableRowElement): string[] {
    return [...row.querySelectorAll('td')]
      .map((cell) => normalizeId(cell.textContent ?? ''))
      .filter((value) => /^[A-Z]{2,6}\d{4,9}$/.test(value));
  }

  private rowMatches(row: PageRow, record: AttendanceCsvRow): boolean {
    return row.ids.includes(record.roll_number) ||
      Boolean(record.member_code && row.ids.includes(record.member_code));
  }

  private setStatus(row: HTMLTableRowElement, status: AttendanceStatus): void {
    const present = this.presentCheckbox(row);
    if (present) {
      if (present.checked !== (status === 'P')) {
        present.click();
      }
      return;
    }
    const radios = [...row.querySelectorAll<HTMLInputElement>('input[type=radio]')];
    const radio = radios.find((control) => this.controlStatus(control) === status);
    if (radio) {
      radio.click();
      radio.dispatchEvent(new Event('input', { bubbles: true }));
      radio.dispatchEvent(new Event('change', { bubbles: true }));
      return;
    }
    const select = row.querySelector<HTMLSelectElement>('select');
    const option = select && [...select.options].find((item) => this.valueStatus(item.value + item.text) === status);
    if (select && option) {
      select.value = option.value;
      select.dispatchEvent(new Event('input', { bubbles: true }));
      select.dispatchEvent(new Event('change', { bubbles: true }));
      return;
    }
    throw new Error('Không nhận diện được control Present/Absent trên một dòng FAP.');
  }

  private readStatus(row: HTMLTableRowElement): AttendanceStatus | null {
    const present = this.presentCheckbox(row);
    if (present) return present.checked ? 'P' : 'A';
    const selected = row.querySelector<HTMLInputElement>('input[type=radio]:checked');
    if (selected) return this.controlStatus(selected);
    const select = row.querySelector<HTMLSelectElement>('select');
    return select ? this.valueStatus(select.value) : null;
  }

  private presentCheckbox(row: HTMLTableRowElement): HTMLInputElement | undefined {
    return [...row.querySelectorAll<HTMLInputElement>('input[type=checkbox]')]
      .find((control) => this.controlStatus(control) === 'P');
  }

  private controlStatus(control: HTMLInputElement): AttendanceStatus | null {
    const label = control.labels?.[0]?.textContent ?? '';
    return this.valueStatus(`${control.value} ${control.id} ${control.name} ${label}`);
  }

  private valueStatus(value: string): AttendanceStatus | null {
    const normalized = value.trim().toUpperCase();
    if (/\b(P|PRESENT|CÓ MẶT)\b/.test(normalized)) return 'P';
    if (/\b(A|ABSENT|VẮNG)\b/.test(normalized)) return 'A';
    return null;
  }
}
