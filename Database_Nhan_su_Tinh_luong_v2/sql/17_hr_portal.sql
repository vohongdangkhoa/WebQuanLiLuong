-- Non-destructive application extension. Install as PAYROLL_APP after 14/15.
-- Business procedures never COMMIT. The API owns the request transaction.
CREATE OR REPLACE PACKAGE PKG_HR_PORTAL AUTHID DEFINER AS
  PROCEDURE read_data(p_actor NUMBER,p_resource VARCHAR2,p_period NUMBER,p_employee NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE save_organization_catalog(p_actor NUMBER,p_kind VARCHAR2,p_existing NUMBER,p_code VARCHAR2,p_name VARCHAR2,p_active VARCHAR2,p_id OUT NUMBER);
  PROCEDURE update_employee(p_actor NUMBER,p_employee NUMBER,p_name VARCHAR2,p_email VARCHAR2,p_birth DATE,p_status VARCHAR2,p_termination DATE,p_version NUMBER);
  PROCEDURE transfer_employee(p_actor NUMBER,p_employee NUMBER,p_department NUMBER,p_position NUMBER,p_from DATE,p_reason VARCHAR2,p_id OUT NUMBER);
  PROCEDURE create_contract(p_actor NUMBER,p_employee NUMBER,p_no VARCHAR2,p_from DATE,p_to DATE,p_salary NUMBER,p_insurance NUMBER,p_enabled VARCHAR2,p_calendar NUMBER,p_id OUT NUMBER);
  PROCEDURE decide_contract(p_actor NUMBER,p_contract NUMBER,p_decision VARCHAR2,p_reason VARCHAR2);
  PROCEDURE prepare_calendar(p_actor NUMBER,p_calendar NUMBER,p_month DATE);
  PROCEDURE read_calendar(p_actor NUMBER,p_calendar NUMBER,p_month DATE,p_rows OUT SYS_REFCURSOR);
  PROCEDURE save_calendar_day(p_actor NUMBER,p_calendar NUMBER,p_date DATE,p_type VARCHAR2,p_minutes NUMBER);
  PROCEDURE create_leave(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_from DATE,p_to DATE,p_minutes NUMBER,p_reason VARCHAR2,p_id OUT NUMBER);
  PROCEDURE create_overtime(p_actor NUMBER,p_employee NUMBER,p_from TIMESTAMP,p_to TIMESTAMP,p_reason VARCHAR2,p_id OUT NUMBER);
  PROCEDURE reject_overtime(p_actor NUMBER,p_ot NUMBER,p_reason VARCHAR2);
  PROCEDURE create_correction(p_actor NUMBER,p_period NUMBER,p_employee NUMBER,p_source VARCHAR2,p_source_id NUMBER,p_reason VARCHAR2,p_id OUT NUMBER);
  PROCEDURE resolve_correction(p_actor NUMBER,p_request NUMBER,p_reason VARCHAR2);
  PROCEDURE grant_leave(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_date DATE,p_minutes NUMBER,p_reason VARCHAR2,p_key VARCHAR2,p_id OUT NUMBER);
  PROCEDURE save_shift(p_actor NUMBER,p_employee NUMBER,p_date DATE,p_shift NUMBER,p_id OUT NUMBER);
  PROCEDURE start_import(p_actor NUMBER,p_hash VARCHAR2,p_storage_key VARCHAR2,p_name VARCHAR2,p_size NUMBER,p_id OUT NUMBER,p_existing OUT NUMBER);
  PROCEDURE append_raw(p_actor NUMBER,p_import NUMBER,p_employee_code VARCHAR2,p_event TIMESTAMP,p_type VARCHAR2,p_device VARCHAR2,p_key VARCHAR2,p_inserted OUT NUMBER);
  PROCEDURE finish_import(p_actor NUMBER,p_import NUMBER,p_errors OUT NUMBER);
END PKG_HR_PORTAL;
/
CREATE OR REPLACE PACKAGE BODY PKG_HR_PORTAL AS
  FUNCTION has_role(p_actor NUMBER,p_role VARCHAR2) RETURN NUMBER IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u JOIN USER_ROLE ur ON ur.user_id=u.user_id JOIN APP_ROLE r ON r.role_id=ur.role_id
    WHERE u.user_id=p_actor AND u.is_active='Y' AND r.role_code=p_role;
    RETURN CASE WHEN v_n>0 THEN 1 ELSE 0 END;
  END;
  PROCEDURE positive(p_id NUMBER) IS BEGIN
    IF p_id IS NULL OR p_id<=0 OR p_id<>TRUNC(p_id) THEN RAISE_APPLICATION_ERROR(-20400,'Positive integer required'); END IF;
  END;
  PROCEDURE reason_required(p_reason VARCHAR2) IS BEGIN
    IF TRIM(p_reason) IS NULL OR LENGTH(p_reason)>1000 THEN RAISE_APPLICATION_ERROR(-20400,'Reason required, maximum 1000 characters'); END IF;
  END;
  PROCEDURE notify_hr(p_actor NUMBER,p_title VARCHAR2,p_detail VARCHAR2,p_entity VARCHAR2,p_id NUMBER) IS
  BEGIN
    INSERT INTO APP_NOTIFICATION(user_id,title,body,entity_type,entity_id)
      SELECT u.user_id,p_title,p_detail,p_entity,p_id FROM APP_USER u
      WHERE u.is_active='Y' AND u.user_id<>p_actor
        AND EXISTS(SELECT 1 FROM USER_ROLE ur JOIN APP_ROLE r ON r.role_id=ur.role_id
          WHERE ur.user_id=u.user_id AND r.role_code='HR');
  END;
  PROCEDURE employee_exists(p_employee NUMBER) IS v_n NUMBER;
  BEGIN
    positive(p_employee); SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee;
    IF v_n=0 THEN RAISE_APPLICATION_ERROR(-20404,'Employee not found'); END IF;
  END;
  PROCEDURE own_or_hr(p_actor NUMBER,p_employee NUMBER) IS v_employee NUMBER;
  BEGIN
    employee_exists(p_employee);
    IF has_role(p_actor,'HR')=1 THEN RETURN; END IF;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'EMPLOYEE');
    SELECT employee_id INTO v_employee FROM APP_USER WHERE user_id=p_actor AND is_active='Y';
    IF v_employee IS NULL OR v_employee<>p_employee THEN RAISE_APPLICATION_ERROR(-20403,'Employee access denied'); END IF;
  END;
  PROCEDURE read_data(p_actor NUMBER,p_resource VARCHAR2,p_period NUMBER,p_employee NUMBER,p_rows OUT SYS_REFCURSOR) IS
    v_employee NUMBER; v_manager NUMBER; v_hr_view NUMBER;
  BEGIN
    BEGIN SELECT employee_id INTO v_employee FROM APP_USER WHERE user_id=p_actor AND is_active='Y';
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20403,'Inactive actor'); END;
    v_manager:=GREATEST(has_role(p_actor,'HR'),has_role(p_actor,'PAYROLL'),has_role(p_actor,'DIRECTOR'));
    v_hr_view:=GREATEST(has_role(p_actor,'HR'),has_role(p_actor,'DIRECTOR'));
    IF p_period IS NOT NULL THEN positive(p_period); END IF;
    IF p_employee IS NOT NULL THEN positive(p_employee); END IF;
    IF p_resource='employees' THEN
      OPEN p_rows FOR SELECT employee_id,employee_code,full_name,TO_CHAR(hire_date,'YYYY-MM-DD') hire_date,status
        FROM EMPLOYEE WHERE v_manager=1 OR employee_id=v_employee ORDER BY employee_code;
    ELSIF p_resource='departments' THEN
      OPEN p_rows FOR SELECT department_id,department_code,department_name FROM DEPARTMENT WHERE is_active='Y' ORDER BY department_code;
    ELSIF p_resource='positions' THEN
      OPEN p_rows FOR SELECT position_id,position_code,position_name FROM JOB_POSITION WHERE is_active='Y' ORDER BY position_code;
    ELSIF p_resource='departmentCatalog' THEN
      PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');
      OPEN p_rows FOR SELECT department_id id,department_code code,department_name name,is_active FROM DEPARTMENT ORDER BY department_code;
    ELSIF p_resource='positionCatalog' THEN
      PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');
      OPEN p_rows FOR SELECT position_id id,position_code code,position_name name,is_active FROM JOB_POSITION ORDER BY position_code;
    ELSIF p_resource='calendars' THEN
      OPEN p_rows FOR SELECT calendar_id,calendar_code,calendar_name FROM WORK_CALENDAR ORDER BY calendar_code;
    ELSIF p_resource='shifts' THEN
      OPEN p_rows FOR SELECT shift_id,shift_code,shift_name FROM WORK_SHIFT ORDER BY shift_code;
    ELSIF p_resource='leaveTypes' THEN
      OPEN p_rows FOR SELECT leave_type_id,leave_code,leave_name,uses_balance FROM LEAVE_TYPE ORDER BY leave_code;
    ELSIF p_resource='periods' THEN
      OPEN p_rows FOR SELECT period_id,TO_CHAR(period_start,'YYYY-MM-DD') period_start,TO_CHAR(period_end,'YYYY-MM-DD') period_end,
        period_status,timesheet_status FROM PAYROLL_PERIOD ORDER BY period_start DESC;
    ELSIF p_resource='attendance' THEN
      OPEN p_rows FOR SELECT t.timesheet_id,t.period_id,t.employee_id,e.employee_code,e.full_name,TO_CHAR(t.work_date,'YYYY-MM-DD') work_date,
        t.worked_minutes,t.paid_leave_minutes,t.paid_holiday_minutes,t.paid_minutes,t.late_minutes,t.status,t.error_message
        FROM TIMESHEET_DAILY t JOIN EMPLOYEE e ON e.employee_id=t.employee_id
        WHERE (v_manager=1 OR t.employee_id=v_employee) AND (p_period IS NULL OR t.period_id=p_period)
          AND (p_employee IS NULL OR t.employee_id=p_employee)
        ORDER BY t.work_date DESC,e.employee_code FETCH FIRST 5000 ROWS ONLY;
    ELSIF p_resource='leaves' THEN
      OPEN p_rows FOR SELECT l.leave_id,l.employee_id,e.employee_code,e.full_name,l.leave_type_id,lt.leave_name,
        TO_CHAR(l.starts_at,'YYYY-MM-DD"T"HH24:MI:SS') starts_at,TO_CHAR(l.ends_at,'YYYY-MM-DD"T"HH24:MI:SS') ends_at,
        l.reason,l.status,l.requested_by,l.decision_reason FROM LEAVE_REQUEST l JOIN EMPLOYEE e ON e.employee_id=l.employee_id
        JOIN LEAVE_TYPE lt ON lt.leave_type_id=l.leave_type_id
        WHERE (v_hr_view=1 OR l.employee_id=v_employee) AND (p_employee IS NULL OR l.employee_id=p_employee)
        ORDER BY l.leave_id DESC FETCH FIRST 2000 ROWS ONLY;
    ELSIF p_resource='overtime' THEN
      OPEN p_rows FOR SELECT o.overtime_id,o.employee_id,e.employee_code,e.full_name,
        TO_CHAR(o.starts_at,'YYYY-MM-DD"T"HH24:MI:SS') starts_at,TO_CHAR(o.ends_at,'YYYY-MM-DD"T"HH24:MI:SS') ends_at,
        o.approved_minutes,o.actual_minutes,o.status,o.reason,o.requested_by FROM OVERTIME_REQUEST o JOIN EMPLOYEE e ON e.employee_id=o.employee_id
        WHERE (v_hr_view=1 OR o.employee_id=v_employee) AND (p_employee IS NULL OR o.employee_id=p_employee)
        ORDER BY o.overtime_id DESC FETCH FIRST 2000 ROWS ONLY;
    ELSIF p_resource='corrections' THEN
      OPEN p_rows FOR SELECT c.change_request_id,c.period_id,c.employee_id,e.employee_code,c.source_type,c.source_id,c.reason,c.status,c.requested_by
        FROM INPUT_CHANGE_REQUEST c LEFT JOIN EMPLOYEE e ON e.employee_id=c.employee_id
        WHERE (v_manager=1 OR c.employee_id=v_employee) AND (p_employee IS NULL OR c.employee_id=p_employee)
        ORDER BY c.change_request_id DESC FETCH FIRST 2000 ROWS ONLY;
    ELSIF p_resource='balances' THEN
      OPEN p_rows FOR SELECT e.employee_id,e.employee_code,l.leave_type_id,l.leave_name,NVL(SUM(g.delta_minutes),0) balance_minutes
        FROM EMPLOYEE e CROSS JOIN LEAVE_TYPE l LEFT JOIN LEAVE_LEDGER g ON g.employee_id=e.employee_id AND g.leave_type_id=l.leave_type_id
          AND g.effective_date<=TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE))
        WHERE (v_hr_view=1 OR e.employee_id=v_employee) AND (p_employee IS NULL OR e.employee_id=p_employee)
        GROUP BY e.employee_id,e.employee_code,l.leave_type_id,l.leave_name ORDER BY e.employee_code,l.leave_name;
    ELSIF p_resource='shiftsScheduled' THEN
      PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');
      OPEN p_rows FOR SELECT s.employee_shift_id,s.employee_id,e.employee_code,e.full_name,TO_CHAR(s.work_date,'YYYY-MM-DD') work_date,s.shift_id,w.shift_name,
        TO_CHAR(s.starts_at,'YYYY-MM-DD"T"HH24:MI:SS') starts_at,TO_CHAR(s.ends_at,'YYYY-MM-DD"T"HH24:MI:SS') ends_at
        FROM EMPLOYEE_SHIFT s JOIN EMPLOYEE e ON e.employee_id=s.employee_id JOIN WORK_SHIFT w ON w.shift_id=s.shift_id
        WHERE (p_employee IS NULL OR s.employee_id=p_employee) AND (p_period IS NULL OR EXISTS(SELECT 1 FROM PAYROLL_PERIOD p WHERE p.period_id=p_period AND s.work_date>=p.period_start AND s.work_date<p.period_end))
        ORDER BY s.work_date DESC,e.employee_code FETCH FIRST 3000 ROWS ONLY;
    ELSIF p_resource='raw' THEN
      PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');
      OPEN p_rows FOR SELECT raw_id,import_id,source_device,source_event_key,employee_id,source_employee_code,
        TO_CHAR(event_at,'YYYY-MM-DD"T"HH24:MI:SS') event_at,event_type,validation_error FROM TIMEKEEPING_RAW ORDER BY raw_id DESC FETCH FIRST 3000 ROWS ONLY;
    ELSIF p_resource='contracts' THEN
      IF v_manager<>1 THEN RAISE_APPLICATION_ERROR(-20403,'Manager required'); END IF;
      OPEN p_rows FOR SELECT c.contract_id,c.employee_id,e.employee_code,e.full_name,c.contract_no,
        TO_CHAR(c.valid_from,'YYYY-MM-DD') valid_from,TO_CHAR(c.valid_to,'YYYY-MM-DD') valid_to,
        c.monthly_salary,c.insurance_base,c.insurance_enabled,c.calendar_id,w.calendar_name,c.status,c.created_by,c.approved_by
        FROM EMPLOYMENT_CONTRACT c JOIN EMPLOYEE e ON e.employee_id=c.employee_id JOIN WORK_CALENDAR w ON w.calendar_id=c.calendar_id
        WHERE p_employee IS NULL OR c.employee_id=p_employee ORDER BY c.valid_from DESC,c.contract_id DESC FETCH FIRST 3000 ROWS ONLY;
    ELSIF p_resource='profile' THEN
      PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); employee_exists(p_employee);
      OPEN p_rows FOR SELECT employee_id,employee_code,full_name,email,TO_CHAR(birth_date,'YYYY-MM-DD') birth_date,
        TO_CHAR(hire_date,'YYYY-MM-DD') hire_date,TO_CHAR(termination_date,'YYYY-MM-DD') termination_date,status,row_version
        FROM EMPLOYEE WHERE employee_id=p_employee;
    ELSE RAISE_APPLICATION_ERROR(-20400,'Unknown read resource'); END IF;
  END;
  PROCEDURE update_employee(p_actor NUMBER,p_employee NUMBER,p_name VARCHAR2,p_email VARCHAR2,p_birth DATE,p_status VARCHAR2,p_termination DATE,p_version NUMBER) IS v_e EMPLOYEE%ROWTYPE;
  BEGIN
    SAVEPOINT hr_update_employee;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs; employee_exists(p_employee);
    SELECT * INTO v_e FROM EMPLOYEE WHERE employee_id=p_employee FOR UPDATE NOWAIT;
    IF p_version IS NULL OR v_e.row_version<>p_version THEN RAISE_APPLICATION_ERROR(-20409,'Employee changed, reload before editing'); END IF;
    IF TRIM(p_name) IS NULL OR LENGTH(TRIM(p_name))>150 OR LENGTH(p_email)>200 OR p_status IS NULL OR p_status NOT IN ('ACTIVE','INACTIVE','TERMINATED')
      OR (p_birth IS NOT NULL AND (p_birth<>TRUNC(p_birth) OR p_birth>=v_e.hire_date))
      OR (p_termination IS NOT NULL AND (p_termination<>TRUNC(p_termination) OR p_termination<v_e.hire_date))
      OR (p_status='TERMINATED' AND p_termination IS NULL) OR (p_status<>'TERMINATED' AND p_termination IS NOT NULL)
      THEN RAISE_APPLICATION_ERROR(-20400,'Invalid employee profile or dates'); END IF;
    IF NVL(v_e.termination_date,DATE '9999-12-31')<>NVL(p_termination,DATE '9999-12-31') THEN
      UPDATE EMPLOYEE SET full_name=TRIM(p_name),email=LOWER(TRIM(p_email)),birth_date=p_birth,status=p_status,
        termination_date=p_termination,row_version=row_version+1 WHERE employee_id=p_employee;
    ELSE
      UPDATE EMPLOYEE SET full_name=TRIM(p_name),email=LOWER(TRIM(p_email)),birth_date=p_birth,status=p_status,
        row_version=row_version+1 WHERE employee_id=p_employee;
    END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE',p_employee,'UPDATE_PROFILE');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_update_employee; RAISE;
  END;
  PROCEDURE save_organization_catalog(p_actor NUMBER,p_kind VARCHAR2,p_existing NUMBER,p_code VARCHAR2,p_name VARCHAR2,p_active VARCHAR2,p_id OUT NUMBER) IS
    v_entity VARCHAR2(30);
  BEGIN
    SAVEPOINT hr_organization_catalog;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_code) IS NULL OR LENGTH(TRIM(p_code))>30 OR TRIM(p_name) IS NULL OR LENGTH(TRIM(p_name))>150
       OR p_active IS NULL OR p_active NOT IN ('Y','N') THEN
      RAISE_APPLICATION_ERROR(-20400,'Invalid organization catalog data');
    END IF;
    IF p_existing IS NOT NULL THEN positive(p_existing); END IF;
    IF p_kind='departments' THEN
      v_entity:='DEPARTMENT';
      IF p_existing IS NULL THEN
        INSERT INTO DEPARTMENT(department_code,department_name,is_active) VALUES(TRIM(p_code),TRIM(p_name),p_active)
          RETURNING department_id INTO p_id;
      ELSE
        UPDATE DEPARTMENT SET department_code=TRIM(p_code),department_name=TRIM(p_name),is_active=p_active WHERE department_id=p_existing;
      END IF;
    ELSIF p_kind='positions' THEN
      v_entity:='JOB_POSITION';
      IF p_existing IS NULL THEN
        INSERT INTO JOB_POSITION(position_code,position_name,is_active) VALUES(TRIM(p_code),TRIM(p_name),p_active)
          RETURNING position_id INTO p_id;
      ELSE
        UPDATE JOB_POSITION SET position_code=TRIM(p_code),position_name=TRIM(p_name),is_active=p_active WHERE position_id=p_existing;
      END IF;
    ELSE
      RAISE_APPLICATION_ERROR(-20400,'Unknown organization catalog');
    END IF;
    IF p_existing IS NOT NULL THEN
      IF SQL%ROWCOUNT=0 THEN RAISE_APPLICATION_ERROR(-20404,'Catalog entry not found'); END IF;
      p_id:=p_existing;
    END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,v_entity,p_id,CASE WHEN p_existing IS NULL THEN 'CREATE' ELSE 'UPDATE' END);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_organization_catalog; RAISE;
  END;
  PROCEDURE transfer_employee(p_actor NUMBER,p_employee NUMBER,p_department NUMBER,p_position NUMBER,p_from DATE,p_reason VARCHAR2,p_id OUT NUMBER) IS
    v_e EMPLOYEE%ROWTYPE;v_old NUMBER;v_from DATE;v_n NUMBER;
  BEGIN
    SAVEPOINT hr_transfer;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs; employee_exists(p_employee); reason_required(p_reason);
    positive(p_department);positive(p_position);
    SELECT * INTO v_e FROM EMPLOYEE WHERE employee_id=p_employee FOR UPDATE NOWAIT;
    IF v_e.status<>'ACTIVE' OR v_e.termination_date IS NOT NULL OR p_from IS NULL OR p_from<>TRUNC(p_from) OR p_from<v_e.hire_date
      THEN RAISE_APPLICATION_ERROR(-20400,'Invalid transfer date or inactive employee'); END IF;
    BEGIN SELECT assignment_id,valid_from INTO v_old,v_from FROM EMPLOYEE_ASSIGNMENT WHERE employee_id=p_employee AND valid_to IS NULL FOR UPDATE NOWAIT;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20409,'Initial assignment is required before transfer'); END;
    IF p_from<=v_from THEN RAISE_APPLICATION_ERROR(-20409,'Transfer must follow previous assignment start'); END IF;
    SELECT COUNT(*) INTO v_n FROM DEPARTMENT WHERE department_id=p_department AND is_active='Y';
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Inactive department'); END IF;
    SELECT COUNT(*) INTO v_n FROM JOB_POSITION WHERE position_id=p_position AND is_active='Y';
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Inactive position'); END IF;
    UPDATE EMPLOYEE_ASSIGNMENT SET valid_to=p_from WHERE assignment_id=v_old;
    INSERT INTO EMPLOYEE_ASSIGNMENT(employee_id,department_id,position_id,valid_from,created_by)
      VALUES(p_employee,p_department,p_position,p_from,p_actor) RETURNING assignment_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE_ASSIGNMENT',p_id,'TRANSFER',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_transfer; RAISE;
  END;
  PROCEDURE create_contract(p_actor NUMBER,p_employee NUMBER,p_no VARCHAR2,p_from DATE,p_to DATE,p_salary NUMBER,p_insurance NUMBER,p_enabled VARCHAR2,p_calendar NUMBER,p_id OUT NUMBER) IS v_e EMPLOYEE%ROWTYPE;v_n NUMBER;
  BEGIN
    SAVEPOINT hr_contract;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs; employee_exists(p_employee);positive(p_calendar);
    SELECT * INTO v_e FROM EMPLOYEE WHERE employee_id=p_employee FOR UPDATE NOWAIT;
    IF TRIM(p_no) IS NULL OR LENGTH(p_no)>60 OR p_from IS NULL OR p_from<>TRUNC(p_from) OR p_from<v_e.hire_date
      OR (p_to IS NOT NULL AND (p_to<>TRUNC(p_to) OR p_to<=p_from)) OR p_salary IS NULL OR p_salary<=0
      OR p_insurance IS NULL OR p_insurance<0 OR p_enabled IS NULL OR p_enabled NOT IN ('Y','N')
      OR (v_e.termination_date IS NOT NULL AND (p_from>v_e.termination_date OR p_to IS NULL OR p_to>v_e.termination_date+1))
      THEN RAISE_APPLICATION_ERROR(-20400,'Invalid contract inputs'); END IF;
    SELECT COUNT(*) INTO v_n FROM WORK_CALENDAR WHERE calendar_id=p_calendar;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Calendar not found'); END IF;
    INSERT INTO EMPLOYMENT_CONTRACT(employee_id,contract_no,valid_from,valid_to,monthly_salary,insurance_base,insurance_enabled,calendar_id,status,created_by)
      VALUES(p_employee,TRIM(p_no),p_from,p_to,p_salary,p_insurance,p_enabled,p_calendar,'PENDING',p_actor) RETURNING contract_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYMENT_CONTRACT',p_id,'CREATE_PENDING');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_contract; RAISE;
  END;
  PROCEDURE decide_contract(p_actor NUMBER,p_contract NUMBER,p_decision VARCHAR2,p_reason VARCHAR2) IS v_c EMPLOYMENT_CONTRACT%ROWTYPE;
  BEGIN
    SAVEPOINT hr_decide_contract;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'DIRECTOR'); PKG_PAYROLL_INTERNAL.lock_inputs;positive(p_contract);
    SELECT * INTO v_c FROM EMPLOYMENT_CONTRACT WHERE contract_id=p_contract FOR UPDATE NOWAIT;
    IF v_c.status<>'PENDING' OR v_c.created_by=p_actor OR p_decision IS NULL OR p_decision NOT IN ('APPROVE','REJECT')
      THEN RAISE_APPLICATION_ERROR(-20409,'Pending contract and different approver required'); END IF;
    IF p_decision='REJECT' THEN
      reason_required(p_reason); UPDATE EMPLOYMENT_CONTRACT SET status='REJECTED' WHERE contract_id=p_contract;
    ELSE
      FOR c IN (SELECT contract_id,valid_from FROM EMPLOYMENT_CONTRACT WHERE employee_id=v_c.employee_id AND status='APPROVED'
        AND valid_from<v_c.valid_from AND (valid_to IS NULL OR valid_to>v_c.valid_from) FOR UPDATE NOWAIT) LOOP
        UPDATE EMPLOYMENT_CONTRACT SET valid_to=v_c.valid_from WHERE contract_id=c.contract_id;
      END LOOP;
      UPDATE EMPLOYMENT_CONTRACT SET status='APPROVED',approved_by=p_actor,approved_at=SYSTIMESTAMP WHERE contract_id=p_contract;
    END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYMENT_CONTRACT',p_contract,p_decision,p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_decide_contract; RAISE;
  END;
  PROCEDURE prepare_calendar(p_actor NUMBER,p_calendar NUMBER,p_month DATE) IS v_date DATE;v_end DATE;v_n NUMBER;
  BEGIN
    SAVEPOINT hr_calendar;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs;positive(p_calendar);
    IF p_month IS NULL THEN RAISE_APPLICATION_ERROR(-20400,'Calendar month required'); END IF;
    SELECT COUNT(*) INTO v_n FROM WORK_CALENDAR WHERE calendar_id=p_calendar;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Calendar not found'); END IF;
    v_date:=TRUNC(p_month,'MM');v_end:=ADD_MONTHS(v_date,1);
    WHILE v_date<v_end LOOP
      MERGE INTO CALENDAR_DAY d USING (SELECT p_calendar c,v_date w FROM dual) s ON (d.calendar_id=s.c AND d.work_date=s.w)
      WHEN NOT MATCHED THEN INSERT(calendar_id,work_date,day_type,standard_minutes)
        VALUES(p_calendar,v_date,CASE WHEN v_date-TRUNC(v_date,'IW')<5 THEN 'WORKDAY' ELSE 'RESTDAY' END,
          CASE WHEN v_date-TRUNC(v_date,'IW')<5 THEN 480 ELSE 0 END);
      v_date:=v_date+1;
    END LOOP;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'WORK_CALENDAR',p_calendar,'PREPARE_MONTH',TO_CHAR(p_month,'YYYY-MM'));
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_calendar; RAISE;
  END;
  PROCEDURE read_calendar(p_actor NUMBER,p_calendar NUMBER,p_month DATE,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');positive(p_calendar);
    IF p_month IS NULL THEN RAISE_APPLICATION_ERROR(-20400,'Calendar month required'); END IF;
    OPEN p_rows FOR SELECT calendar_id,TO_CHAR(work_date,'YYYY-MM-DD') work_date,day_type,standard_minutes FROM CALENDAR_DAY
      WHERE calendar_id=p_calendar AND work_date>=TRUNC(p_month,'MM') AND work_date<ADD_MONTHS(TRUNC(p_month,'MM'),1) ORDER BY work_date;
  END;
  PROCEDURE save_calendar_day(p_actor NUMBER,p_calendar NUMBER,p_date DATE,p_type VARCHAR2,p_minutes NUMBER) IS v_n NUMBER;
  BEGIN
    SAVEPOINT hr_calendar_day;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;positive(p_calendar);
    IF p_date IS NULL OR p_date<>TRUNC(p_date) OR p_type IS NULL OR p_type NOT IN ('WORKDAY','RESTDAY','HOLIDAY')
      OR p_minutes IS NULL OR p_minutes<>TRUNC(p_minutes) OR p_minutes<0 OR p_minutes>1440
      OR (p_type='RESTDAY' AND p_minutes<>0) THEN RAISE_APPLICATION_ERROR(-20400,'Invalid work calendar day'); END IF;
    SELECT COUNT(*) INTO v_n FROM WORK_CALENDAR WHERE calendar_id=p_calendar;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Calendar not found'); END IF;
    MERGE INTO CALENDAR_DAY d USING (SELECT p_calendar c,p_date w FROM dual) s ON (d.calendar_id=s.c AND d.work_date=s.w)
    WHEN MATCHED THEN UPDATE SET day_type=p_type,standard_minutes=p_minutes
    WHEN NOT MATCHED THEN INSERT(calendar_id,work_date,day_type,standard_minutes) VALUES(p_calendar,p_date,p_type,p_minutes);
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'WORK_CALENDAR',p_calendar,'EDIT_DAY',TO_CHAR(p_date,'YYYY-MM-DD')||' '||p_type);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_calendar_day; RAISE;
  END;
  PROCEDURE create_leave(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_from DATE,p_to DATE,p_minutes NUMBER,p_reason VARCHAR2,p_id OUT NUMBER) IS
    v_date DATE;v_std NUMBER;v_total NUMBER:=0;v_n NUMBER;
  BEGIN
    SAVEPOINT hr_leave;
    own_or_hr(p_actor,p_employee);PKG_PAYROLL_INTERNAL.lock_inputs;reason_required(p_reason);positive(p_type);
    IF p_from IS NULL OR p_to IS NULL OR p_from<>TRUNC(p_from) OR p_to<>TRUNC(p_to) OR p_to<=p_from OR p_to-p_from>366
      OR p_minutes IS NULL OR p_minutes<=0 OR p_minutes>1440 OR p_minutes<>TRUNC(p_minutes)
      THEN RAISE_APPLICATION_ERROR(-20400,'Invalid leave interval or minutes'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee AND hire_date<=p_from AND (termination_date IS NULL OR termination_date>=p_to-1);
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Leave outside employment'); END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_TYPE WHERE leave_type_id=p_type;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Leave type not found'); END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_REQUEST
      WHERE employee_id=p_employee AND status IN ('PENDING','APPROVED')
        AND starts_at<CAST(p_to AS TIMESTAMP) AND ends_at>CAST(p_from AS TIMESTAMP);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20410,'Overlapping pending or approved leave request'); END IF;
    INSERT INTO LEAVE_REQUEST(employee_id,leave_type_id,starts_at,ends_at,reason,requested_by)
      VALUES(p_employee,p_type,CAST(p_from AS TIMESTAMP),CAST(p_to AS TIMESTAMP),p_reason,p_actor) RETURNING leave_id INTO p_id;
    v_date:=p_from;
    WHILE v_date<p_to LOOP
      BEGIN
        SELECT cd.standard_minutes INTO v_std FROM EMPLOYMENT_CONTRACT c JOIN CALENDAR_DAY cd ON cd.calendar_id=c.calendar_id AND cd.work_date=v_date
          WHERE c.employee_id=p_employee AND c.status='APPROVED' AND c.valid_from<=v_date AND (c.valid_to IS NULL OR c.valid_to>v_date);
      EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20409,'Approved contract and complete calendar required'); END;
      IF v_std>0 THEN
        INSERT INTO LEAVE_DAY(leave_id,work_date,minutes) VALUES(p_id,v_date,LEAST(v_std,p_minutes));
        v_total:=v_total+LEAST(v_std,p_minutes);
      END IF;
      v_date:=v_date+1;
    END LOOP;
    IF v_total=0 THEN RAISE_APPLICATION_ERROR(-20400,'Leave interval has no working days'); END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'LEAVE_REQUEST',p_id,'CREATE',p_reason);
    notify_hr(p_actor,'Đơn nghỉ phép mới','Mở mục Yêu cầu để xem đơn nghỉ phép đang chờ xử lý.','LEAVE_REQUEST',p_id);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_leave; RAISE;
  END;
  PROCEDURE create_overtime(p_actor NUMBER,p_employee NUMBER,p_from TIMESTAMP,p_to TIMESTAMP,p_reason VARCHAR2,p_id OUT NUMBER) IS v_n NUMBER;
  BEGIN
    SAVEPOINT hr_overtime;
    own_or_hr(p_actor,p_employee);PKG_PAYROLL_INTERNAL.lock_inputs;reason_required(p_reason);
    IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR CAST(p_to AS DATE)-CAST(p_from AS DATE)>1
      THEN RAISE_APPLICATION_ERROR(-20400,'Overtime interval must be positive and at most 24 hours'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee AND hire_date<=TRUNC(CAST(p_from AS DATE))
      AND (termination_date IS NULL OR termination_date>=TRUNC(CAST(p_to AS DATE)));
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Overtime outside employment'); END IF;
    INSERT INTO OVERTIME_REQUEST(employee_id,starts_at,ends_at,reason,requested_by)
      VALUES(p_employee,p_from,p_to,p_reason,p_actor) RETURNING overtime_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'OVERTIME_REQUEST',p_id,'CREATE',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_overtime; RAISE;
  END;
  PROCEDURE reject_overtime(p_actor NUMBER,p_ot NUMBER,p_reason VARCHAR2) IS v_o OVERTIME_REQUEST%ROWTYPE;
  BEGIN
    SAVEPOINT hr_reject_ot;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;reason_required(p_reason);positive(p_ot);
    SELECT * INTO v_o FROM OVERTIME_REQUEST WHERE overtime_id=p_ot FOR UPDATE NOWAIT;
    IF v_o.status<>'PENDING' OR v_o.requested_by=p_actor THEN RAISE_APPLICATION_ERROR(-20409,'Pending request and different approver required'); END IF;
    UPDATE OVERTIME_REQUEST SET status='REJECTED' WHERE overtime_id=p_ot;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'OVERTIME_REQUEST',p_ot,'REJECT',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_reject_ot; RAISE;
  END;
  PROCEDURE create_correction(p_actor NUMBER,p_period NUMBER,p_employee NUMBER,p_source VARCHAR2,p_source_id NUMBER,p_reason VARCHAR2,p_id OUT NUMBER) IS v_n NUMBER;
  BEGIN
    SAVEPOINT hr_correction;
    IF GREATEST(has_role(p_actor,'HR'),has_role(p_actor,'PAYROLL'))=0 THEN own_or_hr(p_actor,p_employee);
    ELSIF p_employee IS NOT NULL THEN employee_exists(p_employee); END IF;
    PKG_PAYROLL_INTERNAL.lock_inputs;reason_required(p_reason);positive(p_period);
    IF p_source IS NULL OR p_source NOT IN ('TIMESHEET','CONTRACT','OTHER') THEN RAISE_APPLICATION_ERROR(-20400,'Invalid correction source'); END IF;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_PERIOD WHERE period_id=p_period;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Period not found'); END IF;
    IF p_source_id IS NOT NULL THEN
      positive(p_source_id);
      IF p_source='TIMESHEET' THEN SELECT COUNT(*) INTO v_n FROM TIMESHEET_DAILY WHERE timesheet_id=p_source_id AND period_id=p_period AND (p_employee IS NULL OR employee_id=p_employee);
      ELSIF p_source='CONTRACT' THEN SELECT COUNT(*) INTO v_n FROM EMPLOYMENT_CONTRACT WHERE contract_id=p_source_id AND (p_employee IS NULL OR employee_id=p_employee);
      ELSE v_n:=0; END IF;
      IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20404,'Correction source not found'); END IF;
    END IF;
    INSERT INTO INPUT_CHANGE_REQUEST(period_id,employee_id,source_type,source_id,reason,requested_by)
      VALUES(p_period,p_employee,p_source,p_source_id,p_reason,p_actor) RETURNING change_request_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'INPUT_CHANGE_REQUEST',p_id,'CREATE',p_reason);
    notify_hr(p_actor,'Yêu cầu điều chỉnh mới','Mở mục Yêu cầu để xem dữ liệu đầu vào cần điều chỉnh.','INPUT_CHANGE_REQUEST',p_id);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_correction; RAISE;
  END;
  PROCEDURE resolve_correction(p_actor NUMBER,p_request NUMBER,p_reason VARCHAR2) IS v_status VARCHAR2(20);
  BEGIN
    SAVEPOINT hr_resolve;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;reason_required(p_reason);positive(p_request);
    SELECT status INTO v_status FROM INPUT_CHANGE_REQUEST WHERE change_request_id=p_request FOR UPDATE NOWAIT;
    IF v_status NOT IN ('PENDING','ACCEPTED') THEN RAISE_APPLICATION_ERROR(-20409,'Correction already processed'); END IF;
    UPDATE INPUT_CHANGE_REQUEST SET status='RESOLVED',resolved_by=p_actor WHERE change_request_id=p_request;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'INPUT_CHANGE_REQUEST',p_request,'RESOLVE',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_resolve; RAISE;
  END;
  PROCEDURE grant_leave(p_actor NUMBER,p_employee NUMBER,p_type NUMBER,p_date DATE,p_minutes NUMBER,p_reason VARCHAR2,p_key VARCHAR2,p_id OUT NUMBER) IS v_n NUMBER;
  BEGIN
    SAVEPOINT hr_leave_grant;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;employee_exists(p_employee);reason_required(p_reason);positive(p_type);
    IF p_date IS NULL OR p_date<>TRUNC(p_date) OR p_minutes IS NULL OR p_minutes<=0 OR p_minutes<>TRUNC(p_minutes) OR p_minutes>525600
      OR TRIM(p_key) IS NULL OR LENGTH(p_key)>70 THEN RAISE_APPLICATION_ERROR(-20400,'Invalid leave credit'); END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_TYPE WHERE leave_type_id=p_type AND uses_balance='Y';
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Leave type does not use balance'); END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_LEDGER WHERE source_key='WEB-'||p_key;
    IF v_n>0 THEN
      SELECT ledger_id INTO p_id FROM LEAVE_LEDGER WHERE source_key='WEB-'||p_key AND employee_id=p_employee AND leave_type_id=p_type
        AND effective_date=p_date AND delta_minutes=p_minutes AND created_by=p_actor;
      RETURN;
    END IF;
    INSERT INTO LEAVE_LEDGER(employee_id,leave_type_id,effective_date,delta_minutes,source_key,created_by)
      VALUES(p_employee,p_type,p_date,p_minutes,'WEB-'||p_key,p_actor) RETURNING ledger_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'LEAVE_LEDGER',p_id,'GRANT',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_leave_grant; RAISE;
  END;
  PROCEDURE save_shift(p_actor NUMBER,p_employee NUMBER,p_date DATE,p_shift NUMBER,p_id OUT NUMBER) IS v_s WORK_SHIFT%ROWTYPE;v_start TIMESTAMP;v_end TIMESTAMP;v_n NUMBER;
  BEGIN
    SAVEPOINT hr_shift;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;employee_exists(p_employee);positive(p_shift);
    IF p_date IS NULL OR p_date<>TRUNC(p_date) THEN RAISE_APPLICATION_ERROR(-20400,'Whole work date required'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee AND hire_date<=p_date AND (termination_date IS NULL OR termination_date>=p_date);
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20400,'Shift outside employment'); END IF;
    SELECT * INTO v_s FROM WORK_SHIFT WHERE shift_id=p_shift;
    v_start:=CAST(p_date+v_s.start_minute/1440 AS TIMESTAMP);
    v_end:=CAST(p_date+v_s.end_day_offset+v_s.end_minute/1440 AS TIMESTAMP);
    IF v_end<=v_start THEN RAISE_APPLICATION_ERROR(-20400,'Invalid shift interval'); END IF;
    MERGE INTO EMPLOYEE_SHIFT s USING (SELECT p_employee e,p_date d FROM dual) q ON (s.employee_id=q.e AND s.work_date=q.d)
    WHEN MATCHED THEN UPDATE SET shift_id=p_shift,starts_at=v_start,ends_at=v_end
    WHEN NOT MATCHED THEN INSERT(employee_id,work_date,shift_id,starts_at,ends_at,created_by) VALUES(p_employee,p_date,p_shift,v_start,v_end,p_actor);
    SELECT employee_shift_id INTO p_id FROM EMPLOYEE_SHIFT WHERE employee_id=p_employee AND work_date=p_date;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE_SHIFT',p_id,'ASSIGN_SHIFT');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_shift; RAISE;
  END;
  PROCEDURE start_import(p_actor NUMBER,p_hash VARCHAR2,p_storage_key VARCHAR2,p_name VARCHAR2,p_size NUMBER,p_id OUT NUMBER,p_existing OUT NUMBER) IS v_document NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF p_hash IS NULL OR LENGTH(p_hash)<>64 OR p_storage_key IS NULL OR p_storage_key<>'attendance/'||p_hash||'.csv'
      OR TRIM(p_name) IS NULL OR LENGTH(p_name)>255 OR p_size IS NULL OR p_size<=0 OR p_size>2097152
      THEN RAISE_APPLICATION_ERROR(-20400,'Invalid attendance file metadata'); END IF;
    BEGIN SELECT import_id INTO p_id FROM ATTENDANCE_IMPORT WHERE file_sha256=p_hash;p_existing:=1;RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
    PKG_REQUESTS.register_document(p_actor,p_storage_key,p_name,'text/csv',p_size,p_hash,v_document);
    INSERT INTO ATTENDANCE_IMPORT(file_sha256,document_id,imported_by,status) VALUES(p_hash,v_document,p_actor,'VALIDATING') RETURNING import_id INTO p_id;
    p_existing:=0;
  END;
  PROCEDURE append_raw(p_actor NUMBER,p_import NUMBER,p_employee_code VARCHAR2,p_event TIMESTAMP,p_type VARCHAR2,p_device VARCHAR2,p_key VARCHAR2,p_inserted OUT NUMBER) IS
    v_n NUMBER;v_employee NUMBER;v_error VARCHAR2(500);v_raw TIMEKEEPING_RAW%ROWTYPE;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_employee_code) IS NULL OR LENGTH(p_employee_code)>50 OR p_event IS NULL OR p_type IS NULL OR p_type NOT IN ('IN','OUT','UNKNOWN')
      OR TRIM(p_device) IS NULL OR LENGTH(p_device)>80 OR TRIM(p_key) IS NULL OR LENGTH(p_key)>100 THEN RAISE_APPLICATION_ERROR(-20400,'Invalid raw attendance row'); END IF;
    SELECT COUNT(*) INTO v_n FROM ATTENDANCE_IMPORT WHERE import_id=p_import AND imported_by=p_actor AND status='VALIDATING';
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20409,'Import is not open'); END IF;
    BEGIN
      SELECT * INTO v_raw FROM TIMEKEEPING_RAW WHERE source_device=p_device AND source_event_key=p_key;
      IF v_raw.source_employee_code<>p_employee_code OR v_raw.event_at<>p_event OR v_raw.event_type<>p_type THEN RAISE_APPLICATION_ERROR(-20409,'Attendance event key reused with different content'); END IF;
      p_inserted:=0;RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
    BEGIN SELECT employee_id INTO v_employee FROM EMPLOYEE WHERE employee_code=p_employee_code;
    EXCEPTION WHEN NO_DATA_FOUND THEN v_employee:=NULL;v_error:='Employee code not found'; END;
    IF p_type='UNKNOWN' THEN v_error:=CASE WHEN v_error IS NULL THEN 'Unknown event type' ELSE v_error||'; Unknown event type' END; END IF;
    INSERT INTO TIMEKEEPING_RAW(import_id,source_device,source_event_key,employee_id,source_employee_code,event_at,event_type,validation_error)
      VALUES(p_import,p_device,p_key,v_employee,p_employee_code,p_event,p_type,v_error);
    p_inserted:=1;
  END;
  PROCEDURE finish_import(p_actor NUMBER,p_import NUMBER,p_errors OUT NUMBER) IS
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    UPDATE ATTENDANCE_IMPORT SET status='IMPORTED' WHERE import_id=p_import AND imported_by=p_actor AND status='VALIDATING';
    IF SQL%ROWCOUNT<>1 THEN RAISE_APPLICATION_ERROR(-20409,'Import is not open'); END IF;
    SELECT COUNT(*) INTO p_errors FROM TIMEKEEPING_RAW WHERE import_id=p_import AND validation_error IS NOT NULL;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'ATTENDANCE_IMPORT',p_import,'IMPORT_RAW');
  END;
END PKG_HR_PORTAL;
/
GRANT EXECUTE ON PKG_HR_PORTAL TO PAYROLL_API;
