import { useRef, useState } from "react";
import useAuth from "../hooks/useAuth";
import useResource from "../hooks/useResource";
import useOperation from "../hooks/useOperation";
import { apiGet, apiPost, apiUpload, queryString, saveDownload } from "../services/api";
import { hasRole, periodLabel, today } from "../utils/format";
import { Alert, Button, Card, DataTable, Field, Modal, PageHeader, ResourceState, SelectField, Tabs } from "../components/ui";
import ActionForm from "../components/ActionForm";

const base = "/configuration";
const intervalFields = () => [
  { name: "validFrom", label: "Từ ngày", type: "date", required: true, defaultValue: today() },
  { name: "validTo", label: "Đến trước ngày", type: "date", nullable: true, hint: "Để trống nếu chưa xác định ngày kết thúc. Ngày kết thúc không được tính vào hiệu lực." },
];
const numberField = (name, label, min = 0, max = 9999999999999, step = "0.01") => ({ name, label, min, max, step, type: "number", numeric: true, required: true });
const policyColumns = [
  { key: "policyCode", label: "Mã chính sách" }, { key: "validFrom", label: "Từ ngày" }, { key: "validTo", label: "Đến trước ngày" },
  { key: "employeeInsuranceRate", label: "Tỷ lệ BH nhân viên" }, { key: "employerInsuranceRate", label: "Tỷ lệ BH công ty" },
  { key: "personalRelief", label: "Giảm trừ cá nhân" }, { key: "dependentRelief", label: "Giảm trừ phụ thuộc" }, { key: "status", label: "Trạng thái" },
];
const allowanceColumns = [
  { key: "employeeCode", label: "Mã nhân viên" }, { key: "fullName", label: "Họ tên" }, { key: "componentName", label: "Khoản thu nhập" },
  { key: "amount", label: "Số tiền" }, { key: "allocationMethod", label: "Phân bổ", render: (value) => ({ FULL_MONTH: "Cả tháng", PAID_MINUTES: "Theo phút hưởng lương", CALENDAR_DAYS: "Theo ngày lịch" })[value] || value },
  { key: "validFrom", label: "Từ ngày" }, { key: "validTo", label: "Đến trước ngày" }, { key: "status", label: "Trạng thái" },
];
const entryColumns = [
  { key: "employeeCode", label: "Mã nhân viên" }, { key: "fullName", label: "Họ tên" }, { key: "periodStart", label: "Kỳ lương" },
  { key: "componentName", label: "Khoản lương" }, { key: "componentKind", label: "Loại" }, { key: "amount", label: "Số tiền" },
  { key: "reason", label: "Diễn giải" }, { key: "status", label: "Trạng thái" },
];
const dependentColumns = [
  { key: "employeeCode", label: "Mã nhân viên" }, { key: "employeeName", label: "Nhân viên" }, { key: "dependentName", label: "Người phụ thuộc" },
  { key: "birthDate", label: "Ngày sinh" }, { key: "validFrom", label: "Từ ngày" }, { key: "validTo", label: "Đến trước ngày" }, { key: "status", label: "Trạng thái" },
];
const accountColumns = [
  { key: "deductionAccountId", label: "Mã theo dõi" }, { key: "employeeCode", label: "Nhân viên" },
  { key: "principalAmount", label: "Tổng phải thu" }, { key: "collectedAmount", label: "Đã thu" },
  { key: "monthlyLimit", label: "Giới hạn tháng" }, { key: "description", label: "Nội dung" },
];

function DependentForm({ employees, selectedEmployee, onClose, onSuccess }) {
  const [values, setValues] = useState({ employeeId: selectedEmployee || (employees.length === 1 ? String(employees[0].value) : ""), identity: "", fullName: "", birthDate: "", validFrom: today(), validTo: "" });
  const [file, setFile] = useState(null);
  const [documentId, setDocumentId] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const lock = useRef(false);
  const change = (name, value) => setValues((previous) => ({ ...previous, [name]: value }));
  async function submit(event) {
    event.preventDefault();
    if (lock.current) return;
    if (!file && !documentId) { setError("Vui lòng chọn tệp minh chứng."); return; }
    lock.current = true; setBusy(true); setError("");
    try {
      let proof = documentId;
      if (!proof) {
        const uploaded = await apiUpload("/documents", file);
        proof = uploaded.documentId;
        if (!Number.isSafeInteger(proof) || proof <= 0) throw new Error("Máy chủ chưa trả mã minh chứng hợp lệ.");
        setDocumentId(proof);
      }
      const result = await apiPost(`${base}/dependents`, {
        ...values, employeeId: Number(values.employeeId), identity: values.identity.trim(), fullName: values.fullName.trim(),
        birthDate: values.birthDate || null, validTo: values.validTo || null, documentId: proof,
      });
      onSuccess(result);
    } catch (failure) { setError(failure.message); }
    finally { lock.current = false; setBusy(false); }
  }
  return <Modal title="Đăng ký người phụ thuộc" onClose={onClose} closable={!busy} wide>
    <form className="action-form" onSubmit={submit}>
      <div className="form-note">Hồ sơ cần giám đốc xác minh. Định danh được bảo vệ trên máy chủ; không hiển thị lại trong danh sách. Chỉ gửi minh chứng mà bạn có quyền sử dụng.</div>
      <fieldset disabled={busy}><div className="form-grid">
        <SelectField label="Nhân viên *" options={employees} value={values.employeeId} onChange={(e) => change("employeeId", e.target.value)} required />
        <Field label="Định danh người phụ thuộc *" hint="Nhập thống nhất số định danh hoặc mã hồ sơ trên minh chứng.">{(id) => <input id={id} required maxLength={128} autoComplete="off" value={values.identity} onChange={(e) => change("identity", e.target.value)} />}</Field>
        <Field label="Họ tên người phụ thuộc *">{(id) => <input id={id} required maxLength={150} value={values.fullName} onChange={(e) => change("fullName", e.target.value)} />}</Field>
        <Field label="Ngày sinh">{(id) => <input id={id} type="date" max={today()} value={values.birthDate} onChange={(e) => change("birthDate", e.target.value)} />}</Field>
        <Field label="Từ ngày *">{(id) => <input id={id} type="date" required value={values.validFrom} onChange={(e) => change("validFrom", e.target.value)} />}</Field>
        <Field label="Đến trước ngày">{(id) => <input id={id} type="date" min={values.validFrom} value={values.validTo} onChange={(e) => change("validTo", e.target.value)} />}</Field>
        <Field label="Tệp minh chứng *" hint="PDF, PNG hoặc JPEG; tối đa 10 MB." className="field-wide">{(id) => <input id={id} type="file" accept=".pdf,.png,.jpg,.jpeg" required={!documentId} onChange={(e) => { setFile(e.target.files?.[0] || null); setDocumentId(null); }} />}</Field>
      </div></fieldset>
      {documentId && <Alert type="success">Minh chứng đã tải lên. Bạn có thể sửa thông tin và gửi lại hồ sơ nếu cần.</Alert>}
      <Alert>{error}</Alert><div className="form-actions"><Button variant="secondary" disabled={busy} onClick={onClose}>Hủy</Button><Button type="submit" disabled={busy}>{busy ? "Đang lưu hồ sơ…" : "Gửi đăng ký"}</Button></div>
    </form>
  </Modal>;
}

function PolicyDetail({ row, onClose }) {
  const brackets = useResource(`${base}/policies/${row.policyId}/brackets`);
  const labels = {
    policyCode: "Mã chính sách", validFrom: "Từ ngày", validTo: "Đến trước ngày", employeeInsuranceRate: "Tỷ lệ BH nhân viên", employerInsuranceRate: "Tỷ lệ BH công ty",
    insuranceCap: "Trần bảo hiểm", personalRelief: "Giảm trừ cá nhân", dependentRelief: "Giảm trừ phụ thuộc", otWorkdayFactor: "Hệ số tăng ca ngày làm",
    otRestdayFactor: "Hệ số tăng ca ngày nghỉ", otHolidayFactor: "Hệ số tăng ca ngày lễ", nightExtraFactor: "Phụ trội ca đêm", otTaxableFraction: "Tỷ phần tăng ca chịu thuế",
    roundScale: "Số chữ số làm tròn", sourceNote: "Căn cứ / ghi chú", status: "Trạng thái",
  };
  return <Modal title={`Chính sách ${row.policyCode}`} onClose={onClose} wide>
    <DataTable searchable={false} rows={Object.entries(labels).map(([key, label]) => ({ label, value: row[key] ?? "—" }))} columns={[{ key: "label", label: "Thông số" }, { key: "value", label: "Giá trị" }]} />
    <h3>Bậc thuế theo phiên bản</h3><ResourceState resource={brackets}><DataTable searchable={false} rows={brackets.data || []} columns={[{ key: "lowerBound", label: "Cận dưới" }, { key: "upperBound", label: "Cận trên", render: (v) => v === null ? "Không giới hạn" : v }, { key: "rate", label: "Tỷ lệ" }]} /></ResourceState>
  </Modal>;
}

function PolicyForm({ onClose, onSuccess }) {
  const [bands, setBands] = useState([{ key: 1, upperBound: "", ratePercent: "" }]);
  const [busy, setBusy] = useState(false);
  const nextKey = useRef(2);
  const maximumBound = 999999999999999;

  function addBand() {
    const band = { key: nextKey.current++, upperBound: "", ratePercent: "" };
    setBands((current) => [...current, band]);
  }

  function removeBand(key) {
    setBands((current) => {
      const remaining = current.filter((band) => band.key !== key);
      const lastIndex = remaining.length - 1;
      return remaining.map((band, index) => index === lastIndex ? { ...band, upperBound: "" } : band);
    });
  }

  function changeBand(key, field, value) {
    setBands((current) => current.map((band) => band.key === key ? { ...band, [field]: value } : band));
  }

  function buildRequest(values) {
    let lowerBound = 0;
    const brackets = bands.map((band, index) => {
      const ratePercent = Number(band.ratePercent);
      if (band.ratePercent === "" || !Number.isFinite(ratePercent) || ratePercent < 0 || ratePercent > 100) {
        throw new Error(`Thuế suất bậc ${index + 1} phải từ 0 đến 100%.`);
      }
      const rate = Number((ratePercent / 100).toFixed(6));
      if (Math.abs(ratePercent / 100 - rate) > Number.EPSILON) {
        throw new Error(`Thuế suất bậc ${index + 1} nhận tối đa 4 chữ số sau dấu thập phân.`);
      }
      const upperBound = index === bands.length - 1 ? null : Number(band.upperBound);
      if (upperBound !== null && (!Number.isFinite(upperBound) || upperBound <= lowerBound || upperBound > maximumBound)) {
        throw new Error(`Cận trên bậc ${index + 1} phải lớn hơn cận dưới và không vượt quá ${maximumBound.toLocaleString("vi-VN")} ₫.`);
      }
      if (upperBound !== null && Number(upperBound.toFixed(2)) !== upperBound) {
        throw new Error(`Cận trên bậc ${index + 1} nhận tối đa 2 chữ số sau dấu thập phân.`);
      }
      const bracket = { lowerBound, upperBound, rate };
      if (upperBound !== null) lowerBound = upperBound;
      return bracket;
    });
    return { ...values, brackets };
  }

  const fields = [
    { name: "policyCode", label: "Mã chính sách", required: true, maxLength: 40 },
    ...intervalFields(),
    numberField("employeeInsuranceRate", "Tỷ lệ BH nhân viên", 0, 1, "0.000001"),
    numberField("employerInsuranceRate", "Tỷ lệ BH công ty", 0, 1, "0.000001"),
    numberField("insuranceCap", "Trần mức đóng bảo hiểm", 0.01),
    numberField("personalRelief", "Giảm trừ cá nhân"),
    numberField("dependentRelief", "Giảm trừ mỗi người phụ thuộc"),
    numberField("otWorkdayFactor", "Hệ số tăng ca ngày làm", 1, 99),
    numberField("otRestdayFactor", "Hệ số tăng ca ngày nghỉ", 1, 99),
    numberField("otHolidayFactor", "Hệ số tăng ca ngày lễ", 1, 99),
    numberField("nightExtraFactor", "Phụ trội ca đêm", 0, 99),
    numberField("otTaxableFraction", "Tỷ phần tăng ca chịu thuế", 0, 1, "0.000001"),
    { ...numberField("roundScale", "Số chữ số làm tròn", 0, 2, "1"), defaultValue: 0 },
    { name: "sourceNote", label: "Căn cứ và ghi chú chính sách", type: "textarea", required: true, maxLength: 1000 },
  ];

  return <Modal title="Tạo phiên bản chính sách lương" onClose={onClose} closable={!busy} wide>
    <fieldset disabled={busy}>
      <div className="section-toolbar">
        <h3>Các bậc thuế</h3>
        <Button icon="plus" variant="secondary" disabled={bands.length >= 50} onClick={addBand}>Thêm bậc</Button>
      </div>
      <p className="section-note">Bậc đầu bắt đầu từ 0 ₫. Mỗi bậc tiếp theo lấy cận trên của bậc trước làm cận dưới. Bậc cuối không giới hạn thu nhập.</p>
      <div className="table-scroll">
        <table>
          <caption className="sr-only">Các bậc thuế của chính sách mới</caption>
          <thead><tr><th scope="col">Bậc</th><th scope="col">Cận dưới (₫)</th><th scope="col">Cận trên (₫)</th><th scope="col">Thuế suất (%)</th><th scope="col">Thao tác</th></tr></thead>
          <tbody>{bands.map((band, index) => {
            const label = `bậc ${index + 1}`;
            const last = index === bands.length - 1;
            return <tr key={band.key}>
              <th scope="row">{index + 1}</th>
              <td><input type="number" aria-label={`Cận dưới ${label}`} readOnly value={index === 0 ? 0 : bands[index - 1].upperBound} /></td>
              <td><input type="number" aria-label={`Cận trên ${label}`} min={0} max={maximumBound} step="0.01" readOnly={last} value={last ? "" : band.upperBound} placeholder={last ? "Không giới hạn" : "Nhập số tiền"} onChange={(event) => changeBand(band.key, "upperBound", event.target.value)} /></td>
              <td><input type="number" aria-label={`Thuế suất ${label}`} min={0} max={100} step="0.0001" value={band.ratePercent} placeholder="Nhập %" onChange={(event) => changeBand(band.key, "ratePercent", event.target.value)} /></td>
              <td><Button variant="danger-ghost" aria-label={`Xóa ${label}`} disabled={bands.length === 1} onClick={() => removeBand(band.key)}>Xóa</Button></td>
            </tr>;
          })}</tbody>
        </table>
      </div>
    </fieldset>
    <ActionForm
      endpoint={`${base}/policies`}
      fields={fields}
      transform={buildRequest}
      onBusyChange={setBusy}
      onCancel={onClose}
      onSuccess={onSuccess}
      submitLabel="Tạo chính sách chờ duyệt"
      warning="Nhập tỷ lệ bảo hiểm và tỷ phần chịu thuế bên dưới dưới dạng thập phân. Ví dụ 0,1 tương ứng 10%. Chính sách có hiệu lực sau khi người có thẩm quyền phê duyệt."
    />
  </Modal>;
}

export default function ConfigurationPage() {
  const { user } = useAuth();
  const manager = hasRole(user, "HR", "PAYROLL", "DIRECTOR");
  const writer = hasRole(user, "HR", "PAYROLL");
  const [tab, setTab] = useState(manager ? "policies" : "dependents");
  const [employeeId, setEmployeeId] = useState("");
  const [periodId, setPeriodId] = useState("");
  const [dependentOpen, setDependentOpen] = useState(false);
  const [policyOpen, setPolicyOpen] = useState(false);
  const [policyDetail, setPolicyDetail] = useState(null);
  const [message, setMessage] = useState("");
  const [downloadError, setDownloadError] = useState("");
  const catalogs = useResource(`${base}/catalogs`);
  const resource = useResource(`${base}/${tab}${queryString({ employeeId: ["allowances", "entries", "dependents"].includes(tab) ? employeeId : "", periodId: tab === "entries" ? periodId : "" })}`);
  const refresh = () => { resource.reload(); catalogs.reload(); };
  const operation = useOperation(refresh);
  const employees = (catalogs.data?.employees || []).map((row) => ({ value: row.employeeId, label: `${row.employeeCode} · ${row.fullName}` }));
  const periods = (catalogs.data?.periods || []).map((row) => ({ value: row.periodId, label: periodLabel(row) }));
  const components = catalogs.data?.components || [];
  const employeeField = { name: "employeeId", label: "Nhân viên", type: "select", numeric: true, required: true, options: employees, defaultValue: employeeId };

  function createAllowance() {
    operation.open({ title: "Đăng ký phụ cấp", endpoint: `${base}/allowances`, submitLabel: "Tạo phụ cấp chờ duyệt", fields: [employeeField,
      { name: "componentId", label: "Khoản thu nhập", type: "select", numeric: true, required: true, options: components.filter((r) => r.componentKind === "EARNING").map((r) => ({ value: r.componentId, label: r.componentName })) },
      numberField("amount", "Số tiền"), { name: "allocationMethod", label: "Cách phân bổ", type: "select", required: true, options: [{ value: "FULL_MONTH", label: "Cả tháng" }, { value: "PAID_MINUTES", label: "Theo phút hưởng lương" }, { value: "CALENDAR_DAYS", label: "Theo ngày lịch" }] }, ...intervalFields()] });
  }
  function createEntry() {
    operation.open({ title: "Lập khoản cộng / trừ theo kỳ", endpoint: `${base}/entries`, submitLabel: "Gửi khoản chờ duyệt", warning: "Khoản khấu trừ cần chọn đúng tài khoản theo dõi của nhân viên. Khoản thu nhập phải để trống tài khoản khấu trừ.", fields: [employeeField,
      { name: "periodId", label: "Kỳ lương", type: "select", numeric: true, required: true, options: periods, defaultValue: periodId },
      { name: "componentId", label: "Khoản lương", type: "select", numeric: true, required: true, options: components.filter((r) => ["EARNING", "DEDUCTION"].includes(r.componentKind)).map((r) => ({ value: r.componentId, label: `${r.componentName} · ${r.componentKind === "EARNING" ? "Thu nhập" : "Khấu trừ"}` })) },
      numberField("amount", "Số tiền", 0.01), { name: "deductionAccountId", label: "Tài khoản theo dõi khấu trừ", type: "select", numeric: true, nullable: true, options: (catalogs.data?.deductionAccounts || []).filter((r) => Number(r.principalAmount) > Number(r.collectedAmount)).map((r) => ({ value: r.deductionAccountId, label: `${r.employeeCode} · #${r.deductionAccountId} · ${r.description}` })) },
      { name: "reason", label: "Diễn giải / căn cứ", type: "textarea", required: true, maxLength: 1000 }] });
  }
  function createAccount() {
    operation.open({ title: "Mở tài khoản theo dõi khấu trừ", endpoint: `${base}/deduction-accounts`, warning: "Thao tác này chỉ mở số dư phải thu. Muốn khấu trừ vào lương cần lập và phê duyệt khoản trừ theo kỳ.", fields: [employeeField,
      numberField("principalAmount", "Tổng số tiền phải thu", 0.01), numberField("monthlyLimit", "Giới hạn khấu trừ mỗi tháng", 0.01), { name: "description", label: "Nội dung", type: "textarea", required: true, maxLength: 500 }] });
  }
  function decide(row, approve) {
    const id = row.policyId || row.allowanceId || row.entryId || row.claimId;
    operation.open({ title: approve ? "Phê duyệt hồ sơ" : "Từ chối hồ sơ", endpoint: `${base}/${tab}/${id}/decision`, submitLabel: approve ? "Xác nhận phê duyệt" : "Xác nhận từ chối", warning: "Người tạo và người duyệt phải là hai tài khoản khác nhau. Dữ liệu đã chốt hoặc khoảng hiệu lực bị chồng sẽ được hệ thống bảo vệ.",
      fields: [{ name: "reason", label: "Ý kiến / lý do", type: "textarea", required: !approve, maxLength: 1000 }], transform: (values) => ({ ...values, decision: approve ? "APPROVE" : "REJECT" }) });
  }
  function endPolicy(row) {
    operation.open({ title: `Kết thúc phiên bản ${row.policyCode}`, endpoint: `${base}/policies/${row.policyId}/end`, warning: "Chỉ rút ngắn khoảng hiệu lực. Ngày kết thúc không thuộc phiên bản cũ. Cần bảo đảm chính sách thay thế phủ đủ tháng lương và không tác động đầu vào đã khóa.", fields: [{ name: "validTo", label: "Ngày kết thúc (không bao gồm)", type: "date", required: true }, { name: "reason", label: "Lý do", type: "textarea", required: true, maxLength: 1000 }] });
  }
  async function downloadProof(row) {
    setDownloadError("");
    try { saveDownload(await apiGet(`/documents/${row.documentId}`, { download: true })); }
    catch (failure) { setDownloadError(failure.message); }
  }
  const tabs = manager ? [{ value: "policies", label: "Chính sách lương" }, { value: "allowances", label: "Phụ cấp" }, { value: "entries", label: "Cộng / trừ theo kỳ" }, { value: "deduction-accounts", label: "Theo dõi khấu trừ" }, { value: "dependents", label: "Người phụ thuộc" }] : [{ value: "dependents", label: "Người phụ thuộc của tôi" }];
  const canCreate = tab === "policies" ? hasRole(user, "PAYROLL") : tab === "deduction-accounts" ? hasRole(user, "PAYROLL") : tab === "dependents" ? hasRole(user, "HR", "EMPLOYEE") : writer;
  const create = tab === "policies" ? () => setPolicyOpen(true) : tab === "allowances" ? createAllowance : tab === "entries" ? createEntry : tab === "deduction-accounts" ? createAccount : () => setDependentOpen(true);
  const columns = tab === "policies" ? policyColumns : tab === "allowances" ? allowanceColumns : tab === "entries" ? entryColumns : tab === "dependents" ? dependentColumns : accountColumns;
  return <>
    <PageHeader eyebrow={manager ? "CHÍNH SÁCH VÀ PHÚC LỢI" : "HỒ SƠ CÁ NHÂN"} title={manager ? "Thiết lập lương" : "Người phụ thuộc"} description="Quản lý phiên bản có hiệu lực, hồ sơ chờ duyệt và minh chứng theo đúng phân quyền.">
      <Button variant="secondary" icon="refresh" onClick={refresh}>Làm mới</Button>{canCreate && <Button icon="plus" onClick={create} disabled={!catalogs.data}>Tạo hồ sơ</Button>}
    </PageHeader>
    {operation.notice}<Alert type="success" onClose={() => setMessage("")}>{message}</Alert><Alert>{downloadError}</Alert>
    <Tabs tabs={tabs} value={tab} onChange={(value) => { setTab(value); setDownloadError(""); }} />
    <ResourceState resource={catalogs}><div className="filter-bar">
      {manager && ["allowances", "entries", "dependents"].includes(tab) && <SelectField label="Nhân viên" options={employees} value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} placeholder="Tất cả nhân viên" />}
      {tab === "entries" && <SelectField label="Kỳ lương" options={periods} value={periodId} onChange={(e) => setPeriodId(e.target.value)} placeholder="Tất cả kỳ" />}
    </div></ResourceState>
    <Card title={tabs.find((item) => item.value === tab)?.label} description={tab === "policies" ? "Tỷ lệ và bậc thuế theo tham số của đơn vị; không tự áp dụng một mức luật định cố định." : tab === "dependents" ? "Chỉ hồ sơ đã xác minh mới được xét giảm trừ khi tính lương." : undefined}>
      <ResourceState resource={resource}><DataTable rows={resource.data || []} columns={columns} caption="Hồ sơ thiết lập lương" actions={(row) => <div className="row-buttons">
        {tab === "policies" && <Button variant="ghost" onClick={() => setPolicyDetail(row)}>Thông số / bậc thuế</Button>}
        {tab === "dependents" && (hasRole(user, "HR", "DIRECTOR") || row.requestedBy === user?.userId) && <Button variant="ghost" onClick={() => downloadProof(row)}>Minh chứng</Button>}
        {hasRole(user, "DIRECTOR") && row.status === "PENDING" && <><Button variant="ghost" onClick={() => decide(row, true)}>Duyệt</Button><Button variant="danger-ghost" onClick={() => decide(row, false)}>Từ chối</Button></>}
        {hasRole(user, "DIRECTOR") && tab === "policies" && row.status === "APPROVED" && <Button variant="ghost" onClick={() => endPolicy(row)}>Kết thúc phiên bản</Button>}
      </div>} /></ResourceState>
    </Card>
    {operation.dialog}
    {policyOpen && <PolicyForm onClose={() => setPolicyOpen(false)} onSuccess={(result) => {
      setPolicyOpen(false);
      setMessage(result?.message || "Đã tạo phiên bản chính sách chờ duyệt.");
      refresh();
    }} />}
    {dependentOpen && <DependentForm employees={employees} selectedEmployee={employeeId} onClose={() => setDependentOpen(false)} onSuccess={(result) => { setDependentOpen(false); setMessage(result.message); refresh(); }} />}
    {policyDetail && <PolicyDetail row={policyDetail} onClose={() => setPolicyDetail(null)} />}
  </>;
}
