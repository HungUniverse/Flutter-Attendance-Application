const $ = (selector) => document.querySelector(selector);
const portrait = `<svg viewBox="0 0 70 90" aria-hidden="true"><circle cx="35" cy="27" r="17"/><path d="M4 90c0-23 13-37 31-37s31 14 31 37z"/></svg>`;
const finalizedStorageKey = 'fap-demo-finalized-v1';
let roster = [];
let markbookClasses = [];
let classListSource = '';
let classListRequest = 0;
let activeClassIndex = -1;
let activeSessionKey = '';

function readFinalized() {
  try {
    const saved = JSON.parse(localStorage.getItem(finalizedStorageKey) || '{}');
    return saved && typeof saved === 'object' && !Array.isArray(saved) ? saved : {};
  } catch { return {}; }
}
let finalized = readFinalized();

function sessionKey(courseCode, classCode, date, scheduleCode) {
  return `${String(courseCode || '').trim().toUpperCase()}|${String(classCode || '').trim().toUpperCase()}|${String(date || '').trim()}|${String(scheduleCode || '').trim().toUpperCase()}`;
}

function finalizedCount(course) {
  return course.meetings.filter((meeting) => finalized[
    sessionKey(course.courseCode, course.classCode, String(meeting.startAt).slice(0, 10), course.scheduleCode)
  ]).length;
}

function makeElement(tag, className, content) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (content !== undefined) element.textContent = content;
  return element;
}

function renderDashboard() {
  $('#dashboardSource').textContent = classListSource;
  $('#dashboardClassCount').textContent = String(markbookClasses.length);
  $('#dashboardStudentCount').textContent = String(markbookClasses.reduce((sum, course) => sum + course.students.length, 0));
  $('#dashboardFinalizedCount').textContent = String(markbookClasses.reduce((sum, course) => sum + finalizedCount(course), 0));
  $('#classList').replaceChildren(...markbookClasses.map((course, index) => {
    const card = makeElement('button', 'class-card');
    card.type = 'button';
    const title = makeElement('span', 'class-card-title', `${course.courseCode} · ${course.classCode}`);
    const detail = makeElement('span', 'class-card-detail', `Lịch ${course.scheduleCode} · ${course.students.length} sinh viên · ${course.meetings.length} slot`);
    const progress = makeElement('span', 'class-card-progress', `${finalizedCount(course)}/${course.meetings.length} slot đã chốt`);
    const arrow = makeElement('span', 'class-card-arrow', '→');
    arrow.setAttribute('aria-hidden', 'true');
    const description = makeElement('span', 'class-card-description');
    description.append(title, detail);
    card.append(description, progress, arrow);
    card.addEventListener('click', () => openClass(index));
    return card;
  }));
}

function showDashboard() {
  $('#classView').hidden = true;
  $('#dashboardView').hidden = false;
  $('#students').replaceChildren();
  $('#result').textContent = '';
  $('#dashboardStatus').textContent = '';
  roster = [];
  activeSessionKey = '';
  const main = document.querySelector('main');
  delete main.dataset.attendanceClass;
  delete main.dataset.attendanceDate;
  delete main.dataset.attendanceSlot;
  delete main.dataset.attendanceFinalized;
  renderDashboard();
  document.documentElement.scrollTop = 0;
}

function populateMeetings(course, selectedStartAt) {
  $('#meetingSelect').replaceChildren(...course.meetings.map((meeting, index) => {
    const option = document.createElement('option');
    option.value = String(index);
    const date = String(meeting.startAt).slice(0, 10).split('-').reverse().join('/');
    const time = String(meeting.startAt).slice(11, 16);
    option.textContent = `Slot ${meeting.number} · ${date} ${time}`;
    return option;
  }));
  $('#meetingSelect').disabled = false;
  if (selectedStartAt) {
    $('#meetingSelect').selectedIndex = course.meetings.findIndex((meeting) => meeting.startAt === selectedStartAt);
  }
}

function openClass(index) {
  const course = markbookClasses[index];
  if (!course) return;
  activeClassIndex = index;
  populateMeetings(course);
  $('#dashboardView').hidden = true;
  $('#classView').hidden = false;
  renderMarkbookSelection();
  document.documentElement.scrollTop = 0;
}

function updateSummary() {
  const present = document.querySelectorAll('#students input[type=checkbox]:checked').length;
  $('#summary').textContent = `P: ${present} · A: ${roster.length - present}`;
}

function showFinalized(entry) {
  const present = entry.statuses.filter((row) => String(row?.status || '').trim().toUpperCase() === 'P').length;
  const absent = entry.statuses.length - present;
  $('#finalizedSummary').textContent = `${entry.statuses.length} sinh viên · P: ${present} · A: ${absent} · ${$('#date').textContent}`;
  $('#finalizedBanner').hidden = false;
  document.querySelector('main').dataset.attendanceFinalized = 'true';
  document.querySelectorAll('#students input[type=checkbox]').forEach((input) => { input.disabled = true; });
  $('#submit').disabled = true;
  $('#submit').textContent = 'Đã chốt danh sách';
  $('#result').className = 'success';
  $('#result').textContent = 'Đã chốt danh sách thành công.';
}

function render(session, source) {
  const meeting = session.meeting;
  if (!meeting || !Array.isArray(session.attendance) || !session.attendance.length) {
    throw new Error('File này không phải JSON session điểm danh có danh sách sinh viên.');
  }
  const courseCode = String(session.courseCode || '').trim().toUpperCase();
  const classCode = String(session.classCode || '').trim().toUpperCase();
  const scheduleCode = String(session.scheduleCode || '').trim().toUpperCase();
  const date = String(meeting.startAt || '').trim().slice(0, 10);
  if (!date || !classCode || !courseCode || !scheduleCode) {
    throw new Error('JSON thiếu mã lớp, môn học hoặc ngày slot.');
  }
  const nextRoster = session.attendance.map((row) => ({
    roll: String(row.rollNumber || '').trim().toUpperCase(),
    name: String(row.fullName || '').trim(),
    photo: typeof row.photoUrl === 'string' && /^(https:\/\/|data:image\/)/i.test(row.photoUrl) ? row.photoUrl : '',
  }));
  if (nextRoster.some((student) => !student.roll || !student.name) ||
      new Set(nextRoster.map((student) => student.roll)).size !== nextRoster.length) {
    throw new Error('Danh sách thiếu hoặc trùng MSSV/họ tên.');
  }
  roster = nextRoster;
  activeSessionKey = sessionKey(courseCode, classCode, date, scheduleCode);
  const saved = finalized[activeSessionKey];
  const savedStatuses = new Map(Array.isArray(saved?.statuses)
    ? saved.statuses.map((row) => [
      String(row?.rollNumber || '').trim().toUpperCase(),
      String(row?.status || '').trim().toUpperCase(),
    ]) : []);
  const isFinalized = Boolean(saved && savedStatuses.size === roster.length &&
    roster.every((student) => savedStatuses.has(student.roll)));
  $('#classHeading').textContent = `${courseCode} · ${classCode}`;
  $('#course').textContent = courseCode;
  $('#classCode').textContent = classCode;
  $('#date').textContent = date;
  const dailySlot = scheduleCode.slice(-1);
  $('#slot').textContent = dailySlot;
  $('#studentCount').textContent = String(roster.length);
  const main = document.querySelector('main');
  main.dataset.attendanceClass = classCode;
  main.dataset.attendanceDate = date;
  main.dataset.attendanceSlot = dailySlot;
  delete main.dataset.attendanceFinalized;
  $('#students').replaceChildren(...roster.map((student, index) => {
    const tr = document.createElement('tr');
    const roll = makeElement('td', 'roll', student.roll);
    const name = makeElement('td', 'name', student.name);
    const choices = document.createElement('td');
    const box = makeElement('div', 'choices');
    const choice = document.createElement('label');
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.name = `present-${index}`;
    input.value = 'P';
    input.checked = isFinalized && savedStatuses.get(student.roll) === 'P';
    choice.append(input, ' Present');
    box.append(choice);
    choices.append(box);
    const photo = document.createElement('td');
    const frame = makeElement('div', 'portrait');
    if (student.photo) {
      const img = document.createElement('img');
      img.src = student.photo;
      img.alt = `Ảnh thẻ ${student.name}`;
      frame.append(img);
    } else frame.innerHTML = portrait;
    photo.append(frame);
    tr.append(roll, name, choices, photo);
    return tr;
  }));
  updateSummary();
  $('#sourceInfo').textContent = source;
  $('#finalizedBanner').hidden = true;
  $('#submit').disabled = false;
  $('#submit').textContent = 'Submit điểm danh';
  $('#result').textContent = '';
  $('#result').className = '';
  if (isFinalized) {
    showFinalized(saved);
  } else if (saved) {
    document.querySelectorAll('#students input[type=checkbox]').forEach((input) => {
      input.disabled = true;
    });
    $('#submit').disabled = true;
    $('#result').textContent = 'Slot đã chốt với danh sách lớp trước đó. Hãy chọn slot khác.';
  }
}

function renderMarkbookSelection() {
  const course = markbookClasses[activeClassIndex];
  const meeting = course?.meetings[$('#meetingSelect').selectedIndex];
  if (!course || !meeting) return;
  render({
    courseCode: course.courseCode,
    classCode: course.classCode,
    scheduleCode: course.scheduleCode,
    meeting,
    attendance: course.students,
  }, classListSource);
}

async function loadClassList(options, fileName) {
  const requestId = ++classListRequest;
  $('#dashboardStatus').textContent = 'Đang đọc danh sách lớp…';
  try {
    const format = fileName?.split('.').at(-1)?.toLowerCase();
    const endpoint = '/markbook-rosters.json';
    const response = await fetch(format ? `${endpoint}?format=${encodeURIComponent(format)}` : endpoint, options);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Không đọc được danh sách lớp.');
    if (!Array.isArray(data.classes) || !data.classes.length) {
      throw new Error('Tệp không có lớp hợp lệ.');
    }
    if (requestId !== classListRequest) return;
    markbookClasses = data.classes;
    classListSource = `Nguồn: ${fileName ?? data.sourceName ?? 'Danh sách lớp mặc định'}`;
    if (fileName) showDashboard();
    else renderDashboard();
    $('#dashboardStatus').textContent = fileName ? `Đã nạp ${data.classes.length} lớp.` : '';
  } catch (error) {
    if (requestId === classListRequest) {
      $('#dashboardStatus').textContent = error.message || String(error);
    }
  }
}

$('#backDashboard').addEventListener('click', showDashboard);
$('#returnDashboard').addEventListener('click', showDashboard);
$('#meetingSelect').addEventListener('change', renderMarkbookSelection);
$('#pickClassList').addEventListener('click', () => $('#classListFile').click());
$('#classListFile').addEventListener('change', async (event) => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  if (file.size > 20 * 1024 * 1024) {
    $('#dashboardStatus').textContent = 'Tệp danh sách lớp tối đa 20 MB.';
    return;
  }
  const buttons = ['#pickClassList', '#pickSession'].map($);
  buttons.forEach((button) => { button.disabled = true; });
  try {
    await loadClassList({
      method: 'POST',
      headers: { 'content-type': 'application/octet-stream' },
      body: file,
    }, file.name);
  } finally {
    buttons.forEach((button) => { button.disabled = false; });
  }
});
$('#pickSession').addEventListener('click', () => $('#sessionFile').click());
$('#sessionFile').addEventListener('change', async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    const session = JSON.parse((await file.text()).replace(/^\uFEFF/, ''));
    const normCourse = String(session.courseCode || '').trim().toUpperCase();
    const normClass = String(session.classCode || '').trim().toUpperCase();
    const normSchedule = String(session.scheduleCode || '').trim().toUpperCase();
    activeClassIndex = markbookClasses.findIndex((course) =>
      String(course.courseCode || '').trim().toUpperCase() === normCourse &&
      String(course.classCode || '').trim().toUpperCase() === normClass &&
      String(course.scheduleCode || '').trim().toUpperCase() === normSchedule);
    if (activeClassIndex >= 0) {
      populateMeetings(markbookClasses[activeClassIndex], session.meeting?.startAt);
    } else {
      $('#meetingSelect').replaceChildren(makeElement('option', '', 'Slot từ JSON'));
      $('#meetingSelect').disabled = true;
    }
    render(session, `Nguồn: ${file.name}`);
    $('#dashboardView').hidden = true;
    $('#classView').hidden = false;
  } catch (error) { $('#dashboardStatus').textContent = error.message || String(error); }
  event.target.value = '';
});

$('#attendanceTable').addEventListener('change', updateSummary);
$('#submit').addEventListener('click', () => {
  if (!activeSessionKey || finalized[activeSessionKey] || !roster.length) return;
  const statuses = [...document.querySelectorAll('#students tr')].map((row) => ({
    rollNumber: row.querySelector('.roll').textContent,
    status: row.querySelector('input[type=checkbox]').checked ? 'P' : 'A',
  }));
  const entry = { statuses, submittedAt: new Date().toISOString() };
  try {
    const updated = { ...finalized, [activeSessionKey]: entry };
    localStorage.setItem(finalizedStorageKey, JSON.stringify(updated));
    finalized = updated;
    localStorage.setItem('fap-demo-last-submit', JSON.stringify({
      classCode: $('#classCode').textContent,
      meetingDate: $('#date').textContent,
      statuses,
      submittedAt: entry.submittedAt,
    }));
    showFinalized(entry);
    renderDashboard();
  } catch (error) {
    $('#result').className = '';
    $('#result').textContent = `Không lưu được điểm danh: ${error.message || error}`;
  }
});

if (new URLSearchParams(window.location.search).get('empty') === '1') {
  renderDashboard();
  $('#dashboardStatus').textContent = 'Bấm Nạp danh sách lớp để bắt đầu.';
  const resetButton = $('#resetDemo');
  resetButton.hidden = false;
  resetButton.addEventListener('click', () => {
    try {
      localStorage.removeItem(finalizedStorageKey);
      localStorage.removeItem('fap-demo-last-submit');
    } catch {
      $('#dashboardStatus').textContent = 'Không xóa được dữ liệu trong trình duyệt.';
      return;
    }
    classListRequest++;
    finalized = {};
    markbookClasses = [];
    classListSource = '';
    activeClassIndex = -1;
    showDashboard();
    $('#dashboardStatus').textContent = 'Đã xóa dữ liệu demo. Bấm Nạp danh sách lớp để bắt đầu.';
  });
} else {
  void loadClassList();
}
