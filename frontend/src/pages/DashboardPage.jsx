import { useState } from "react";
import { getHealth, getDatabaseHealth } from "../services/api.js";

function DashboardPage() {
  const [message, setMessage] = useState("Chưa kiểm tra backend.");

  async function handleCheckBackend() {
    setMessage("Đang kiểm tra kết nối...");

    try {
      const data = await getHealth();
      setMessage(`Backend đang hoạt động: ${data.status}`);
    } catch {
      setMessage("Chưa kết nối được backend.");
    }
  }

  async function handleCheckDatabase() {
    setMessage("Đang kiểm tra kết nối Oracle...");

    try {
      const data = await getDatabaseHealth();
      setMessage(`Oracle: ${data.database}`);
    } catch {
      setMessage("Chưa kiểm tra được kết nối Oracle.");
    }
  }
  return (
    <main>
      <h1>Tổng quan</h1>
      <p>Chào mừng bạn đến với hệ thống quản lý nhân sự và tính lương.</p>

      <button type="button" onClick={handleCheckBackend}>
        Kiểm tra backend
      </button>

      <button type="button" onClick={handleCheckDatabase}>
        Kiểm tra Oracle
      </button>

      <p role="status">{message}</p>
    </main>
  );
}

export default DashboardPage;
/*message: giữ nội dung đang hiển thị.
setMessage(...): thay nội dung bảng thông báo và yêu cầu React cập nhật màn hình. Đây là cách dùng useState.
onClick={handleCheckBackend}: khi bạn bấm nút, React chạy hàm handleCheckBackend. Tài liệu React
await getHealth(): gọi hàm trong api.js và chờ backend trả lời.
try: thực hiện yêu cầu; catch: xử lý nếu yêu cầu gặp lỗi.
{message}: đưa nội dung thông báo vào giao diện.*/
