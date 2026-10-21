import { useEffect, useState } from "react";
import AuthContext from "./AuthContext";
import { getCurrentUser, loginUser, logoutUser } from "../services/api";

export default function AuthProvider({ children }) {
  /*  const [user, setUser] = useState(null);
- user: giữ thông tin tài khoản.
- null: ban đầu chưa có thông tin tài khoản.
- setUser: hàm dùng để cập nhật user. */

  const [user, setUser] = useState(null);

  /* const [isChecking, setIsChecking] = useState(true);
- isChecking: cho biết có đang kiểm tra phiên đăng nhập hay không.
- Ban đầu đặt true vì mình cần kiểm tra phiên trước khi hiển thị các trang. */

  const [isChecking, setIsChecking] = useState(true);

  /* - sessionError: giữ thông báo lỗi khi kiểm tra phiên.
- "": ban đầu chưa có thông báo lỗi.
useState cung cấp một giá trị và hàm cập nhật giá trị đó. Các hàm setUser, setIsChecking, setSessionError sẽ được dùng ở bước tiếp theo.
 */
  const [sessionError, setSessionError] = useState("");

  /* - useEffect(...): bắt đầu kiểm tra khi AuthProvider được đưa lên giao diện.
- await getCurrentUser(): chờ backend trả kết quả. Có phiên hợp lệ thì nhận thông tin tài khoản; nhận HTTP 401 thì hàm trả null.
- setUser(currentUser): lưu kết quả vào biến user.
- catch: nếu gặp lỗi mạng hoặc lỗi máy chủ, lưu thông báo vào sessionError.
- finally: kết thúc việc chờ bằng setIsChecking(false), dù kiểm tra thành công hay gặp lỗi.
Riêng ignore giúp bỏ qua kết quả đến muộn của lượt kiểm tra đã được React dọn dẹp. Đây là cách xử lý kết quả bất đồng bộ trong */

  const [retryCount, setRetryCount] = useState(0);

  useEffect(() => {
    let ignore = false;

    async function checkSession() {
      try {
        const currentUser = await getCurrentUser();

        if (!ignore) {
          setUser(currentUser);
        }
      } catch (error) {
        if (!ignore) {
          setSessionError(
            error.message || "Không kiểm tra được phiên đăng nhập.",
          );
        }
      } finally {
        if (!ignore) {
          setIsChecking(false);
        }
      }
    }

    checkSession();

    return () => {
      ignore = true;
    };
  }, [retryCount]);

  /* Hàm retrySession() làm ba việc:
- Xóa thông báo lỗi cũ.
- Bật lại trạng thái đang kiểm tra.
- Tăng retryCount để gọi backend lần nữa.
Hai câu if quyết định nội dung hiển thị:
- Đang kiểm tra → hiện dòng “Đang kiểm tra phiên đăng nhập...”.
- Kiểm tra gặp lỗi → hiện thông báo lỗi cùng nút “Thử lại”.
- Kiểm tra thành công → đi tiếp xuống phần return chứa AuthContext và hiển thị children.
Kết quả null do chưa đăng nhập vẫn là một lần kiểm tra thành công. Phần chuyển người chưa đăng nhập sang trang đăng nhập mình sẽ làm ở bước sau */

  function retrySession() {
    setSessionError("");
    setIsChecking(true);
    setRetryCount((count) => count + 1);
  }

  /*  Hai hàm này làm việc như sau:
- signIn: gửi tài khoản, mật khẩu đến backend. Khi thành công, lưu thông tin tài khoản vào user.
- signOut: chờ backend đăng xuất thành công, rồi đặt user về null.
Nếu API báo lỗi, hàm sẽ chuyển lỗi về nơi gọi để giao diện xử lý. */

  async function signIn(username, password) {
    const loggedInUser = await loginUser(username, password);

    setUser(loggedInUser);

    return loggedInUser;
  }

  async function signOut() {
    await logoutUser();

    setUser(null);
  }

  if (isChecking) {
    return <p role="status">Đang kiểm tra phiên đăng nhập...</p>;
  }

  if (sessionError) {
    return (
      <div>
        <p role="alert">{sessionError}</p>

        <button type="button" onClick={retrySession}>
          Thử lại
        </button>
      </div>
    );
  }
  /* có nghĩa là: cung cấp ba giá trị này cho các thành phần được bọc bên trong AuthProvider. children chính là những thành phần bên trong đó. */
  return (
    <AuthContext value={{ user, isChecking, sessionError, signIn, signOut }}>
      {children}
    </AuthContext>
  );
}
