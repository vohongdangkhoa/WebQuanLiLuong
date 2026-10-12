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
