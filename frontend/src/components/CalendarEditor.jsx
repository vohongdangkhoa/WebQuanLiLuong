import { useRef, useState } from "react";
import useResource from "../hooks/useResource";
import useOperation from "../hooks/useOperation";
import { apiRequest, queryString } from "../services/api";
import { dateText, numberText, today } from "../utils/format";
import { Alert, Button, Card, DataTable, Field, Modal, ResourceState, SelectField } from "./ui";

const dayLabels = {
  WORKDAY: "Ngày làm việc",
  RESTDAY: "Ngày nghỉ theo lịch",
  HOLIDAY: "Ngày lễ",
};
const dayTypes = Object.entries(dayLabels).map(([value, label]) => ({ value, label }));

function durationInput(minutes) {
  const remaining = minutes % 60;
  const hours = Math.floor(minutes / 60);
  return remaining ? `${hours}:${String(remaining).padStart(2, "0")}` : String(hours);
}

function durationText(minutes) {
  const hours = Math.floor(minutes / 60);
  const remaining = minutes % 60;
  return remaining ? `${numberText(hours)} giờ ${remaining} phút` : `${numberText(hours)} giờ`;
}

function parseDuration(value) {
  const parts = /^(\d{1,2})(?::([0-5]\d))?$/.exec(value.trim());
  if (!parts) return null;
  const minutes = Number(parts[1]) * 60 + Number(parts[2] ?? 0);
  return minutes <= 1440 ? minutes : null;
}

function CalendarDayDialog({ calendar, month, row, onClose, onSaved }) {
  const [workDate, setWorkDate] = useState(row?.workDate || `${month}-01`);
  const [dayType, setDayType] = useState(row?.dayType || "");
  const [duration, setDuration] = useState(row ? durationInput(row.standardMinutes) : "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const saving = useRef(false);
  const isRestDay = dayType === "RESTDAY";
  const isHoliday = dayType === "HOLIDAY";
  const minutes = isRestDay ? 0 : parseDuration(duration);

  function chooseType(event) {
    const nextType = event.target.value;
    if (nextType === "HOLIDAY" && dayType !== "HOLIDAY") setDuration("");
    setDayType(nextType);
    setError("");
  }

  async function save(event) {
    event.preventDefault();
    if (saving.current || !workDate || !dayType) return;
    if (minutes === null) {
      setError("Nhập thời lượng từ 0 đến 24 giờ, ví dụ 8 hoặc 7:45.");
      return;
    }

    saving.current = true;
    setBusy(true);
    setError("");
    try {
      await apiRequest("/hr/calendar/day", {
        method: "PUT",
        body: { calendarId: calendar.calendarId, workDate, dayType, standardMinutes: minutes },
      });
      onSaved(workDate);
    } catch (failure) {
      setError(failure.message);
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }

  return <Modal title={row ? `Cập nhật ngày ${dateText(workDate)}` : "Thiết lập ngày trong lịch"}
    description={`${calendar.calendarCode} · ${calendar.calendarName}`} onClose={onClose} closable={!busy}>
    <form className="action-form" onSubmit={save}>
      <fieldset disabled={busy}>
        <div className="form-grid">
          {!row && <Field label="Ngày áp dụng *" hint={workDate ? `Đang chọn ${dateText(workDate)}` : undefined}>
            {(id) => <input id={id} type="date" value={workDate} required onChange={(event) => setWorkDate(event.target.value)} />}
          </Field>}
          <SelectField label="Loại ngày *" value={dayType} required options={dayTypes} placeholder="Chọn loại ngày" onChange={chooseType} />
          {(dayType === "WORKDAY" || isHoliday) && <Field label={isHoliday ? "Thời lượng hưởng lương theo lịch *" : "Thời lượng làm việc chuẩn *"}
            hint="Nhập 8 cho 8 giờ, hoặc 7:45 cho 7 giờ 45 phút.">
            {(id) => <input id={id} type="text" value={duration} placeholder="Ví dụ 8 hoặc 7:45" required maxLength={8}
              onChange={(event) => { setDuration(event.target.value); setError(""); }} />}
          </Field>}
        </div>
      </fieldset>
      {isRestDay && <p className="form-note">Ngày nghỉ theo lịch có 0 giờ chuẩn. Ví dụ, cuối tuần của lịch làm việc từ thứ Hai đến thứ Sáu.</p>}
      {isHoliday && <p className="form-note">Điền thời lượng được tính hưởng lương theo lịch của công ty. Chọn 0 nếu ngày lễ này không ghi nhận thời lượng hưởng lương.</p>}
      <Alert>{error}</Alert>
      <div className="form-actions">
        <Button variant="secondary" disabled={busy} onClick={onClose}>Hủy</Button>
        <Button type="submit" disabled={busy || !workDate || !dayType} icon={busy ? undefined : "check"}>{busy ? "Đang lưu…" : "Lưu ngày"}</Button>
      </div>
    </form>
  </Modal>;
}

export default function CalendarEditor({ calendars = [], onUpdated }) {
  const [selectedId, setSelectedId] = useState("");
  const [month, setMonth] = useState(() => today().slice(0, 7));
  const [dayEditor, setDayEditor] = useState(null);
  const selected = calendars.find((calendar) => String(calendar.calendarId) === selectedId) || calendars[0];
  const calendarId = selected ? String(selected.calendarId) : "";
  const enabled = Boolean(calendarId && month);
  const days = useResource(`/hr/calendar${queryString({ calendarId, monthDate: month ? `${month}-01` : "" })}`, enabled);
  const options = calendars.map((calendar) => ({ value: calendar.calendarId, label: `${calendar.calendarCode} · ${calendar.calendarName}` }));
  const operation = useOperation(() => {
    operation.setMessage("Đã bổ sung các ngày còn thiếu trong tháng.");
    refreshCalendar();
  });

  function refreshCalendar() {
    days.reload();
    onUpdated?.();
  }

  function prepareMonth() {
    const [year, monthNumber] = month.split("-");
    operation.open({
      title: `Chuẩn bị lịch tháng ${monthNumber}/${year}`,
      description: `${selected.calendarCode} · ${selected.calendarName}`,
      endpoint: "/hr/calendar/month",
      submitLabel: "Bổ sung các ngày còn thiếu",
      warning: "Mẫu tháng thêm 8 giờ mỗi ngày từ thứ Hai đến thứ Sáu và đánh dấu thứ Bảy, Chủ nhật là ngày nghỉ. Các ngày đã có được giữ nguyên. Sau khi lưu, chỉnh ngày lễ hoặc ngày có giờ làm khác theo lịch thực tế của công ty.",
      fields: [],
      transform: () => ({ calendarId: selected.calendarId, monthDate: `${month}-01` }),
    });
  }

  function editDay(row = null) {
    operation.setMessage("");
    setDayEditor({ row, calendar: selected, month });
  }

  function daySaved(workDate) {
    setDayEditor(null);
    setMonth(workDate.slice(0, 7));
    operation.setMessage(`Đã lưu ngày ${dateText(workDate)}.`);
    refreshCalendar();
  }

  const rows = days.data || [];
  const tableRows = rows.map((day) => ({ ...day, dayLabel: dayLabels[day.dayType], durationLabel: durationText(day.standardMinutes) }));
  return <Card className="calendar-card" title="Lịch làm việc chuẩn"
    description="Thiết lập lịch một lần cho mọi nhân viên có hợp đồng áp dụng lịch này."
    actions={<div className="row-buttons"><Button variant="secondary" disabled={!enabled} onClick={prepareMonth}>Chuẩn bị lịch tháng</Button><Button icon="plus" disabled={!enabled} onClick={() => editDay()}>Thiết lập ngày</Button></div>}>
    {operation.notice}
    <div className="filter-bar">
      <SelectField label="Lịch làm việc" value={calendarId} onChange={(event) => setSelectedId(event.target.value)} options={options} placeholder="Chọn lịch làm việc" />
      <Field label="Tháng áp dụng">{(id) => <input id={id} type="month" value={month} onChange={(event) => setMonth(event.target.value)} required min="1900-01" max="2100-12" />}</Field>
      <Button variant="secondary" icon="refresh" disabled={!enabled} onClick={days.reload}>Làm mới lịch</Button>
    </div>
    {enabled ? <ResourceState resource={days}>
      {rows.length > 0 && <p className="section-note">{numberText(rows.length)} ngày đã thiết lập · Tổng thời lượng chuẩn {durationText(rows.reduce((sum, day) => sum + day.standardMinutes, 0))}</p>}
      <DataTable rows={tableRows} rowKey="workDate" exportName={`lich-lam-viec-${month}.csv`} emptyTitle="Tháng này chưa có lịch làm việc"
        emptyDescription="Chọn Chuẩn bị lịch tháng, sau đó kiểm tra ngày nghỉ và ngày lễ."
        columns={[
          { key: "workDate", label: "Ngày áp dụng" },
          { key: "dayLabel", label: "Loại ngày" },
          { key: "durationLabel", label: "Thời lượng chuẩn", align: "right" },
        ]} actions={(row) => <Button variant="ghost" onClick={() => editDay(row)}>Cập nhật ngày</Button>} />
    </ResourceState> : <p className="section-note">Chọn lịch làm việc và tháng để xem dữ liệu.</p>}
    {operation.dialog}
    {dayEditor && <CalendarDayDialog {...dayEditor} onClose={() => setDayEditor(null)} onSaved={daySaved} />}
  </Card>;
}
