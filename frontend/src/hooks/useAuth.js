import { useContext } from "react";
import AuthContext from "../contexts/AuthContext";

/* - useContext(AuthContext): đọc dữ liệu mà AuthProvider cung cấp. Tài liệu React
- auth === null: phát hiện component gọi hàm này đang nằm ngoài AuthProvider.
- return auth: trả về các giá trị mình đã cung cấp: user, isChecking, sessionError, signIn, signOut.
Chú ý phân biệt: auth === null là thiếu Provider; còn auth.user === null là chưa có tài khoản đăng nhập. */

export default function useAuth() {
  const auth = useContext(AuthContext);

  if (auth === null) {
    throw new Error("useAuth phải được sử dụng bên trong AuthProvider.");
  }

  return auth;
}
