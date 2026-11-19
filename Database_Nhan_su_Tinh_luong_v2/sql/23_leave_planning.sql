CREATE OR REPLACE PACKAGE PKG_LEAVE_PLANNING AUTHID DEFINER AS
  FUNCTION day_minutes(p_day_type VARCHAR2,p_standard NUMBER,p_duration VARCHAR2,p_minutes NUMBER) RETURN NUMBER;
  PROCEDURE lock_plan(p_actor NUMBER,p_employee NUMBER);
  PROCEDURE preview(p_actor NUMBER,p_employee NUMBER,p_from DATE,p_to DATE,
    p_duration VARCHAR2,p_minutes NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE submit(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_from DATE,p_to DATE,
    p_duration VARCHAR2,p_minutes NUMBER,p_reason VARCHAR2,p_id OUT NUMBER);
END PKG_LEAVE_PLANNING;
/
CREATE OR REPLACE PACKAGE BODY PKG_LEAVE_PLANNING AS
  FUNCTION day_minutes(p_day_type VARCHAR2,p_standard NUMBER,p_duration VARCHAR2,p_minutes NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN CASE
      WHEN p_day_type IN ('RESTDAY','HOLIDAY') THEN 0
      WHEN p_day_type<>'WORKDAY' OR p_standard IS NULL THEN NULL
      WHEN p_standard=0 THEN 0
      WHEN p_duration='FULL' THEN p_standard
      WHEN p_duration='HALF' AND MOD(p_standard,2)=0 THEN p_standard/2
      WHEN p_duration='HOURS' AND p_minutes>0 AND p_minutes<=p_standard AND p_minutes=TRUNC(p_minutes) THEN p_minutes
      ELSE NULL END;
  END;

  PROCEDURE require_access(p_actor NUMBER,p_employee NUMBER) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u WHERE u.user_id=p_actor AND u.is_active='Y'
      AND EXISTS(SELECT 1 FROM USER_ROLE ur JOIN APP_ROLE r ON r.role_id=ur.role_id
        WHERE ur.user_id=u.user_id AND (r.role_code='HR' OR (r.role_code='EMPLOYEE' AND u.employee_id=p_employee)));
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20002,'Leave employee access denied');END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Employee not found');END IF;
  END;

  PROCEDURE lock_plan(p_actor NUMBER,p_employee NUMBER) IS v_id NUMBER;
  BEGIN
    require_access(p_actor,p_employee);
    PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id=p_employee FOR UPDATE NOWAIT;
  END;

  PROCEDURE preview(p_actor NUMBER,p_employee NUMBER,p_from DATE,p_to DATE,
    p_duration VARCHAR2,p_minutes NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_access(p_actor,p_employee);
    IF p_from IS NULL OR p_to IS NULL OR p_from<>TRUNC(p_from) OR p_to<>TRUNC(p_to)
      OR p_to<=p_from OR p_to-p_from>366 OR p_duration IS NULL OR p_duration NOT IN ('FULL','HALF','HOURS')
      OR (p_duration='HOURS' AND (p_minutes IS NULL OR p_minutes<>TRUNC(p_minutes) OR p_minutes<=0 OR p_minutes>1440))
      THEN RAISE_APPLICATION_ERROR(-20800,'Invalid leave duration');END IF;
    OPEN p_rows FOR
      WITH dates AS (SELECT p_from+LEVEL-1 work_date FROM dual CONNECT BY LEVEL<=p_to-p_from),
      schedule AS (
        SELECT d.work_date,c.contract_id,c.calendar_id,w.calendar_name,cd.day_type,cd.standard_minutes,
          CASE
            WHEN d.work_date<e.hire_date OR (e.termination_date IS NOT NULL AND d.work_date>e.termination_date) THEN 'OUTSIDE_EMPLOYMENT'
            WHEN c.contract_id IS NULL THEN 'MISSING_CONTRACT'
            WHEN cd.work_date IS NULL THEN 'MISSING_CALENDAR'
            WHEN cd.day_type<>'WORKDAY' OR cd.standard_minutes=0 THEN NULL
            WHEN p_duration='HALF' AND MOD(cd.standard_minutes,2)<>0 THEN 'FRACTIONAL_HALF'
            WHEN p_duration='HOURS' AND p_minutes>cd.standard_minutes THEN 'EXCEEDS_DAY'
            ELSE NULL END issue_code
        FROM dates d JOIN EMPLOYEE e ON e.employee_id=p_employee
        LEFT JOIN EMPLOYMENT_CONTRACT c ON c.employee_id=e.employee_id AND c.status='APPROVED'
          AND c.valid_from<=d.work_date AND (c.valid_to IS NULL OR c.valid_to>d.work_date)
        LEFT JOIN WORK_CALENDAR w ON w.calendar_id=c.calendar_id
        LEFT JOIN CALENDAR_DAY cd ON cd.calendar_id=c.calendar_id AND cd.work_date=d.work_date
      )
      SELECT work_date,contract_id,calendar_id,calendar_name,day_type,standard_minutes,
        CASE WHEN issue_code IS NOT NULL THEN NULL
          ELSE PKG_LEAVE_PLANNING.day_minutes(day_type,standard_minutes,p_duration,p_minutes)
          END leave_minutes,issue_code
      FROM schedule ORDER BY work_date;
  END;

  PROCEDURE submit(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_from DATE,p_to DATE,
    p_duration VARCHAR2,p_minutes NUMBER,p_reason VARCHAR2,p_id OUT NUMBER) IS
    v_rows SYS_REFCURSOR;v_date DATE;v_contract NUMBER;v_calendar NUMBER;v_calendar_name VARCHAR2(150);
    v_day_type VARCHAR2(20);v_standard NUMBER;v_minutes NUMBER;v_issue VARCHAR2(40);v_n NUMBER;v_total NUMBER:=0;
  BEGIN
    SAVEPOINT scheduled_leave;
    lock_plan(p_actor,p_employee);
    IF TRIM(p_reason) IS NULL OR LENGTH(TRIM(p_reason))<3 OR LENGTH(p_reason)>1000 THEN
      RAISE_APPLICATION_ERROR(-20801,'Leave reason required');END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_TYPE WHERE leave_type_id=p_type;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Leave type not found');END IF;
    preview(p_actor,p_employee,p_from,p_to,p_duration,p_minutes,v_rows);
    SELECT COUNT(*) INTO v_n FROM LEAVE_REQUEST WHERE employee_id=p_employee AND status IN ('PENDING','APPROVED')
      AND starts_at<CAST(p_to AS TIMESTAMP) AND ends_at>CAST(p_from AS TIMESTAMP);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20410,'Overlapping leave');END IF;
    INSERT INTO LEAVE_REQUEST(employee_id,leave_type_id,starts_at,ends_at,reason,requested_by)
      VALUES(p_employee,p_type,CAST(p_from AS TIMESTAMP),CAST(p_to AS TIMESTAMP),TRIM(p_reason),p_actor)
      RETURNING leave_id INTO p_id;
    LOOP
      FETCH v_rows INTO v_date,v_contract,v_calendar,v_calendar_name,v_day_type,v_standard,v_minutes,v_issue;
      EXIT WHEN v_rows%NOTFOUND;
      IF v_issue IS NOT NULL THEN RAISE_APPLICATION_ERROR(-20802,'Work calendar is incomplete or duration invalid');END IF;
      IF v_minutes>0 THEN
        INSERT INTO LEAVE_DAY(leave_id,work_date,minutes) VALUES(p_id,v_date,v_minutes);
        v_total:=v_total+v_minutes;
      END IF;
    END LOOP;
    CLOSE v_rows;
    IF v_total=0 THEN RAISE_APPLICATION_ERROR(-20803,'No working days in request');END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'LEAVE_REQUEST',p_id,'CREATE',p_reason);
    INSERT INTO APP_NOTIFICATION(user_id,title,body,entity_type,entity_id)
      SELECT u.user_id,'Đơn nghỉ phép mới','Mở mục Đơn từ để xem yêu cầu đang chờ xử lý.','LEAVE_REQUEST',p_id
      FROM APP_USER u WHERE u.is_active='Y' AND u.user_id<>p_actor AND EXISTS (
        SELECT 1 FROM USER_ROLE ur JOIN APP_ROLE r ON r.role_id=ur.role_id WHERE ur.user_id=u.user_id AND r.role_code='HR');
  EXCEPTION WHEN OTHERS THEN
    IF v_rows%ISOPEN THEN CLOSE v_rows;END IF;
    ROLLBACK TO scheduled_leave;RAISE;
  END;
END PKG_LEAVE_PLANNING;
/
GRANT EXECUTE ON PKG_LEAVE_PLANNING TO PAYROLL_API;
