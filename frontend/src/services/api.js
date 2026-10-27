const API_BASE_URL = "http://localhost:5038/api";
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
    throw new Error("Không kiểm tra được phiên đăng nhập X .");
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
