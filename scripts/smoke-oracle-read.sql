-- SQL*Plus smoke check for an existing FREEPDB1 installation.
-- Run in a fresh owner/administrative session. Prints row counts, never row contents.
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

DECLARE
  TYPE resource_list IS TABLE OF VARCHAR2(30);
  l_hr_resources resource_list := resource_list(
    'employees', 'departments', 'positions', 'calendars', 'shifts', 'leaveTypes',
    'periods', 'attendance', 'leaves', 'overtime', 'corrections', 'balances',
    'contracts', 'shiftsScheduled', 'raw'
  );
  l_config_resources resource_list := resource_list(
    'employees', 'periods', 'components', 'accounts', 'policies',
    'allowances', 'entries', 'dependents'
  );
  l_hr NUMBER;
  l_manager NUMBER;
  l_employee_actor NUMBER;
  l_own_employee NUMBER;
  l_other_employee NUMBER;
  l_employee NUMBER;
  l_calendar NUMBER;
  l_month DATE;
  l_policy NUMBER;
  l_rows SYS_REFCURSOR;

  FUNCTION active_actor(p_role VARCHAR2, p_preferred VARCHAR2) RETURN NUMBER IS
    l_actor NUMBER;
  BEGIN
    SELECT MIN(u.user_id) KEEP (DENSE_RANK FIRST ORDER BY
      CASE WHEN LOWER(u.username) = p_preferred THEN 0 ELSE 1 END, u.user_id)
    INTO l_actor
    FROM PAYROLL_APP.APP_USER u
    JOIN PAYROLL_APP.USER_ROLE ur ON ur.user_id = u.user_id
    JOIN PAYROLL_APP.APP_ROLE r ON r.role_id = ur.role_id
    WHERE u.is_active = 'Y'
      AND r.role_code = p_role
      AND (p_role <> 'EMPLOYEE' OR (
        u.employee_id IS NOT NULL AND NOT EXISTS (
          SELECT 1
          FROM PAYROLL_APP.USER_ROLE manager_role
          JOIN PAYROLL_APP.APP_ROLE manager_code ON manager_code.role_id = manager_role.role_id
          WHERE manager_role.user_id = u.user_id
            AND manager_code.role_code IN ('HR', 'PAYROLL', 'DIRECTOR')
        )
      ));
    RETURN l_actor;
  END;

  FUNCTION consume(p_rows IN OUT SYS_REFCURSOR) RETURN NUMBER IS
    l_cursor NUMBER;
    l_columns PLS_INTEGER;
    l_description DBMS_SQL.DESC_TAB2;
    l_number NUMBER;
    l_text VARCHAR2(32767);
    l_date DATE;
    l_fetched PLS_INTEGER;
    l_count NUMBER := 0;
  BEGIN
    l_cursor := DBMS_SQL.TO_CURSOR_NUMBER(p_rows);
    DBMS_SQL.DESCRIBE_COLUMNS2(l_cursor, l_columns, l_description);
    FOR i IN 1..l_columns LOOP
      CASE
        WHEN l_description(i).col_type = 2 THEN DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_number);
        WHEN l_description(i).col_type IN (1, 96) THEN DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_text, 32767);
        WHEN l_description(i).col_type = 12 THEN DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_date);
        ELSE RAISE_APPLICATION_ERROR(-20951, 'Unexpected smoke cursor column type ' || l_description(i).col_type);
      END CASE;
    END LOOP;
    LOOP
      l_fetched := DBMS_SQL.FETCH_ROWS(l_cursor);
      EXIT WHEN l_fetched = 0;
      l_count := l_count + l_fetched;
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(l_cursor);
    RETURN l_count;
  EXCEPTION WHEN OTHERS THEN
    IF l_cursor IS NOT NULL AND DBMS_SQL.IS_OPEN(l_cursor) THEN
      DBMS_SQL.CLOSE_CURSOR(l_cursor);
    END IF;
    RAISE;
  END;

  PROCEDURE hr_rows(p_resource VARCHAR2, p_actor NUMBER, p_employee NUMBER DEFAULT NULL) IS
    l_result SYS_REFCURSOR;
  BEGIN
    PAYROLL_APP.PKG_HR_PORTAL.read_data(
      p_actor => p_actor, p_resource => p_resource, p_period => NULL,
      p_employee => p_employee, p_rows => l_result);
    DBMS_OUTPUT.PUT_LINE('PASS HR.' || p_resource || ' rows=' || consume(l_result));
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FAIL HR.' || p_resource || ' Oracle=' || SQLCODE);
    RAISE;
  END;

  PROCEDURE config_rows(p_resource VARCHAR2, p_actor NUMBER, p_period NUMBER DEFAULT NULL) IS
    l_result SYS_REFCURSOR;
  BEGIN
    PAYROLL_APP.PKG_CONFIGURATION.read_data(
      p_actor => p_actor, p_resource => p_resource, p_employee => NULL,
      p_period => p_period, p_rows => l_result);
    DBMS_OUTPUT.PUT_LINE('PASS CONFIG.' || p_resource || ' rows=' || consume(l_result));
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('FAIL CONFIG.' || p_resource || ' Oracle=' || SQLCODE);
    RAISE;
  END;
BEGIN
  l_hr := active_actor('HR', 'hr.demo');
  l_manager := COALESCE(l_hr, active_actor('PAYROLL', 'payroll.demo'), active_actor('DIRECTOR', 'director.demo'));
  l_employee_actor := active_actor('EMPLOYEE', 'employee.demo');

  IF l_hr IS NOT NULL THEN
    FOR i IN 1..l_hr_resources.COUNT LOOP
      hr_rows(l_hr_resources(i), l_hr);
    END LOOP;
    SELECT MIN(employee_id) INTO l_employee FROM PAYROLL_APP.EMPLOYEE;
    IF l_employee IS NOT NULL THEN
      hr_rows('profile', l_hr, l_employee);
    ELSE
      DBMS_OUTPUT.PUT_LINE('SKIP HR.profile no employee record');
    END IF;
    SELECT MIN(calendar_id) INTO l_calendar FROM PAYROLL_APP.WORK_CALENDAR;
    IF l_calendar IS NOT NULL THEN
      SELECT TRUNC(NVL(MIN(work_date), CURRENT_DATE), 'MM') INTO l_month
      FROM PAYROLL_APP.CALENDAR_DAY WHERE calendar_id = l_calendar;
      PAYROLL_APP.PKG_HR_PORTAL.read_calendar(
        p_actor => l_hr, p_calendar => l_calendar, p_month => l_month, p_rows => l_rows);
      DBMS_OUTPUT.PUT_LINE('PASS HR.calendar rows=' || consume(l_rows));
    ELSE
      DBMS_OUTPUT.PUT_LINE('SKIP HR.calendar no calendar record');
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIP HR no active account with HR role');
  END IF;

  IF l_manager IS NOT NULL THEN
    FOR i IN 1..l_config_resources.COUNT LOOP
      config_rows(l_config_resources(i), l_manager);
    END LOOP;
    SELECT MIN(policy_id) INTO l_policy FROM PAYROLL_APP.PAYROLL_POLICY;
    config_rows('brackets', l_manager, l_policy);
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIP CONFIG manager lists no active manager account');
  END IF;

  IF l_employee_actor IS NOT NULL THEN
    SELECT employee_id INTO l_own_employee
    FROM PAYROLL_APP.APP_USER WHERE user_id = l_employee_actor;
    SELECT MIN(employee_id) INTO l_other_employee
    FROM PAYROLL_APP.EMPLOYEE WHERE employee_id <> l_own_employee;
    hr_rows('attendance', l_employee_actor, l_own_employee);
    config_rows('employees', l_employee_actor);
    config_rows('dependents', l_employee_actor);
    IF l_other_employee IS NOT NULL THEN
      PAYROLL_APP.PKG_HR_PORTAL.read_data(l_employee_actor, 'attendance', NULL, l_other_employee, l_rows);
      IF consume(l_rows) <> 0 THEN
        RAISE_APPLICATION_ERROR(-20952, 'Employee attendance scope returned another employee');
      END IF;
      DBMS_OUTPUT.PUT_LINE('PASS EMPLOYEE other attendance rows=0');
      BEGIN
        PAYROLL_APP.PKG_CONFIGURATION.read_data(l_employee_actor, 'dependents', l_other_employee, NULL, l_rows);
        l_employee := consume(l_rows);
        RAISE_APPLICATION_ERROR(-20953, 'Employee dependent scope should deny another employee');
      EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> -20002 THEN RAISE; END IF;
        DBMS_OUTPUT.PUT_LINE('PASS EMPLOYEE other dependents denied');
      END;
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE('SKIP EMPLOYEE no active linked employee-only account');
  END IF;
END;
/
