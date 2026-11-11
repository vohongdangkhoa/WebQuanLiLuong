const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || "/api").replace(/\/$/, "");
/*API_BASE_URL: lưu địa chỉ chung của backend, để mình dùng lại.
getHealth(): tên hàm kiểm tra backend.
fetch(...): gửi yêu cầu đến http://localhost:5038/api/health.
async và await: cho phép hàm chờ phản hồi trước khi xử lý tiếp.
if (!response.ok): nếu backend trả về mã lỗi, hàm báo lỗi bằng throw new Error(...).
response.json(): chuyển nội dung JSON backend trả về thành dữ liệu JavaScript.
return data: trả dữ liệu cho nơi gọi hàm.
export: cho phép file khác nhập và sử dụng hàm này.*/
export async function getHealth() {
  const response = await fetch(`${API_BASE_URL}/health`);

  if (!response.ok) {
    throw new Error("Không lấy được trạng thái backend.");
  }

  const data = await response.json();

  return data;
}
export async function getDatabaseHealth() {
  const response = await fetch(`${API_BASE_URL}/health/database`);

  if (!response.ok) {
    throw new Error("Không kiểm tra được kết nối Oracle.");
  }

  const data = await response.json();

  return data;
}

/* - credentials: "include": cho phép trình duyệt gửi và nhận cookie khi React gọi backend ở cổng khác. Tài liệu MDN
- cache: "no-store": lấy kết quả mới từ backend.
- Nếu nhận 401 → trả null, nghĩa là chưa có phiên đăng nhập hợp lệ.
- Nếu nhận lỗi khác → báo lỗi kiểm tra phiên.
- Nếu thành công → trả đối tượng chứa userId, username, roles.
Nhờ vậy, React phân biệt được chưa đăng nhập với gặp lỗi khi kiểm tra phiên. */

export async function getCurrentUser() {
  const response = await fetch(`${API_BASE_URL}/auth/me`, {
    credentials: "include",
    cache: "no-store",
  });

  if (response.status === 401) {
    return null;
  }

  if (!response.ok) {
    throw new Error("Không kiểm tra được phiên đăng nhập. Vui lòng thử lại.");
  }

  const data = await response.json();

  return data;
}
/* Hàm này làm ba việc:
1. Gọi API GET /api/auth/csrf mà mình đã tạo.
2. Cho phép trình duyệt gửi và nhận cookie bằng credentials: "include".
3. Đọc JSON rồi trả về riêng chuỗi mã trong trường token.
Sau này, hàm đăng nhập hoặc đăng xuất sẽ gọi getCsrfToken() trước, rồi gửi mã nhận được trong header X-CSRF-TOKEN. Đây là cách gửi mã CSRF kèm yêu cầu từ JavaScript. */
export async function getCsrfToken() {
  const response = await fetch(`${API_BASE_URL}/auth/csrf`, {
    credentials: "include",
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error("Không lấy được mã kiểm tra yêu cầu.");
  }

  const data = await response.json();

  return data.token;
}

/* loginUser(username, password): nhận tên đăng nhập và mật khẩu từ giao diện.
await getCsrfToken(): lấy mã CSRF trước khi gửi yêu cầu đăng nhập.
method: "POST": gửi dữ liệu đến API /api/auth/login.
credentials: "include": cho phép trình duyệt gửi và nhận cookie khi gọi backend.
headers: báo dữ liệu gửi đi là JSON và đính kèm mã CSRF.
JSON.stringify(...): chuyển đối tượng chứa tài khoản, mật khẩu thành chuỗi JSON để gửi. Đây là cách gửi JSON bằng Fetch trong tài liệu MDN.
if (!response.ok): nếu backend báo thất bại, lấy thông báo lỗi để giao diện hiển thị.
return data: khi đăng nhập thành công, trả về thông tin tài khoản gồm userId, username và roles. */
export async function loginUser(username, password) {
  const csrfToken = await getCsrfToken();

  const response = await fetch(`${API_BASE_URL}/auth/login`, {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-TOKEN": csrfToken,
    },
    body: JSON.stringify({ username, password }),
  });

  const data = await response.json();

  if (!response.ok) {
    const validationMessages = data.errors
      ? Object.values(data.errors).flat()
      : [];

    throw new Error(
      data.message ||
        validationMessages[0] ||
        data.title ||
        "Đăng nhập không thành công.",
    );
  }

  return data;
}

/* getCsrfToken(): lấy mã CSRF mới cho yêu cầu đăng xuất.
fetch(...): gửi yêu cầu POST /api/auth/logout, kèm cookie và mã CSRF.
response.json(): đọc kết quả backend trả về.
throw new Error(...): báo lỗi nếu đăng xuất thất bại.
return data: trả kết quả khi thành công. Backend sẽ yêu cầu trình duyệt xóa cookie đăng nhập. */
export async function logoutUser() {
  const csrfToken = await getCsrfToken();

  const response = await fetch(`${API_BASE_URL}/auth/logout`, {
    method: "POST",
    credentials: "include",
    headers: {
      "X-CSRF-TOKEN": csrfToken,
    },
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(
      data.message || data.title || "Không đăng xuất được. Vui lòng thử lại.",
    );
  }

  return data;
}
export async function getEmployees() {
  const response = await fetch(`${API_BASE_URL}/employees`, {
    credentials: "include",
    cache: "no-store",
  });

  if (response.status === 401) {
    throw new Error(
      "Phiên đăng nhập không còn hợp lệ. Hãy tải lại trang để đăng nhập lại.",
    );
  }

  if (response.status === 403) {
    throw new Error("Bạn không có quyền xem danh sách nhân viên.");
  }

  if (!response.ok) {
    throw new Error("Không tải được danh sách nhân viên. Vui lòng thử lại.");
  }

  const data = await response.json();
  return data;
}
/* fetch(...): gọi API /api/employees.
credentials: "include": gửi kèm cookie đăng nhập khi React gọi backend ở cổng khác.
cache: "no-store": lấy dữ liệu mới từ backend.
401: phiên đăng nhập không hợp lệ.
403: tài khoản không có quyền xem nhân viên.
response.json(): đọc kết quả JSON thành danh sách để React sử dụng.
export: cho phép trang Nhân viên nhập và gọi hàm này. */

export async function createEmployee(employee) {
  const csrfToken = await getCsrfToken();

  const response = await fetch(`${API_BASE_URL}/employees`, {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-TOKEN": csrfToken,
    },
    body: JSON.stringify(employee),
  });

  if (response.status === 401) {
    throw new Error(
      "Phiên đăng nhập không còn hợp lệ. Hãy tải lại trang để đăng nhập lại.",
    );
  }

  if (response.status === 403) {
    throw new Error("Bạn không có quyền thêm nhân viên.");
  }

  const data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const validationMessages = data.errors
      ? Object.values(data.errors).flat()
      : [];

    throw new Error(
      data.message ||
        validationMessages[0] ||
        data.title ||
        "Không thêm được nhân viên. Vui lòng thử lại.",
    );
  }

  return data;
}

/* - employee: nhận đối tượng gồm employeeCode, fullName, hireDate.
- getCsrfToken(): lấy mã CSRF trước khi gửi yêu cầu.
- credentials: "include": gửi kèm cookie đăng nhập.
- JSON.stringify(employee): chuyển thông tin nhân viên thành JSON.
- Kiểm tra phản hồi; nếu thất bại thì lấy thông báo backend gửi về để giao diện hiển thị.
Dòng .catch(() => ({})) dùng đối tượng rỗng khi phản hồi không đọc được thành JSON, giúp phần xử lý phía sau sử dụng thông báo lỗi dự phòng. */

export async function getDepartments() {
  const response = await fetch(`${API_BASE_URL}/departments`, {
    credentials: "include",
    cache: "no-store",
  });

  if (response.status === 401) {
    throw new Error(
      "Phiên đăng nhập không còn hợp lệ. Hãy tải lại trang để đăng nhập lại.",
    );
  }

  if (response.status === 403) {
    throw new Error("Bạn không có quyền xem danh sách phòng ban.");
  }

  if (!response.ok) {
    throw new Error("Không tải được danh sách phòng ban. Vui lòng thử lại.");
  }

  const data = await response.json();
  return data;
}
export async function getJobPositions() {
  const response = await fetch(`${API_BASE_URL}/job-positions`, {
    credentials: "include",
    cache: "no-store",
  });

  if (response.status === 401) {
    throw new Error(
      "Phiên đăng nhập không còn hợp lệ. Hãy tải lại trang để đăng nhập lại.",
    );
  }

  if (response.status === 403) {
    throw new Error("Bạn không có quyền xem danh sách chức danh.");
  }

  if (!response.ok) {
    throw new Error("Không tải được danh sách chức danh. Vui lòng thử lại.");
  }

  const data = await response.json();
  return data;
}
export async function createEmployeeAssignment(employeeId, assignment) {
  if (!Number.isSafeInteger(employeeId) || employeeId <= 0) {
    throw new Error("Vui lòng chọn nhân viên hợp lệ.");
  }

  const csrfToken = await getCsrfToken();

  const response = await fetch(
    `${API_BASE_URL}/employees/${employeeId}/assignments`,
    {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-TOKEN": csrfToken,
      },
      body: JSON.stringify(assignment),
    },
  );

  if (response.status === 401) {
    throw new Error(
      "Phiên đăng nhập không còn hợp lệ. Hãy tải lại trang để đăng nhập lại.",
    );
  }

  if (response.status === 403) {
    throw new Error("Bạn không có quyền phân công nhân viên.");
  }

  const data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const validationMessages = data.errors
      ? Object.values(data.errors).flat()
      : [];

    throw new Error(
      data.message ||
        validationMessages[0] ||
        data.title ||
        "Không lưu được phân công. Vui lòng thử lại.",
    );
  }

  return data;
}

export class ApiError extends Error {
  constructor(message, status, details) {
    const reference = status >= 500 && typeof details?.traceId === "string" ? details.traceId : "";
    super(reference ? message + " Mã lỗi: " + reference : message);
    this.name = "ApiError";
    this.status = status;
    this.details = details;
  }
}
export async function apiRequest(path, { method = "GET", body, signal, download = false } = {}) {
  const headers = {};
  if (!["GET", "HEAD", "OPTIONS"].includes(method)) headers["X-CSRF-TOKEN"] = await getCsrfToken();
  if (body !== undefined) headers["Content-Type"] = "application/json";
  let response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: "include", cache: "no-store", signal });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    throw new ApiError("Không thể kết nối máy chủ. Hãy kiểm tra kết nối và thử lại.", 0);
  }
  if (response.status === 401) window.dispatchEvent(new Event("payroll:session-expired"));
  if (response.ok && download) {
    const disposition = response.headers.get("Content-Disposition") || "";
    const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
    const ordinary = disposition.match(/filename="?([^";]+)"?/i)?.[1];
    return { blob: await response.blob(), filename: encoded ? decodeURIComponent(encoded) : ordinary || "bao-cao.csv" };
  }
  const data = response.status === 204 ? null : await response.json().catch(() => null);
  if (response.ok && response.status !== 204 && data === null) {
    throw new ApiError("Phản hồi máy chủ chưa đúng định dạng. Vui lòng tải lại trang và thử lại.", response.status);
  }
  if (!response.ok) {
    const validations = data?.errors ? Object.values(data.errors).flat() : [];
    const fallback = response.status === 401 ? "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại." : response.status === 403 ? "Tài khoản của bạn không có quyền thực hiện thao tác này." : response.status === 404 ? "Không tìm thấy dữ liệu được yêu cầu." : "Chưa thể thực hiện yêu cầu. Vui lòng thử lại.";
    throw new ApiError(data?.message || validations[0] || data?.title || fallback, response.status, data);
  }
  return data;
}
export const apiGet = (path, options) => apiRequest(path, options);
export const apiPost = (path, body) => apiRequest(path, { method: "POST", body });
export const apiPut = (path, body) => apiRequest(path, { method: "PUT", body });
export const getEmployeeAssignments = (id) => apiGet(`/employees/${id}/assignments`);
export function queryString(values) {
  const params = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => { if (value !== undefined && value !== null && value !== "") params.set(key, String(value)); });
  return params.size ? `?${params}` : "";
}
export function saveDownload({ blob, filename }) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a"); anchor.href = url; anchor.download = filename;
  document.body.append(anchor); anchor.click(); anchor.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export async function apiUpload(path, file) {
  const token = await getCsrfToken();
  const form = new FormData(); form.append("file", file);
  let response;
  try { response = await fetch(`${API_BASE_URL}${path}`, { method: "POST", credentials: "include", headers: { "X-CSRF-TOKEN": token }, body: form }); }
  catch { throw new ApiError("Không thể tải tệp lên. Vui lòng kiểm tra kết nối.", 0); }
  const data = await response.json().catch(() => ({}));
  if (response.status === 401) window.dispatchEvent(new Event("payroll:session-expired"));
  if (!response.ok) throw new ApiError(data.message || Object.values(data.errors || {}).flat()[0] || data.title || "Không nhập được tệp.", response.status, data);
  return data;
}
