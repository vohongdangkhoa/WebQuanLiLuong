export const roleLabels = { HR: "Nhân sự", PAYROLL: "Kế toán lương", DIRECTOR: "Giám đốc", EMPLOYEE: "Nhân viên" };
export const statusLabels = {
  ACTIVE: "Đang làm việc", INACTIVE: "Không hoạt động", TERMINATED: "Đã nghỉ việc", DRAFT: "Bản nháp", PENDING: "Chờ duyệt", SUBMITTED: "Chờ phê duyệt", APPROVED: "Đã duyệt", REJECTED: "Từ chối", OPEN: "Đang mở", CLOSED: "Đã đóng", LOCKED: "Đã chốt", UNLOCKED: "Chưa chốt", CALCULATING: "Đang tính", CALCULATED: "Đã tính", COMPLETED: "Hoàn tất", FAILED: "Thất bại", ERROR: "Có lỗi", SUCCESS: "Thành công", CREATED: "Đã tạo", EXPORTED: "Đã xuất tệp", SENT: "Đã gửi", SENT_TO_BANK: "Đã gửi ngân hàng", PROCESSING: "Đang xử lý", PAID: "Đã thanh toán", UNPAID: "Chưa thanh toán", PARTIAL: "Thanh toán một phần", CERTIFIED: "Đã xác nhận", CONFIRMED: "Đã xác nhận", RESOLVED: "Đã xử lý", CANCELLED: "Đã hủy", ISSUED: "Đã phát hành", Y: "Có", N: "Không",
};
export const hasRole = (user, ...roles) => roles.some((role) => user?.roles?.includes(role));
Object.assign(statusLabels, { PENDING_APPROVAL: "Chờ phê duyệt", VERIFIED: "Đã xác minh", VALID: "Hợp lệ", REOPENED: "Đã mở lại", SUCCEEDED: "Thành công", READY: "Sẵn sàng", MATCHED: "Đã khớp", UNMATCHED: "Chưa khớp", AMOUNT_MISMATCH: "Lệch số tiền", CONFLICT: "Xung đột", APPLIED: "Đã áp dụng", ACCEPTED: "Đã tiếp nhận", IMPORTED: "Đã nhập", VALIDATING: "Đang kiểm tra", EARNING: "Thu nhập", DEDUCTION: "Khấu trừ", EMPLOYER_COST: "Chi phí công ty", WORKDAY: "Ngày làm việc", RESTDAY: "Ngày nghỉ", HOLIDAY: "Ngày lễ" });
Object.assign(statusLabels, { TIMESHEET: "Bảng công", EMPLOYEE: "Nhân viên", EMPLOYEE_ASSIGNMENT: "Phân công nhân viên", EMPLOYMENT_CONTRACT: "Hợp đồng lao động", PAYROLL_RUN: "Bảng lương", PAYROLL_PERIOD: "Kỳ lương", PAYMENT_BATCH: "Đợt thanh toán", BANK_ACCOUNT: "Tài khoản ngân hàng", CREATE: "Tạo mới", UPDATE: "Cập nhật", APPROVE: "Phê duyệt", REJECT: "Từ chối", VERIFY: "Xác minh", TRANSFER: "Chuyển công tác", LOCK: "Chốt dữ liệu", REOPEN: "Mở lại dữ liệu", CLOSE: "Đóng kỳ", EXPORT: "Xuất tệp", SUBMIT: "Gửi duyệt" });
export function dateText(value) { if (!value) return "—"; const parts = String(value).slice(0, 10).split("-"); return parts.length === 3 ? `${parts[2]}/${parts[1]}/${parts[0]}` : String(value); }
export function dateTimeText(value) { if (!value) return "—"; if (!/Z$|[+-]\d{2}:\d{2}$/.test(String(value))) return `${dateText(value)} ${String(value).slice(11, 16)}`.trim(); const date = new Date(value); return Number.isNaN(date.valueOf()) ? String(value) : date.toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" }); }
const moneyFormat = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", minimumFractionDigits: 0, maximumFractionDigits: 2 });
const numberFormat = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 4 });
const percentFormat = new Intl.NumberFormat("vi-VN", { style: "percent", maximumFractionDigits: 4 });
export const money = (value) => value == null ? "—" : moneyFormat.format(value);
export const numberText = (value) => value == null ? "—" : numberFormat.format(value);
export const percentText = (value) => value == null ? "—" : percentFormat.format(value);
export function today() { const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Ho_Chi_Minh", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date()); const get = (type) => parts.find((part) => part.type === type).value; return `${get("year")}-${get("month")}-${get("day")}`; }
export function periodLabel(period) { return period?.periodName || period?.periodCode || (period?.periodStart ? `Tháng ${String(period.periodStart).slice(5, 7)}/${String(period.periodStart).slice(0, 4)}` : String(period?.periodId ?? "")); }
export function rowsOf(data) { return Array.isArray(data) ? data : data?.rows || data?.items || []; }
const labels = { employeeCode: "Mã nhân viên", fullName: "Họ tên", employeeName: "Nhân viên", departmentName: "Phòng ban", positionName: "Chức danh", periodId: "Mã kỳ", periodName: "Kỳ lương", periodStart: "Bắt đầu", periodEnd: "Kết thúc", periodStatus: "Trạng thái kỳ", timesheetStatus: "Bảng công", status: "Trạng thái", paymentStatus: "Thanh toán", versionNo: "Phiên bản", versionNumber: "Phiên bản", runId: "Mã bảng lương", totalGross: "Tổng thu nhập", grossAmount: "Tổng thu nhập", gross: "Tổng thu nhập", totalNet: "Thực lĩnh", netAmount: "Thực lĩnh", net: "Thực lĩnh", totalTax: "Thuế TNCN", taxAmount: "Thuế TNCN", totalInsurance: "Bảo hiểm", insuranceAmount: "Bảo hiểm", employerInsurance: "BH doanh nghiệp", totalEmployees: "Nhân viên", employeeCount: "Nhân viên", successCount: "Thành công", errorCount: "Lỗi", failureCount: "Lỗi", resultId: "Mã kết quả", batchId: "Mã đợt", paymentId: "Mã giao dịch", itemId: "Mã dòng", reference: "Tham chiếu", referenceCode: "Tham chiếu", bankReference: "Tham chiếu ngân hàng", amount: "Số tiền", paidAmount: "Đã trả", unpaidAmount: "Còn lại", failureReason: "Lý do lỗi", errorMessage: "Thông báo", reason: "Lý do", decisionReason: "Ý kiến duyệt", workDate: "Ngày làm việc", workedMinutes: "Phút thực làm", paidLeaveMinutes: "Phút nghỉ phép", paidHolidayMinutes: "Phút nghỉ lễ", paidMinutes: "Phút tính lương", lateMinutes: "Phút đi muộn", startsAt: "Bắt đầu", endsAt: "Kết thúc", validFrom: "Từ ngày", validTo: "Đến trước ngày", issuedAt: "Ngày phát hành", createdAt: "Ngày tạo", contractNo: "Số hợp đồng", monthlySalary: "Lương tháng", insuranceBase: "Mức đóng bảo hiểm", insuranceEnabled: "Tham gia bảo hiểm", calendarName: "Lịch làm việc", leaveName: "Loại nghỉ", approvedMinutes: "Phút được duyệt", actualMinutes: "Phút thực tế", balanceMinutes: "Số dư (phút)", sourceType: "Loại dữ liệu", sourceId: "Mã nguồn", title: "Nội dung", action: "Thao tác", accountHolder: "Chủ tài khoản", bankName: "Ngân hàng", bankCode: "Mã ngân hàng", maskedAccount: "Số tài khoản", accountLast4: "Bốn số cuối", componentName: "Khoản lương", componentCode: "Mã khoản", componentKind: "Loại khoản", quantity: "Số lượng", rate: "Đơn giá", formula: "Cách tính", calculationNote: "Diễn giải", taxableAmount: "Thu nhập chịu thuế", deductionAmount: "Khấu trừ" };
export function columnLabel(key) { return labels[key] || key.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase()); }
export function displayValue(key, value) {
  if (value == null || value === "") return "—";
  if (typeof value === "boolean") return value ? "Có" : "Không";
  if (typeof value === "object") return JSON.stringify(value);
  if (/At$/.test(key)) return dateTimeText(value);
  if (/Date$|validFrom|validTo|periodStart|periodEnd/.test(key)) return dateText(value);
  if (typeof value === "number") {
    if (/InsuranceRate$|Fraction$/i.test(key)) return percentText(value);
    if (/amount|salary|gross|net$|tax|insurance|companyCost|unitRate|relief|monthlyLimit/i.test(key)) return money(value);
    return numberText(value);
  }
  return statusLabels[value] || String(value);
}
export function exportCsv(filename, rows, columns) {
  const escape = (input) => { let value = String(input ?? ""); if (/^[\s]*[=+\-@]|^[\t\r]/.test(value)) value = `'${value}`; return `"${value.replaceAll('"', '""')}"`; };
  const csv = [columns.map((col) => escape(col.label)).join(","), ...rows.map((row) => columns.map((col) => escape(displayValue(col.key, row[col.key]))).join(","))].join("\r\n");
  const url = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" })); const anchor = document.createElement("a"); anchor.href = url; anchor.download = filename; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
