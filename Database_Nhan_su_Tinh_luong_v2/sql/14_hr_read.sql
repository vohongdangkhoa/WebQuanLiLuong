CREATE OR REPLACE PACKAGE PKG_HR_READ AUTHID DEFINER AS
  PROCEDURE list_employees(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  );

   PROCEDURE list_departments(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  );

  PROCEDURE list_job_positions(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  );
    PROCEDURE list_employee_assignments(
    p_actor IN NUMBER,
    p_employee_id IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  );
END PKG_HR_READ;
/
/* 
- PACKAGE PKG_HR_READ: khai báo tên gói lệnh.
- AUTHID DEFINER: các lệnh trong gói sử dụng quyền của chủ sở hữu gói, ở đây là PAYROLL_APP.
- PROCEDURE list_employees: khai báo một thủ tục có tên list_employees, dùng để lấy danh sách nhân viên.
- p_actor IN NUMBER: nhận vào mã tài khoản đang thực hiện thao tác.
- p_rows OUT SYS_REFCURSOR: trả ra kết quả truy vấn gồm nhiều dòng.
Đây là phần khai báo: cho biết tên thủ tục, thông tin nhận vào và kết quả trả ra. Phần xử lý truy vấn mình sẽ viết ở bước kế. */


CREATE OR REPLACE PACKAGE BODY PKG_HR_READ AS
  PROCEDURE list_employees(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  ) IS
    v_today DATE := TRUNC(
      CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE)
    );
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');

    OPEN p_rows FOR
      SELECT e.employee_id,
             e.employee_code,
             e.full_name,
             d.department_name,
             jp.position_name,
             e.status
      FROM EMPLOYEE e
      LEFT JOIN EMPLOYEE_ASSIGNMENT a
          ON a.employee_id = e.employee_id
         AND a.valid_from <= v_today
         AND (a.valid_to IS NULL OR a.valid_to > v_today)
          LEFT JOIN DEPARTMENT d
          ON d.department_id = a.department_id
      LEFT JOIN JOB_POSITION jp
          ON jp.position_id = a.position_id
      ORDER BY e.employee_code;
  END list_employees;
    PROCEDURE list_departments(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  ) IS
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');

    OPEN p_rows FOR
      SELECT department_id,
             department_code,
             department_name
      FROM DEPARTMENT
      WHERE is_active = 'Y'
      ORDER BY department_code;
    END list_departments;

  PROCEDURE list_job_positions(
    p_actor IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  ) IS
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');

    OPEN p_rows FOR
      SELECT position_id,
             position_code,
             position_name
      FROM JOB_POSITION
      WHERE is_active = 'Y'
      ORDER BY position_code;
  END list_job_positions;
    PROCEDURE list_employee_assignments(
    p_actor IN NUMBER,
    p_employee_id IN NUMBER,
    p_rows OUT SYS_REFCURSOR
  ) IS
    v_employee_count NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');

    IF p_employee_id IS NULL
       OR p_employee_id <= 0
       OR p_employee_id <> TRUNC(p_employee_id) THEN
      RAISE_APPLICATION_ERROR(
        -20310, 'Employee ID must be a positive integer'
      );
    END IF;

    SELECT COUNT(*)
    INTO v_employee_count
    FROM EMPLOYEE
    WHERE employee_id = p_employee_id;

    IF v_employee_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20311, 'Employee not found');
    END IF;

    OPEN p_rows FOR
      SELECT a.assignment_id,
             e.employee_code,
             d.department_name,
             jp.position_name,
             a.valid_from,
             a.valid_to
      FROM EMPLOYEE_ASSIGNMENT a
      JOIN EMPLOYEE e
          ON e.employee_id = a.employee_id
      JOIN DEPARTMENT d
          ON d.department_id = a.department_id
      JOIN JOB_POSITION jp
          ON jp.position_id = a.position_id
      WHERE a.employee_id = p_employee_id
      ORDER BY a.valid_from DESC, a.assignment_id DESC;
  END list_employee_assignments;
END PKG_HR_READ;
/
/* - PACKAGE BODY: nơi viết cách các thủ tục trong gói hoạt động.
- v_today: biến giữ ngày hôm nay theo giờ Việt Nam, giúp câu truy vấn gọn hơn.
- require_role(p_actor, 'HR'): kiểm tra tài khoản còn hoạt động và có quyền Nhân sự trước khi đọc dữ liệu.
- OPEN p_rows FOR: mở kết quả câu truy vấn để backend đọc qua p_rows.
Phần nối ba bảng chính là câu truy vấn bạn vừa kiểm tra thành công trong DBeaver. */




/*GRANT EXECUTE: cấp quyền gọi các thủ tục trong gói.
ON PKG_HR_READ: áp dụng cho gói đọc nhân viên vừa tạo.
TO PAYROLL_API: tài khoản nhận quyền.*/

GRANT EXECUTE ON PKG_HR_READ TO PAYROLL_API;