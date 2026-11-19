import { useRef, useState } from "react";
import useResource from "../hooks/useResource";
import { apiPost, queryString } from "../services/api";
import { dateText, numberText, statusLabels, today } from "../utils/format";
import { EmployeeIdentity } from "./EmployeeFilter";
import { Alert, Button, DataTable, Field, Modal, ResourceState, SelectField } from "./ui";

const issueLabels = {
  OUTSIDE_EMPLOYMENT: "Ngoài thời gian làm việc",
  MISSING_CONTRACT: "Thiếu hợp đồng được duyệt",
  MISSING_CALENDAR: "Chưa có lịch ngày này",
  FRACTIONAL_HALF: "Chưa chia được nửa ngày theo phút nguyên",
  EXCEEDS_DAY: "Giờ xin nghỉ vượt giờ chuẩn",
};
const hoursText = (minutes) => minutes == null ? "—" : `${numberText(minutes / 60)} giờ`;

export default function LeaveRequestForm({ employees, leaveTypes, canChooseEmployee, initialEmployeeId, onClose, onSuccess }) {
  const ownProfile = useResource("/profile", !canChooseEmployee);
  const [employeeId, setEmployeeId] = useState(initialEmployeeId || (employees.length === 1 ? String(employees[0].employeeId) : ""));
  const [leaveTypeId, setLeaveTypeId] = useState("");
  const [startDate, setStartDate] = useState(today());
  const [lastDate, setLastDate] = useState(today());
  const [duration, setDuration] = useState("FULL");
  const [hours, setHours] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const submitting = useRef(false);
  const employee = canChooseEmployee ? employees.find((row) => String(row.employeeId) === employeeId) : ownProfile.data;
  const hoursPerDay = duration === "HOURS" ? Number(hours) : null;
  const datesValid = Boolean(startDate && lastDate && lastDate >= startDate);
  const hoursValid = duration !== "HOURS" || (hours !== "" && hoursPerDay >= 0.25 && hoursPerDay <= 24 && Number.isInteger(hoursPerDay * 60));
  const readyToPreview = Boolean(employee?.employeeId && datesValid && hoursValid);
  const preview = useResource(`/hr/requests/leave/preview${queryString({
    employeeId: employee?.employeeId, startDate, lastDate, duration, hoursPerDay,
  })}`, readyToPreview);
  const plan = preview.data;
  const canSubmit = readyToPreview && plan?.canSubmit && !preview.loading && !preview.error;

  async function submit(event) {
    event.preventDefault();
    if (submitting.current || !canSubmit) return;
    submitting.current = true;
    setBusy(true);
    setError("");
    try {
      const result = await apiPost("/hr/requests/leave/scheduled", {
        employeeId: employee.employeeId,
        leaveTypeId: Number(leaveTypeId),
        startDate, lastDate, duration, hoursPerDay,
        reason: reason.trim(), scheduleToken: plan.scheduleToken,
      });
      onSuccess(result);
    } catch (failure) {
      setError(failure.message);
      if (failure.status === 409) preview.reload();
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }

  return <Modal title="Tạo đơn nghỉ phép" onClose={onClose} closable={!busy} wide>
    <form onSubmit={submit} className="action-form">
      <fieldset disabled={busy}>
        <div className="form-grid">
          {canChooseEmployee ? <SelectField label="Nhân viên *" value={employeeId} required
            onChange={(event) => setEmployeeId(event.target.value)}
            options={employees.map((row) => ({ value: row.employeeId, label: `${row.employeeCode} · ${row.fullName}` }))} />
            : <ResourceState resource={ownProfile}>{employee && <EmployeeIdentity employee={employee} />}</ResourceState>}
          <SelectField label="Loại nghỉ *" value={leaveTypeId} onChange={(event) => setLeaveTypeId(event.target.value)} required
            options={leaveTypes.map((row) => ({ value: row.leaveTypeId, label: row.leaveName }))} />
          <Field label="Nghỉ từ ngày *">{(id) => <input id={id} type="date" value={startDate} required onChange={(event) => setStartDate(event.target.value)} />}</Field>
          <Field label="Đến hết ngày *" hint="Tính cả ngày kết thúc bạn chọn.">{(id) => <input id={id} type="date" value={lastDate} min={startDate} required onChange={(event) => setLastDate(event.target.value)} />}</Field>
          <SelectField label="Thời lượng mỗi ngày *" value={duration} required onChange={(event) => setDuration(event.target.value)}
            options={[{ value: "FULL", label: "Cả ngày" }, { value: "HALF", label: "Nửa ngày" }, { value: "HOURS", label: "Theo giờ" }]} />
          {duration === "HOURS" && <Field label="Số giờ nghỉ mỗi ngày *" hint="Ví dụ 1,5 giờ. Thời lượng áp dụng cho mỗi ngày làm việc trong khoảng nghỉ.">
            {(id) => <input id={id} type="number" inputMode="decimal" min="0.25" max="24" step="0.25" required value={hours} onChange={(event) => setHours(event.target.value)} />}
          </Field>}
          <Field label="Lý do nghỉ *" className="field-wide">{(id) => <textarea id={id} rows={3} required minLength={3} maxLength={1000} value={reason} onChange={(event) => setReason(event.target.value)} />}</Field>
        </div>
      </fieldset>
      <p className="form-note">Cả ngày và nửa ngày được tính theo giờ chuẩn trong lịch hợp đồng. Ngày nghỉ và ngày lễ được bỏ qua. Kiểm tra bảng tính dưới đây trước khi gửi.</p>
      {!datesValid && <Alert>Ngày kết thúc phải từ ngày bắt đầu trở đi.</Alert>}
      {readyToPreview && <section className="leave-plan" aria-label="Thời gian nghỉ theo lịch làm việc" aria-live="polite">
        <div className="section-toolbar"><h3>Thời gian nghỉ theo lịch</h3><Button variant="secondary" disabled={busy || preview.loading} onClick={preview.reload}>Tính lại</Button></div>
        <ResourceState resource={preview}>
          {plan && <>
            {plan.issues.map((issue) => <Alert key={issue}>{issue}</Alert>)}
            {plan.canSubmit && <p className="leave-plan-total"><strong>{hoursText(plan.totalMinutes)}</strong> nghỉ trong {plan.workingDays} ngày làm việc · {plan.skippedDays} ngày không trừ phép</p>}
            <DataTable rows={plan.days} rowKey="workDate" searchable={false} columns={[
              { key: "workDate", label: "Ngày", render: dateText },
              { key: "calendarName", label: "Lịch hợp đồng" },
              { key: "dayType", label: "Loại ngày", render: (value) => statusLabels[value] || "Chưa có lịch" },
              { key: "standardMinutes", label: "Giờ chuẩn", render: hoursText, align: "right" },
              { key: "leaveMinutes", label: "Giờ nghỉ", render: hoursText, align: "right" },
              { key: "issueCode", label: "Kết quả", render: (value, row) => value ? issueLabels[value] : row.leaveMinutes === 0 ? "Không trừ phép" : "Được tính nghỉ" },
            ]} />
          </>}
        </ResourceState>
      </section>}
      <Alert>{error}</Alert>
      <div className="form-actions">
        <Button variant="secondary" disabled={busy} onClick={onClose}>Hủy</Button>
        <Button type="submit" disabled={busy || !canSubmit || !leaveTypeId || reason.trim().length < 3}>
          {busy ? "Đang gửi…" : "Gửi đơn nghỉ phép"}
        </Button>
      </div>
    </form>
  </Modal>;
}
