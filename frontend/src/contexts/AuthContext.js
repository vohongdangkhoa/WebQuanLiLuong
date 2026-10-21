/* import { createContext } from "react": lấy công cụ tạo Context của React.
createContext(null): tạo Context; null là giá trị mặc định khi chưa có thành phần cung cấp dữ liệu.
export default AuthContext: cho phép các file khác nhập và sử dụng Context này. */
import { createContext } from "react";

const AuthContext = createContext(null);

export default AuthContext;
