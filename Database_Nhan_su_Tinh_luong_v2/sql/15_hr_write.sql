CREATE OR REPLACE PACKAGE PKG_HR_WRITE AUTHID DEFINER AS
  PROCEDURE create_employee(
    p_actor IN NUMBER,
    p_employee_code IN VARCHAR2,
    p_full_name IN VARCHAR2,
    p_hire_date IN DATE,
    p_employee_id OUT NUMBER
  );

  PROCEDURE create_assignment(
    p_actor IN NUMBER,
    p_employee_id IN NUMBER,
    p_department_id IN NUMBER,
    p_position_id IN NUMBER,
    p_valid_from IN DATE,
    p_assignment_id OUT NUMBER
  );
END PKG_HR_WRITE;
/
/* - p_actor: mã tài khoản đang thực hiện thao tác.
- p_employee_code: mã nhân viên, chẳng hạn NV004.
- p_full_name: họ tên nhân viên.
- p_hire_date: ngày vào làm.
- p_employee_id OUT: trả về số định danh nội bộ do Oracle tự tạo cho hồ sơ mới.
Đây là phần khai báo. Phần kiểm tra dữ liệu và thêm vào bảng sẽ viết ở bước kế. */

CREATE OR REPLACE PACKAGE BODY PKG_HR_WRITE AS
  PROCEDURE create_employee(
    p_actor IN NUMBER,
    p_employee_code IN VARCHAR2,
    p_full_name IN VARCHAR2,
    p_hire_date IN DATE,
    p_employee_id OUT NUMBER
  ) IS
  BEGIN
    SAVEPOINT hr_create_employee;

    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');

    IF TRIM(p_employee_code) IS NULL
       OR LENGTH(TRIM(p_employee_code)) > 30 THEN
      RAISE_APPLICATION_ERROR(
        -20300,
        'Employee code is required and must not exceed 30 characters'
      );
    END IF;

    IF TRIM(p_full_name) IS NULL
       OR LENGTH(TRIM(p_full_name)) > 150 THEN
      RAISE_APPLICATION_ERROR(
        -20301,
        'Full name is required and must not exceed 150 characters'
      );
    END IF;

    IF p_hire_date IS NULL
       OR p_hire_date <> TRUNC(p_hire_date) THEN
      RAISE_APPLICATION_ERROR(
        -20302,
        'Hire date is required and must not include a time'
      );
    END IF;

    INSERT INTO EMPLOYEE (
      employee_code,
      full_name,
      hire_date
    )
    VALUES (
      TRIM(p_employee_code),
      TRIM(p_full_name),
      p_hire_date
    )
    RETURNING employee_id INTO p_employee_id;

    PKG_PAYROLL_INTERNAL.audit_event(
      p_actor,
      'EMPLOYEE',
      p_employee_id,
      'CREATE'
    );

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO hr_create_employee;
      RAISE;
  END create_employee;
    PROCEDURE create_assignment(
    p_actor IN NUMBER,
    p_employee_id IN NUMBER,
    p_department_id IN NUMBER,
    p_position_id IN NUMBER,
    p_valid_from IN DATE,
    p_assignment_id OUT NUMBER
  ) IS
  BEGIN
    SAVEPOINT hr_create_assignment;

    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF p_employee_id IS NULL
       OR p_employee_id <= 0
       OR p_employee_id <> TRUNC(p_employee_id)
       OR p_department_id IS NULL
       OR p_department_id <= 0
       OR p_department_id <> TRUNC(p_department_id)
       OR p_position_id IS NULL
       OR p_position_id <= 0
       OR p_position_id <> TRUNC(p_position_id) THEN
      RAISE_APPLICATION_ERROR(
        -20310,
        'Employee, department and position IDs must be positive integers'
      );
    END IF;

    IF p_valid_from IS NULL
       OR p_valid_from <> TRUNC(p_valid_from) THEN
      RAISE_APPLICATION_ERROR(
        -20313,
        'Assignment start date is required and must not include a time'
      );
    END IF;
    RAISE_APPLICATION_ERROR(
      -20319,
      'Assignment creation is not ready'
    );

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO hr_create_assignment;
      RAISE;
  END create_assignment;
END PKG_HR_WRITE;
/

/* require_role(..., 'HR'): kiểm tra tài khoản có quyền nhân sự.
TRIM(...): bỏ dấu cách ở đầu và cuối thông tin.
Ba khối IF: kiểm tra mã tối đa 30 ký tự, họ tên tối đa 150 ký tự, ngày vào làm chỉ chứa ngày. Các giới hạn này khớp bảng EMPLOYEE của bạn.
INSERT INTO: thêm hồ sơ. Oracle tự tạo số ID và đặt trạng thái mặc định là ACTIVE.
RETURNING ... INTO: lấy ID vừa tạo, đưa vào biến trả về p_employee_id.
audit_event(...): ghi lại ai đã tạo hồ sơ nào.
SAVEPOINT và ROLLBACK TO: nếu thao tác gặp lỗi, hoàn tác những thay đổi từ mốc này; RAISE báo lỗi về nơi gọi. */


SELECT object_type, status
FROM user_objects
WHERE object_name = 'PKG_HR_WRITE'
  AND object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY object_type;

GRANT EXECUTE ON PKG_HR_WRITE TO PAYROLL_API;

SELECT table_name, privilege, grantable
FROM user_tab_privs_made
WHERE grantee = 'PAYROLL_API'
  AND table_name = 'PKG_HR_WRITE';