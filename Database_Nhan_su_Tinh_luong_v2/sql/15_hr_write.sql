CREATE OR REPLACE PACKAGE PKG_HR_WRITE AUTHID DEFINER AS
  PROCEDURE create_employee(
    p_actor IN NUMBER,
    p_employee_code IN VARCHAR2,
    p_full_name IN VARCHAR2,
    p_hire_date IN DATE,
    p_employee_id OUT NUMBER
  );
END PKG_HR_WRITE;
/
/* - p_actor: mã tài khoản đang thực hiện thao tác.
- p_employee_code: mã nhân viên, chẳng hạn NV004.
- p_full_name: họ tên nhân viên.
- p_hire_date: ngày vào làm.
- p_employee_id OUT: trả về số định danh nội bộ do Oracle tự tạo cho hồ sơ mới.
Đây là phần khai báo. Phần kiểm tra dữ liệu và thêm vào bảng sẽ viết ở bước kế. */