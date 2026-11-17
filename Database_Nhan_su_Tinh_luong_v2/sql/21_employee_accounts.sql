-- Add employee contact details and HR account issuance to an existing schema.
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM all_tab_columns
  WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
    AND table_name = 'EMPLOYEE' AND column_name = 'PHONE_NUMBER';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE EMPLOYEE ADD (phone_number VARCHAR2(10 CHAR))';
  END IF;
END;
/

CREATE OR REPLACE PACKAGE PKG_EMPLOYEE_ACCOUNTS AUTHID DEFINER AS
  PROCEDURE get_context(p_actor NUMBER, p_employee NUMBER, p_lock NUMBER, p_rows OUT SYS_REFCURSOR);
  PROCEDURE create_account(p_actor NUMBER, p_employee NUMBER, p_version NUMBER,
    p_phone VARCHAR2, p_birth DATE, p_username VARCHAR2, p_hash VARCHAR2, p_id OUT NUMBER);
END PKG_EMPLOYEE_ACCOUNTS;
/

CREATE OR REPLACE PACKAGE BODY PKG_EMPLOYEE_ACCOUNTS AS
  PROCEDURE get_context(p_actor NUMBER, p_employee NUMBER, p_lock NUMBER, p_rows OUT SYS_REFCURSOR) IS
    v_id NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');
    IF p_lock = 1 THEN
      SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id = p_employee FOR UPDATE NOWAIT;
    ELSE
      SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id = p_employee;
    END IF;
    OPEN p_rows FOR
      SELECT e.employee_id, e.employee_code, e.full_name, e.birth_date, e.hire_date,
        e.phone_number, e.status, e.termination_date, e.row_version,
        u.user_id, u.username, u.is_active
      FROM EMPLOYEE e LEFT JOIN APP_USER u ON u.employee_id = e.employee_id
      WHERE e.employee_id = p_employee;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20700, 'Employee not found');
  END;

  PROCEDURE create_account(p_actor NUMBER, p_employee NUMBER, p_version NUMBER,
    p_phone VARCHAR2, p_birth DATE, p_username VARCHAR2, p_hash VARCHAR2, p_id OUT NUMBER) IS
    v_employee EMPLOYEE%ROWTYPE;
    v_count NUMBER;
    v_role NUMBER;
  BEGIN
    SAVEPOINT employee_account_create;
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'HR');
    SELECT * INTO v_employee FROM EMPLOYEE WHERE employee_id = p_employee FOR UPDATE NOWAIT;
    SELECT COUNT(*) INTO v_count FROM APP_USER WHERE employee_id = p_employee;
    IF v_count > 0 THEN RAISE_APPLICATION_ERROR(-20701, 'Employee already has an account'); END IF;
    IF p_version IS NULL OR v_employee.row_version <> p_version THEN
      RAISE_APPLICATION_ERROR(-20702, 'Employee profile changed');
    END IF;
    IF v_employee.status <> 'ACTIVE' OR v_employee.termination_date IS NOT NULL THEN
      RAISE_APPLICATION_ERROR(-20703, 'Employee is not active');
    END IF;
    IF p_phone IS NULL OR LENGTH(p_phone) <> 10 OR NOT REGEXP_LIKE(p_phone, '^0[0-9]{9}$', 'c')
      OR NOT REGEXP_LIKE(v_employee.employee_code, '[0-9]{2}$', 'c')
      OR p_username IS NULL OR p_username <> SUBSTR(v_employee.employee_code, -2) || p_phone
      OR p_hash IS NULL OR LENGTH(p_hash) < 50 OR LENGTH(p_hash) > 500 THEN
      RAISE_APPLICATION_ERROR(-20704, 'Invalid generated credentials');
    END IF;
    IF p_birth IS NULL OR p_birth <> TRUNC(p_birth) OR p_birth >= v_employee.hire_date
      OR p_birth >= TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE)) THEN
      RAISE_APPLICATION_ERROR(-20705, 'Invalid birth date');
    END IF;
    IF v_employee.birth_date IS NOT NULL AND v_employee.birth_date <> p_birth THEN
      RAISE_APPLICATION_ERROR(-20706, 'Birth date differs from employee profile');
    END IF;
    SELECT role_id INTO v_role FROM APP_ROLE WHERE role_code = 'EMPLOYEE';
    INSERT INTO APP_USER(username, password_hash, employee_id, is_active)
      VALUES(p_username, p_hash, p_employee, 'Y') RETURNING user_id INTO p_id;
    INSERT INTO USER_ROLE(user_id, role_id) VALUES(p_id, v_role);
    UPDATE EMPLOYEE SET phone_number = p_phone, birth_date = p_birth, row_version = row_version + 1
      WHERE employee_id = p_employee;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor, 'EMPLOYEE', p_employee, 'CREATE_EMPLOYEE_ACCOUNT',
      'Created account ID ' || TO_CHAR(p_id));
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO employee_account_create;
    RAISE;
  END;
END PKG_EMPLOYEE_ACCOUNTS;
/
GRANT EXECUTE ON PKG_EMPLOYEE_ACCOUNTS TO PAYROLL_API;
