CREATE OR REPLACE PACKAGE PKG_PERSONAL_PROFILE AUTHID DEFINER AS
  PROCEDURE profile(p_actor NUMBER, p_rows OUT SYS_REFCURSOR);
  PROCEDURE assignments(p_actor NUMBER, p_rows OUT SYS_REFCURSOR);
  PROCEDURE contracts(p_actor NUMBER, p_rows OUT SYS_REFCURSOR);
END PKG_PERSONAL_PROFILE;
/

CREATE OR REPLACE PACKAGE BODY PKG_PERSONAL_PROFILE AS
  FUNCTION own_employee(p_actor NUMBER) RETURN NUMBER IS v_employee NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor, 'EMPLOYEE');
    SELECT employee_id INTO v_employee FROM APP_USER WHERE user_id = p_actor AND is_active = 'Y';
    RETURN v_employee;
  END;

  PROCEDURE profile(p_actor NUMBER, p_rows OUT SYS_REFCURSOR) IS
    v_employee NUMBER;
    v_today DATE := TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE));
  BEGIN
    v_employee := own_employee(p_actor);
    OPEN p_rows FOR
      SELECT e.employee_id, e.employee_code, e.full_name, e.email, e.phone_number,
        e.birth_date, e.hire_date, e.termination_date, e.status,
        u.username, u.created_at account_created_at,
        d.department_name, j.position_name, a.valid_from assignment_start
      FROM EMPLOYEE e JOIN APP_USER u ON u.employee_id = e.employee_id AND u.user_id = p_actor
      LEFT JOIN EMPLOYEE_ASSIGNMENT a ON a.employee_id = e.employee_id
        AND a.valid_from <= v_today AND (a.valid_to IS NULL OR a.valid_to > v_today)
      LEFT JOIN DEPARTMENT d ON d.department_id = a.department_id
      LEFT JOIN JOB_POSITION j ON j.position_id = a.position_id
      WHERE e.employee_id = v_employee;
  END;

  PROCEDURE assignments(p_actor NUMBER, p_rows OUT SYS_REFCURSOR) IS v_employee NUMBER;
  BEGIN
    v_employee := own_employee(p_actor);
    OPEN p_rows FOR
      SELECT a.assignment_id, d.department_name, j.position_name, a.valid_from, a.valid_to
      FROM EMPLOYEE_ASSIGNMENT a
      JOIN DEPARTMENT d ON d.department_id = a.department_id
      JOIN JOB_POSITION j ON j.position_id = a.position_id
      WHERE a.employee_id = v_employee ORDER BY a.valid_from DESC, a.assignment_id DESC;
  END;

  PROCEDURE contracts(p_actor NUMBER, p_rows OUT SYS_REFCURSOR) IS v_employee NUMBER;
  BEGIN
    v_employee := own_employee(p_actor);
    OPEN p_rows FOR
      SELECT c.contract_id, c.contract_no, c.valid_from, c.valid_to,
        c.monthly_salary, c.insurance_base, c.insurance_enabled, w.calendar_name, c.status
      FROM EMPLOYMENT_CONTRACT c JOIN WORK_CALENDAR w ON w.calendar_id = c.calendar_id
      WHERE c.employee_id = v_employee AND c.status = 'APPROVED'
      ORDER BY c.valid_from DESC, c.contract_id DESC;
  END;
END PKG_PERSONAL_PROFILE;
/
GRANT EXECUTE ON PKG_PERSONAL_PROFILE TO PAYROLL_API;
