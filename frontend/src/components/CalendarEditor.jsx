import { useState } from "react";
import useResource from "../hooks/useResource";
import useOperation from "../hooks/useOperation";
import { queryString } from "../services/api";
import { dateText, numberText, today } from "../utils/format";
import { Button, Card, DataTable, Field, ResourceState, SelectField } from "./ui";

const dayTypes = [
  { value: "WORKDAY", label: "Ngày làm việc" },
  { value: "RESTDAY", label: "Ngày nghỉ" },
  { value: "HOLIDAY", label: "Ngày lễ" },
];

export default function CalendarEditor({ calendars = [], onUpdated }) {
  const [selectedId, setSelectedId] = useState("");
  const [month, setMonth] = useState(() => today().slice(0, 7));
  const calendarId = selectedId || String(calendars[0]?.calendarId || "");
  const enabled = Boolean(calendarId && month);
  const days = useResource(`/hr/calendar${queryString({ calendarId, monthDate: month ? `${month}-01` : "" })}`, enabled);
  const operation = useOperation(() => {
    days.reload();
    onUpdated?.();
  });
  const options = calendars.map((calendar) => ({ value: calendar.calendarId, label: `${calendar.calendarCode} · ${calendar.calendarName}` }));

  function prepareMonth() {
    operation.open({
      title: "Bổ sung lịch làm việc tháng",
      endpoint: "/hr/calendar/month",
      submitLabel: "Bổ sung các ngày còn thiếu",
      warning: "Thêm các ngày chưa có: thứ Hai–thứ Sáu 480 phút, cuối tuần 0 phút. Các ngày đã thiết lập được giữ nguyên. Sau đó HR cần kiểm tra và thiết lập ngày lễ hoặc lịch làm việc riêng của doanh nghiệp.",
      fields: [],
      transform: () => ({ calendarId: Number(calendarId), monthDate: `${month}-01` }),
    });
  }

  function editDay(row) {
    operation.open({
      title: row ? `Thiết lập ngày ${dateText(row.workDate)}` : "Thiết lập ngày trong lịch",
      endpoint: "/hr/calendar/day",
      method: "PUT",
      submitLabel: "Lưu ngày làm việc",
      initial: row || {},
      warning: "Phút chuẩn được dùng để phân bổ lương tháng. Ngày nghỉ phải có 0 phút; ngày lễ hưởng lương cần thiết lập số phút chuẩn phù hợp. Kỳ đã chốt hoặc bảng lương đã duyệt được bảo vệ khỏi thay đổi.",
      fields: [
        ...(!row ? [{ name: "workDate", label: "Ngày áp dụng", type: "date", required: true, defaultValue: `${month}-01` }] : []),
        { name: "dayType", label: "Loại ngày", type: "select", required: true, options: dayTypes, defaultValue: "WORKDAY" },
        { name: "standardMinutes", label: "Số phút chuẩn", type: "number", numeric: true, required: true, min: 0, max: 1440, step: 1, defaultValue: 480 },
      ],
      transform: (values) => ({ ...values, calendarId: Number(calendarId), workDate: row?.workDate || values.workDate }),
    });
  }

  const rows = days.data || [];
  return <Card className="calendar-card" title="Lịch làm việc chuẩn" description="Thiết lập ngày làm việc, ngày nghỉ và ngày lễ cho lịch được chọn trong hợp đồng lao động." actions={<div className="row-buttons"><Button variant="secondary" disabled={!enabled} onClick={prepareMonth}>Chuẩn bị lịch tháng</Button><Button icon="plus" disabled={!enabled} onClick={() => editDay(null)}>Thiết lập ngày</Button></div>}>
    {operation.notice}
    <div className="filter-bar">
      <SelectField label="Lịch làm việc" value={calendarId} onChange={(event) => setSelectedId(event.target.value)} options={options} placeholder="Chọn lịch làm việc" />
      <Field label="Tháng áp dụng">{(id) => <input id={id} type="month" value={month} onChange={(event) => setMonth(event.target.value)} required min="1900-01" max="2100-12" />}</Field>
      <Button variant="secondary" icon="refresh" disabled={!enabled} onClick={days.reload}>Làm mới lịch</Button>
    </div>
    {enabled ? <ResourceState resource={days}><p className="section-note">{numberText(rows.length)} ngày đã thiết lập · Tổng {numberText(rows.reduce((sum, day) => sum + Number(day.standardMinutes || 0), 0))} phút chuẩn trong tháng. Các ngày lễ được HR thiết lập theo lịch của doanh nghiệp.</p><DataTable rows={rows} rowKey="workDate" exportName={`lich-lam-viec-${month}.csv`} emptyTitle="Tháng này chưa có lịch làm việc" emptyDescription="Chọn Chuẩn bị lịch tháng để bổ sung các ngày còn thiếu, sau đó rà soát ngày nghỉ và ngày lễ." columns={[
      { key: "workDate", label: "Ngày áp dụng" },
      { key: "dayType", label: "Loại ngày", render: (value) => dayTypes.find((type) => type.value === value)?.label || value },
      { key: "standardMinutes", label: "Phút chuẩn", align: "right" },
    ]} actions={(row) => <Button variant="ghost" onClick={() => editDay(row)}>Cập nhật ngày</Button>} /></ResourceState> : <p className="section-note">Chọn lịch làm việc và tháng để xem dữ liệu.</p>}
    {operation.dialog}
  </Card>;
}
