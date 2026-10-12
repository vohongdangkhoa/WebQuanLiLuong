CREATE OR REPLACE PACKAGE PKG_HR_CORE AUTHID DEFINER AS
  PROCEDURE save_day(p_actor NUMBER,p_period NUMBER,p_employee NUMBER,p_date DATE,p_worked NUMBER,p_leave NUMBER,p_holiday NUMBER);
  PROCEDURE lock_timesheet(p_actor NUMBER,p_period NUMBER);
  PROCEDURE reopen_timesheet(p_actor NUMBER,p_period NUMBER,p_reason VARCHAR2);
END;
/
CREATE OR REPLACE PACKAGE BODY PKG_HR_CORE AS
  PROCEDURE save_day(p_actor NUMBER,p_period NUMBER,p_employee NUMBER,p_date DATE,p_worked NUMBER,p_leave NUMBER,p_holiday NUMBER) IS
    v_period PAYROLL_PERIOD%ROWTYPE; v_cal NUMBER; v_std NUMBER; v_n NUMBER; v_id NUMBER;
  BEGIN
    SAVEPOINT hr_day;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_period FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    IF v_period.timesheet_status='LOCKED' OR v_period.period_status='CLOSED' THEN RAISE_APPLICATION_ERROR(-20010,'Timesheet locked'); END IF;
    IF p_date IS NULL OR p_date<>TRUNC(p_date) OR p_date<v_period.period_start OR p_date>=v_period.period_end THEN RAISE_APPLICATION_ERROR(-20011,'Date outside period'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=p_employee AND hire_date<=p_date AND (termination_date IS NULL OR termination_date>=p_date);
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20012,'Employee not employed on this day'); END IF;
    SELECT calendar_id INTO v_cal FROM EMPLOYMENT_CONTRACT WHERE employee_id=p_employee AND status='APPROVED' AND valid_from<=p_date AND (valid_to IS NULL OR valid_to>p_date);
    SELECT standard_minutes INTO v_std FROM CALENDAR_DAY WHERE calendar_id=v_cal AND work_date=p_date;
    IF p_worked IS NULL OR p_leave IS NULL OR p_holiday IS NULL OR p_worked<0 OR p_leave<0 OR p_holiday<0 OR p_worked+p_leave+p_holiday>v_std THEN
      RAISE_APPLICATION_ERROR(-20013,'Paid minutes exceed daily calendar or invalid minutes');
    END IF;
    -- HR certifies leave/holiday reconciliation before this procedure. Importing punches alone is insufficient.
    MERGE INTO TIMESHEET_DAILY d USING (SELECT p_employee e,p_date w FROM dual) s ON (d.employee_id=s.e AND d.work_date=s.w)
    WHEN MATCHED THEN UPDATE SET d.worked_minutes=p_worked,d.paid_leave_minutes=p_leave,d.paid_holiday_minutes=p_holiday,
      d.paid_minutes=p_worked+p_leave+p_holiday,d.status='VALID',d.error_message=NULL,d.row_version=d.row_version+1
    WHEN NOT MATCHED THEN INSERT (period_id,employee_id,work_date,worked_minutes,paid_leave_minutes,paid_holiday_minutes,paid_minutes,status)
      VALUES(p_period,p_employee,p_date,p_worked,p_leave,p_holiday,p_worked+p_leave+p_holiday,'VALID');
    SELECT timesheet_id INTO v_id FROM TIMESHEET_DAILY WHERE employee_id=p_employee AND work_date=p_date;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'TIMESHEET_DAILY',v_id,'SAVE_DAY','HR certified daily minutes');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_day; RAISE;
  END;
  PROCEDURE lock_timesheet(p_actor NUMBER,p_period NUMBER) IS v_p PAYROLL_PERIOD%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT hr_lock;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    IF v_p.period_status<>'OPEN' OR v_p.timesheet_status='LOCKED' THEN RAISE_APPLICATION_ERROR(-20014,'Period not open for locking'); END IF;
    IF TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE))<v_p.period_end THEN RAISE_APPLICATION_ERROR(-20015,'Month not finished'); END IF;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE period_id=p_period AND status IN ('CALCULATING','PENDING_APPROVAL','APPROVED');
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20016,'Run prevents locking'); END IF;
    SELECT COUNT(*) INTO v_n FROM TIMESHEET_DAILY WHERE period_id=p_period AND status='ERROR';
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20017,'Unresolved timesheet errors'); END IF;
    SELECT COUNT(*) INTO v_n FROM LEAVE_REQUEST WHERE status='PENDING' AND starts_at<CAST(v_p.period_end AS TIMESTAMP) AND ends_at>CAST(v_p.period_start AS TIMESTAMP);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20018,'Pending leave requests'); END IF;
    SELECT COUNT(*) INTO v_n FROM OVERTIME_REQUEST WHERE status IN ('PENDING','APPROVED') AND starts_at<CAST(v_p.period_end AS TIMESTAMP) AND ends_at>CAST(v_p.period_start AS TIMESTAMP);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20019,'Pending or unconfirmed overtime'); END IF;
    SELECT COUNT(*) INTO v_n FROM BONUS_DEDUCTION WHERE period_id=p_period AND status='PENDING';
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20020,'Unapproved earning/deduction input'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYMENT_CONTRACT WHERE status='PENDING' AND valid_from<v_p.period_end AND (valid_to IS NULL OR valid_to>v_p.period_start);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20020,'Unapproved effective contracts'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE_ALLOWANCE WHERE status='PENDING' AND valid_from<v_p.period_end AND (valid_to IS NULL OR valid_to>v_p.period_start);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20020,'Unapproved effective allowances'); END IF;
    SELECT COUNT(*) INTO v_n FROM DEPENDENT_CLAIM WHERE status='PENDING' AND valid_from<v_p.period_end AND (valid_to IS NULL OR valid_to>v_p.period_start);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20020,'Unverified dependent claims'); END IF;
    -- Require a daily certificate for EVERY employed calendar day, even rest days with zero minutes.
    FOR e IN (SELECT employee_id,hire_date,termination_date FROM EMPLOYEE WHERE hire_date<v_p.period_end AND (termination_date IS NULL OR termination_date>=v_p.period_start)) LOOP
      SELECT COUNT(*) INTO v_n FROM TIMESHEET_DAILY WHERE period_id=p_period AND employee_id=e.employee_id AND status='VALID'
        AND work_date>=GREATEST(e.hire_date,v_p.period_start) AND work_date<LEAST(NVL(e.termination_date+1,v_p.period_end),v_p.period_end);
      IF v_n<>LEAST(NVL(e.termination_date+1,v_p.period_end),v_p.period_end)-GREATEST(e.hire_date,v_p.period_start) THEN
        RAISE_APPLICATION_ERROR(-20021,'Missing daily timesheet for employee '||e.employee_id);
      END IF;
    END LOOP;
    UPDATE PAYROLL_PERIOD SET timesheet_status='LOCKED',locked_by=p_actor,locked_at=SYSTIMESTAMP WHERE period_id=p_period;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_PERIOD',p_period,'LOCK_TIMESHEET');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_lock; RAISE;
  END;
  PROCEDURE reopen_timesheet(p_actor NUMBER,p_period NUMBER,p_reason VARCHAR2) IS v_p PAYROLL_PERIOD%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT hr_reopen;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR'); PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_reason) IS NULL THEN RAISE_APPLICATION_ERROR(-20022,'Reason required'); END IF;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE period_id=p_period AND status IN ('CALCULATING','PENDING_APPROVAL','APPROVED');
    IF v_p.period_status='CLOSED' OR v_n>0 OR v_p.timesheet_status<>'LOCKED' THEN RAISE_APPLICATION_ERROR(-20023,'Cannot reopen this period'); END IF;
    UPDATE PAYROLL_PERIOD SET timesheet_status='REOPENED',input_version=input_version+1,locked_by=NULL,locked_at=NULL WHERE period_id=p_period;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_PERIOD',p_period,'REOPEN_TIMESHEET',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO hr_reopen; RAISE;
  END;
END;
//////tới đây 

CREATE OR REPLACE PACKAGE PKG_PAYROLL_CORE AUTHID DEFINER AS
  PROCEDURE calculate(p_actor NUMBER,p_period NUMBER,p_request_key VARCHAR2,p_run OUT NUMBER);
  PROCEDURE submit_run(p_actor NUMBER,p_run NUMBER);
  PROCEDURE decide_run(p_actor NUMBER,p_run NUMBER,p_decision VARCHAR2,p_reason VARCHAR2 DEFAULT NULL);
END;
/
CREATE OR REPLACE PACKAGE BODY PKG_PAYROLL_CORE AS
  PROCEDURE add_item(p_result NUMBER,p_code VARCHAR2,p_department NUMBER,p_source VARCHAR2,p_source_id NUMBER,p_date DATE,
    p_amount NUMBER,p_taxable NUMBER,p_quantity NUMBER,p_rate NUMBER,p_multiplier NUMBER,p_formula VARCHAR2,p_policy NUMBER,p_account NUMBER DEFAULT NULL) IS
    v_c PAY_COMPONENT%ROWTYPE;v_department_name DEPARTMENT.department_name%TYPE;
  BEGIN
    SELECT * INTO v_c FROM PAY_COMPONENT WHERE component_code=p_code;
    SELECT department_name INTO v_department_name FROM DEPARTMENT WHERE department_id=p_department;
    INSERT INTO PAYROLL_ITEM(result_id,component_id,component_code_snapshot,kind_snapshot,department_id,source_type,source_id,source_date,
      amount,taxable_amount,quantity,unit_rate,multiplier,formula_snapshot,policy_id,deduction_account_id,department_name_snapshot)
    VALUES(p_result,v_c.component_id,v_c.component_code,v_c.component_kind,p_department,p_source,p_source_id,p_date,
      p_amount,p_taxable,p_quantity,p_rate,p_multiplier,p_formula,p_policy,p_account,v_department_name);
  END;
  PROCEDURE snap(p_result NUMBER,p_type VARCHAR2,p_source NUMBER,p_json CLOB) IS
  BEGIN
    MERGE INTO PAYROLL_SNAPSHOT d USING (SELECT p_result r,p_type t,p_source s FROM dual) q ON (d.result_id=q.r AND d.source_type=q.t AND d.source_id=q.s)
    WHEN NOT MATCHED THEN INSERT(result_id,source_type,source_id,snapshot_json) VALUES(p_result,p_type,p_source,p_json);
  END;
  PROCEDURE employee_result(p_run NUMBER,p_e EMPLOYEE%ROWTYPE,p_p PAYROLL_PERIOD%ROWTYPE,p_pol PAYROLL_POLICY%ROWTYPE) IS
    v_result NUMBER; v_dep NUMBER; v_depname DEPARTMENT.department_name%TYPE; v_expected NUMBER; v_n NUMBER;
    v_std NUMBER; v_amount NUMBER; v_rate NUMBER; v_factor NUMBER; v_json CLOB;
    v_gross NUMBER; v_taxbase NUMBER; v_ins NUMBER; v_pit NUMBER; v_employer NUMBER; v_available NUMBER;
    v_other NUMBER:=0; v_depcount NUMBER; v_base NUMBER; v_enabled CHAR(1); v_collect NUMBER; v_days NUMBER; v_paid NUMBER;
  BEGIN
    SELECT a.department_id,d.department_name INTO v_dep,v_depname FROM EMPLOYEE_ASSIGNMENT a JOIN DEPARTMENT d ON d.department_id=a.department_id
      WHERE a.employee_id=p_e.employee_id AND a.valid_from<=LEAST(p_p.period_end-1,NVL(p_e.termination_date,p_p.period_end-1))
      AND (a.valid_to IS NULL OR a.valid_to>LEAST(p_p.period_end-1,NVL(p_e.termination_date,p_p.period_end-1)));
    INSERT INTO PAYROLL_RESULT(run_id,employee_id,employee_code_snapshot,employee_name_snapshot,department_id_snapshot,department_name_snapshot)
      VALUES(p_run,p_e.employee_id,p_e.employee_code,p_e.full_name,v_dep,v_depname) RETURNING result_id INTO v_result;
    SELECT JSON_OBJECT('employee_id' VALUE p_e.employee_id,'name' VALUE p_e.full_name,'hire_date' VALUE TO_CHAR(p_e.hire_date,'YYYY-MM-DD'),
      'termination_date' VALUE TO_CHAR(p_e.termination_date,'YYYY-MM-DD') RETURNING CLOB) INTO v_json FROM dual;
    snap(v_result,'EMPLOYEE',p_e.employee_id,v_json);
    SELECT JSON_OBJECT('policy_id' VALUE p_pol.policy_id,'code' VALUE p_pol.policy_code,'source_note' VALUE p_pol.source_note,
      'employee_rate' VALUE p_pol.employee_insurance_rate,'employer_rate' VALUE p_pol.employer_insurance_rate,'cap' VALUE p_pol.insurance_cap,
      'personal_relief' VALUE p_pol.personal_relief,'dependent_relief' VALUE p_pol.dependent_relief,'round_scale' VALUE p_pol.round_scale,
      'valid_from' VALUE TO_CHAR(p_pol.valid_from,'YYYY-MM-DD'),'valid_to' VALUE TO_CHAR(p_pol.valid_to,'YYYY-MM-DD'),
      'ot_workday' VALUE p_pol.ot_workday_factor,'ot_restday' VALUE p_pol.ot_restday_factor,'ot_holiday' VALUE p_pol.ot_holiday_factor,
      'night_extra' VALUE p_pol.night_extra_factor,'ot_taxable_fraction' VALUE p_pol.ot_taxable_fraction RETURNING CLOB) INTO v_json FROM dual;
    snap(v_result,'POLICY',p_pol.policy_id,v_json);
    FOR b IN (SELECT * FROM TAX_BRACKET WHERE policy_id=p_pol.policy_id) LOOP
      SELECT JSON_OBJECT('lower' VALUE b.lower_bound,'upper' VALUE b.upper_bound,'rate' VALUE b.rate RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'TAX_BRACKET',b.bracket_id,v_json);
    END LOOP;
    v_expected:=LEAST(p_p.period_end,NVL(p_e.termination_date+1,p_p.period_end))-GREATEST(p_e.hire_date,p_p.period_start);v_n:=0;
    FOR d IN (SELECT t.*,c.contract_id,c.monthly_salary,c.insurance_base,c.insurance_enabled,c.calendar_id,c.valid_from,c.valid_to,cd.standard_minutes,cd.day_type
      FROM TIMESHEET_DAILY t JOIN EMPLOYMENT_CONTRACT c ON c.employee_id=t.employee_id AND c.status='APPROVED' AND c.valid_from<=t.work_date AND (c.valid_to IS NULL OR c.valid_to>t.work_date)
      JOIN CALENDAR_DAY cd ON cd.calendar_id=c.calendar_id AND cd.work_date=t.work_date
      WHERE t.period_id=p_p.period_id AND t.employee_id=p_e.employee_id AND t.work_date>=p_e.hire_date AND (p_e.termination_date IS NULL OR t.work_date<=p_e.termination_date)
      ORDER BY t.work_date) LOOP
      v_n:=v_n+1;
      IF d.status<>'VALID' OR d.paid_minutes>d.standard_minutes THEN RAISE_APPLICATION_ERROR(-20030,'Invalid daily paid minutes'); END IF;
      SELECT SUM(standard_minutes),COUNT(*) INTO v_std,v_days FROM CALENDAR_DAY WHERE calendar_id=d.calendar_id AND work_date>=p_p.period_start AND work_date<p_p.period_end;
      IF v_days<>p_p.period_end-p_p.period_start OR NVL(v_std,0)<=0 THEN RAISE_APPLICATION_ERROR(-20031,'Calendar incomplete or zero divisor'); END IF;
      SELECT department_id INTO v_dep FROM EMPLOYEE_ASSIGNMENT WHERE employee_id=p_e.employee_id AND valid_from<=d.work_date AND (valid_to IS NULL OR valid_to>d.work_date);
      v_rate:=d.monthly_salary/v_std;v_amount:=ROUND(v_rate*d.paid_minutes,p_pol.round_scale);
      add_item(v_result,'BASE',v_dep,'TIMESHEET',d.timesheet_id,d.work_date,v_amount,v_amount,d.paid_minutes,v_rate,1,'monthly_salary / calendar_month_minutes * paid_minutes',p_pol.policy_id);
      SELECT JSON_OBJECT('contract_id' VALUE d.contract_id,'monthly_salary' VALUE d.monthly_salary,'insurance_base' VALUE d.insurance_base,
        'insurance_enabled' VALUE d.insurance_enabled,'calendar_id' VALUE d.calendar_id,'valid_from' VALUE TO_CHAR(d.valid_from,'YYYY-MM-DD'),'valid_to' VALUE TO_CHAR(d.valid_to,'YYYY-MM-DD') RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'CONTRACT',d.contract_id,v_json);
      SELECT JSON_OBJECT('work_date' VALUE TO_CHAR(d.work_date,'YYYY-MM-DD'),'paid_minutes' VALUE d.paid_minutes,'worked_minutes' VALUE d.worked_minutes,
        'paid_leave_minutes' VALUE d.paid_leave_minutes,'paid_holiday_minutes' VALUE d.paid_holiday_minutes,'day_type' VALUE d.day_type,
        'standard_minutes' VALUE d.standard_minutes,'month_standard_minutes' VALUE v_std,'department_id' VALUE v_dep RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'TIMESHEET',d.timesheet_id,v_json);
    END LOOP;
    IF v_n<>v_expected OR v_n=0 THEN RAISE_APPLICATION_ERROR(-20032,'Contract/calendar/timesheet gap or overlap'); END IF;
    -- Result-level deductions are allocated to the month-end department; daily BASE/OT preserves department per day.
    SELECT department_id INTO v_dep FROM EMPLOYEE_ASSIGNMENT WHERE employee_id=p_e.employee_id
      AND valid_from<=LEAST(p_p.period_end-1,NVL(p_e.termination_date,p_p.period_end-1)) AND (valid_to IS NULL OR valid_to>LEAST(p_p.period_end-1,NVL(p_e.termination_date,p_p.period_end-1)));
    FOR a IN (SELECT a.*,c.component_code,c.component_kind,c.taxable_fraction FROM EMPLOYEE_ALLOWANCE a JOIN PAY_COMPONENT c ON c.component_id=a.component_id
      WHERE a.employee_id=p_e.employee_id AND a.status='APPROVED' AND a.valid_from<p_p.period_end AND (a.valid_to IS NULL OR a.valid_to>p_p.period_start)) LOOP
      IF a.component_kind<>'EARNING' THEN RAISE_APPLICATION_ERROR(-20033,'Allowance must be earning'); END IF;
      v_amount:=0;
      IF a.allocation_method='FULL_MONTH' THEN
        IF a.valid_from>p_p.period_start OR NVL(a.valid_to,p_p.period_end)<p_p.period_end OR p_e.hire_date>p_p.period_start OR NVL(p_e.termination_date,p_p.period_end-1)<p_p.period_end-1 THEN
          RAISE_APPLICATION_ERROR(-20034,'FULL_MONTH allowance requires full-month eligibility; use other method');
        END IF; v_amount:=a.amount;
      ELSIF a.allocation_method='CALENDAR_DAYS' THEN
        v_days:=GREATEST(0,LEAST(p_p.period_end,NVL(a.valid_to,p_p.period_end),NVL(p_e.termination_date+1,p_p.period_end))-GREATEST(p_p.period_start,a.valid_from,p_e.hire_date));
        v_amount:=ROUND(a.amount*v_days/(p_p.period_end-p_p.period_start),p_pol.round_scale);
      ELSE
        FOR d IN (SELECT t.work_date,t.paid_minutes,c.calendar_id FROM TIMESHEET_DAILY t JOIN EMPLOYMENT_CONTRACT c ON c.employee_id=t.employee_id AND c.status='APPROVED'
          AND c.valid_from<=t.work_date AND (c.valid_to IS NULL OR c.valid_to>t.work_date)
          WHERE t.employee_id=p_e.employee_id AND t.period_id=p_p.period_id AND t.work_date>=a.valid_from AND (a.valid_to IS NULL OR t.work_date<a.valid_to)) LOOP
          SELECT SUM(standard_minutes) INTO v_std FROM CALENDAR_DAY WHERE calendar_id=d.calendar_id AND work_date>=p_p.period_start AND work_date<p_p.period_end;
          v_amount:=v_amount+ROUND(a.amount*d.paid_minutes/v_std,p_pol.round_scale);
        END LOOP;
      END IF;
      add_item(v_result,a.component_code,v_dep,'ALLOWANCE',a.allowance_id,NULL,v_amount,ROUND(v_amount*a.taxable_fraction,p_pol.round_scale),NULL,NULL,NULL,a.allocation_method,p_pol.policy_id);
      SELECT JSON_OBJECT('amount' VALUE a.amount,'allocation' VALUE a.allocation_method,'taxable_fraction' VALUE a.taxable_fraction,'valid_from' VALUE TO_CHAR(a.valid_from,'YYYY-MM-DD'),
        'valid_to' VALUE TO_CHAR(a.valid_to,'YYYY-MM-DD') RETURNING CLOB) INTO v_json FROM dual; snap(v_result,'ALLOWANCE',a.allowance_id,v_json);
    END LOOP;
    FOR o IN (SELECT * FROM OVERTIME_REQUEST WHERE employee_id=p_e.employee_id AND status='CONFIRMED'
      AND starts_at<CAST(p_p.period_end AS TIMESTAMP) AND ends_at>CAST(p_p.period_start AS TIMESTAMP)) LOOP
      SELECT NVL(SUM(payable_minutes),0) INTO v_paid FROM OVERTIME_SEGMENT WHERE overtime_id=o.overtime_id;
      IF v_paid<>LEAST(o.approved_minutes,o.actual_minutes) THEN RAISE_APPLICATION_ERROR(-20035,'OT segments must equal min approved and actual minutes'); END IF;
      SELECT COUNT(*) INTO v_n FROM OVERTIME_SEGMENT a JOIN OVERTIME_SEGMENT b ON a.overtime_id=b.overtime_id AND a.segment_id<b.segment_id
        AND a.starts_at<b.ends_at AND b.starts_at<a.ends_at WHERE a.overtime_id=o.overtime_id;
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20036,'Overlapping OT segments'); END IF;
      FOR s IN (SELECT * FROM OVERTIME_SEGMENT WHERE overtime_id=o.overtime_id AND work_date>=p_p.period_start AND work_date<p_p.period_end ORDER BY starts_at) LOOP
        IF s.starts_at<GREATEST(o.starts_at,o.actual_starts_at) OR s.ends_at>LEAST(o.ends_at,o.actual_ends_at) OR TRUNC(CAST(s.starts_at AS DATE))<>s.work_date OR s.ends_at>CAST(s.work_date+1 AS TIMESTAMP)
          OR s.payable_minutes>(CAST(s.ends_at AS DATE)-CAST(s.starts_at AS DATE))*1440 THEN RAISE_APPLICATION_ERROR(-20036,'OT segment invalid'); END IF;
        SELECT c.monthly_salary,cd.day_type,c.calendar_id INTO v_base,v_depname,v_days FROM EMPLOYMENT_CONTRACT c JOIN CALENDAR_DAY cd ON cd.calendar_id=c.calendar_id AND cd.work_date=s.work_date
          WHERE c.employee_id=p_e.employee_id AND c.status='APPROVED' AND c.valid_from<=s.work_date AND (c.valid_to IS NULL OR c.valid_to>s.work_date);
        SELECT SUM(standard_minutes) INTO v_std FROM CALENDAR_DAY WHERE calendar_id=v_days AND work_date>=p_p.period_start AND work_date<p_p.period_end;
        v_factor:=CASE v_depname WHEN 'WORKDAY' THEN p_pol.ot_workday_factor WHEN 'RESTDAY' THEN p_pol.ot_restday_factor ELSE p_pol.ot_holiday_factor END;
        IF s.is_night='Y' THEN v_factor:=v_factor+p_pol.night_extra_factor; END IF;
        SELECT department_id INTO v_dep FROM EMPLOYEE_ASSIGNMENT WHERE employee_id=p_e.employee_id AND valid_from<=s.work_date AND (valid_to IS NULL OR valid_to>s.work_date);
        v_rate:=v_base/v_std;v_amount:=ROUND(v_rate*s.payable_minutes*v_factor,p_pol.round_scale);
        add_item(v_result,'OT',v_dep,'OT_SEGMENT',s.segment_id,s.work_date,v_amount,ROUND(v_amount*p_pol.ot_taxable_fraction,p_pol.round_scale),s.payable_minutes,v_rate,v_factor,'hourly base from monthly calendar * confirmed minutes * day/night factor',p_pol.policy_id);
        SELECT JSON_OBJECT('approved_minutes' VALUE o.approved_minutes,'actual_minutes' VALUE o.actual_minutes,'segment_minutes' VALUE s.payable_minutes,
          'starts_at' VALUE TO_CHAR(s.starts_at,'YYYY-MM-DD HH24:MI:SS'),'ends_at' VALUE TO_CHAR(s.ends_at,'YYYY-MM-DD HH24:MI:SS'),'is_night' VALUE s.is_night,'day_type' VALUE v_depname RETURNING CLOB) INTO v_json FROM dual;
        snap(v_result,'OT_SEGMENT',s.segment_id,v_json);
      END LOOP;
    END LOOP;
    SELECT department_id_snapshot INTO v_dep FROM PAYROLL_RESULT WHERE result_id=v_result;
    FOR b IN (SELECT b.*,c.component_code,c.component_kind,c.taxable_fraction FROM BONUS_DEDUCTION b JOIN PAY_COMPONENT c ON c.component_id=b.component_id
      WHERE b.employee_id=p_e.employee_id AND b.period_id=p_p.period_id AND b.status='APPROVED' AND c.component_kind='EARNING') LOOP
      IF b.deduction_account_id IS NOT NULL THEN RAISE_APPLICATION_ERROR(-20037,'Earning cannot consume deduction balance'); END IF;
      add_item(v_result,b.component_code,v_dep,'BONUS',b.entry_id,NULL,b.amount,ROUND(b.amount*b.taxable_fraction,p_pol.round_scale),NULL,NULL,NULL,b.reason,p_pol.policy_id);
      SELECT JSON_OBJECT('amount' VALUE b.amount,'reason' VALUE b.reason,'taxable_fraction' VALUE b.taxable_fraction RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'BONUS',b.entry_id,v_json);
    END LOOP;
    SELECT NVL(SUM(amount),0),NVL(SUM(taxable_amount),0) INTO v_gross,v_taxbase FROM PAYROLL_ITEM WHERE result_id=v_result AND kind_snapshot='EARNING';
    SELECT insurance_base,insurance_enabled INTO v_base,v_enabled FROM (SELECT insurance_base,insurance_enabled FROM EMPLOYMENT_CONTRACT
      WHERE employee_id=p_e.employee_id AND status='APPROVED' AND valid_from<LEAST(p_p.period_end,NVL(p_e.termination_date+1,p_p.period_end)) ORDER BY valid_from DESC) WHERE ROWNUM=1;
    v_ins:=CASE WHEN v_enabled='Y' THEN ROUND(LEAST(v_base,p_pol.insurance_cap)*p_pol.employee_insurance_rate,p_pol.round_scale) ELSE 0 END;
    v_employer:=CASE WHEN v_enabled='Y' THEN ROUND(LEAST(v_base,p_pol.insurance_cap)*p_pol.employer_insurance_rate,p_pol.round_scale) ELSE 0 END;
    v_depcount:=0;
    FOR c IN (SELECT c.*,d.identity_hmac FROM DEPENDENT_CLAIM c JOIN DEPENDENT_PERSON d ON d.dependent_person_id=c.dependent_person_id
      WHERE c.employee_id=p_e.employee_id AND c.status='VERIFIED' AND c.valid_from<=p_p.period_end-1 AND (c.valid_to IS NULL OR c.valid_to>p_p.period_end-1)) LOOP
      v_depcount:=v_depcount+1;
      SELECT JSON_OBJECT('dependent_person_id' VALUE c.dependent_person_id,'valid_from' VALUE TO_CHAR(c.valid_from,'YYYY-MM-DD'),'valid_to' VALUE TO_CHAR(c.valid_to,'YYYY-MM-DD') RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'DEPENDENT',c.claim_id,v_json);
    END LOOP;
    v_taxbase:=GREATEST(0,v_taxbase-v_ins-p_pol.personal_relief-v_depcount*p_pol.dependent_relief);
    v_pit:=ROUND(PKG_PAYROLL_INTERNAL.bracket_tax(p_pol.policy_id,v_taxbase),p_pol.round_scale);
    v_available:=v_gross-v_ins-v_pit;
    IF v_available<0 THEN RAISE_APPLICATION_ERROR(-20038,'Insurance/tax exceeds gross; manual policy review required'); END IF;
    add_item(v_result,'INS_EMP',v_dep,'POLICY',p_pol.policy_id,NULL,v_ins,0,v_base,p_pol.employee_insurance_rate,1,'min(insurance_base,cap) * employee_rate',p_pol.policy_id);
    add_item(v_result,'PIT',v_dep,'POLICY',p_pol.policy_id,NULL,v_pit,0,v_taxbase,NULL,NULL,'sum of progressive taxable slices',p_pol.policy_id);
    add_item(v_result,'INS_COMPANY',v_dep,'POLICY',p_pol.policy_id,NULL,v_employer,0,v_base,p_pol.employer_insurance_rate,1,'company insurance expense; not deducted from Net',p_pol.policy_id);
    FOR b IN (SELECT b.*,c.component_code FROM BONUS_DEDUCTION b JOIN PAY_COMPONENT c ON c.component_id=b.component_id
      WHERE b.employee_id=p_e.employee_id AND b.period_id=p_p.period_id AND b.status='APPROVED' AND c.component_kind='DEDUCTION' ORDER BY b.entry_id) LOOP
      IF b.deduction_account_id IS NULL THEN RAISE_APPLICATION_ERROR(-20039,'Voluntary deductions require a balance account for carry-forward'); END IF;
      SELECT LEAST(principal_amount-collected_amount,monthly_limit) INTO v_collect FROM DEDUCTION_ACCOUNT WHERE deduction_account_id=b.deduction_account_id AND employee_id=p_e.employee_id;
      SELECT JSON_OBJECT('principal' VALUE principal_amount,'collected_before_run' VALUE collected_amount,'monthly_limit' VALUE monthly_limit RETURNING CLOB)
        INTO v_json FROM DEDUCTION_ACCOUNT WHERE deduction_account_id=b.deduction_account_id;
      snap(v_result,'DEDUCTION_ACCOUNT',b.deduction_account_id,v_json);
      SELECT NVL(SUM(amount),0) INTO v_paid FROM PAYROLL_ITEM WHERE result_id=v_result AND deduction_account_id=b.deduction_account_id;
      v_collect:=GREATEST(0,LEAST(b.amount,v_available-v_other,v_collect-v_paid));
      v_other:=v_other+v_collect;
      add_item(v_result,b.component_code,v_dep,'DEDUCTION',b.entry_id,NULL,v_collect,0,NULL,NULL,NULL,'min(requested,remaining balance,monthly limit,available Net)',p_pol.policy_id,b.deduction_account_id);
      SELECT JSON_OBJECT('requested_amount' VALUE b.amount,'collected_in_run' VALUE v_collect,'reason' VALUE b.reason RETURNING CLOB) INTO v_json FROM dual;
      snap(v_result,'DEDUCTION',b.entry_id,v_json);
    END LOOP;
    UPDATE PAYROLL_RESULT SET gross_amount=v_gross,employee_insurance=v_ins,pit_amount=v_pit,other_deduction=v_other,
      net_amount=v_available-v_other,employer_insurance=v_employer,taxable_income=v_taxbase,dependent_count=v_depcount WHERE result_id=v_result;
  END;
  PROCEDURE calculate(p_actor NUMBER,p_period NUMBER,p_request_key VARCHAR2,p_run OUT NUMBER) IS
    v_p PAYROLL_PERIOD%ROWTYPE; v_pol PAYROLL_POLICY%ROWTYPE; v_old PAYROLL_RUN%ROWTYPE; v_n NUMBER; v_ver NUMBER; v_success NUMBER:=0; v_errors NUMBER:=0;
    v_code NUMBER; v_msg VARCHAR2(2000);
  BEGIN
    SAVEPOINT calc_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL'); PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_request_key) IS NULL THEN RAISE_APPLICATION_ERROR(-20040,'request_key required'); END IF;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    BEGIN
      SELECT * INTO v_old FROM PAYROLL_RUN WHERE request_key=p_request_key;
      IF v_old.period_id<>p_period OR v_old.calculated_by<>p_actor THEN RAISE_APPLICATION_ERROR(-20041,'Idempotency key belongs to different request'); END IF;
      p_run:=v_old.run_id; RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE period_id=p_period AND status IN ('CALCULATING','PENDING_APPROVAL','APPROVED');
    IF v_p.period_status<>'OPEN' OR v_p.timesheet_status<>'LOCKED' OR v_n>0 THEN RAISE_APPLICATION_ERROR(-20042,'Period not ready or run frozen'); END IF;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_POLICY WHERE status='APPROVED' AND valid_from<v_p.period_end AND (valid_to IS NULL OR valid_to>v_p.period_start);
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20043,'Exactly one approved policy must cover entire month'); END IF;
    SELECT * INTO v_pol FROM PAYROLL_POLICY WHERE status='APPROVED' AND valid_from<=v_p.period_start AND (valid_to IS NULL OR valid_to>=v_p.period_end);
    v_n:=PKG_PAYROLL_INTERNAL.bracket_tax(v_pol.policy_id,0);
    SELECT NVL(MAX(version_no),0)+1 INTO v_ver FROM PAYROLL_RUN WHERE period_id=p_period;
    INSERT INTO PAYROLL_RUN(period_id,version_no,request_key,input_version,policy_id,calculated_by,status)
      VALUES(p_period,v_ver,p_request_key,v_p.input_version,v_pol.policy_id,p_actor,'CALCULATING') RETURNING run_id INTO p_run;
    FOR e IN (SELECT * FROM EMPLOYEE WHERE hire_date<v_p.period_end AND (termination_date IS NULL OR termination_date>=v_p.period_start) ORDER BY employee_id) LOOP
      SAVEPOINT calc_employee;
      BEGIN employee_result(p_run,e,v_p,v_pol); v_success:=v_success+1;
      EXCEPTION WHEN OTHERS THEN
        v_code:=SQLCODE;v_msg:=SUBSTR(SQLERRM,1,1800);ROLLBACK TO calc_employee;
        INSERT INTO PAYROLL_ERROR(run_id,employee_id,error_code,error_message) VALUES(p_run,e.employee_id,v_code,v_msg);v_errors:=v_errors+1;
      END;
    END LOOP;
    IF v_success+v_errors=0 THEN RAISE_APPLICATION_ERROR(-20044,'No eligible employees'); END IF;
    UPDATE PAYROLL_RUN SET status=CASE WHEN v_errors=0 THEN 'CALCULATED' ELSE 'ERROR' END,finished_at=SYSTIMESTAMP,success_count=v_success,error_count=v_errors WHERE run_id=p_run;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_RUN',p_run,'CALCULATE',NULL,NULL,NULL,p_request_key);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO calc_call; RAISE;
  END;
  PROCEDURE submit_run(p_actor NUMBER,p_run NUMBER) IS v_r PAYROLL_RUN%ROWTYPE; v_p PAYROLL_PERIOD%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT submit_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_r FROM PAYROLL_RUN WHERE run_id=p_run FOR UPDATE NOWAIT;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=v_r.period_id FOR UPDATE NOWAIT;
    IF v_r.status<>'CALCULATED' OR v_r.error_count<>0 OR v_r.input_version<>v_p.input_version OR v_p.timesheet_status<>'LOCKED' OR v_p.period_status<>'OPEN' THEN
      RAISE_APPLICATION_ERROR(-20045,'Run stale, erroneous or not calculated'); END IF;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE period_id=v_r.period_id AND version_no>v_r.version_no AND status<>'CANCELLED';
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20046,'A newer run exists'); END IF;
    UPDATE PAYROLL_RUN SET status='PENDING_APPROVAL' WHERE run_id=p_run;
    INSERT INTO PAYROLL_APPROVAL(run_id,action,actor_id) VALUES(p_run,'SUBMIT',p_actor);
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_RUN',p_run,'SUBMIT');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO submit_call; RAISE;
  END;
  PROCEDURE decide_run(p_actor NUMBER,p_run NUMBER,p_decision VARCHAR2,p_reason VARCHAR2 DEFAULT NULL) IS
    v_r PAYROLL_RUN%ROWTYPE; v_p PAYROLL_PERIOD%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT decide_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'DIRECTOR');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF p_decision IS NULL OR p_decision NOT IN ('APPROVE','REJECT') THEN RAISE_APPLICATION_ERROR(-20047,'Invalid decision'); END IF;
    IF p_decision='REJECT' AND TRIM(p_reason) IS NULL THEN RAISE_APPLICATION_ERROR(-20048,'Rejection reason required'); END IF;
    SELECT * INTO v_r FROM PAYROLL_RUN WHERE run_id=p_run FOR UPDATE NOWAIT;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=v_r.period_id FOR UPDATE NOWAIT;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_APPROVAL WHERE run_id=p_run AND action='SUBMIT' AND actor_id=p_actor;
    IF p_actor=v_r.calculated_by OR v_n>0 THEN RAISE_APPLICATION_ERROR(-20049,'Maker cannot approve own payroll'); END IF;
    IF v_r.status<>'PENDING_APPROVAL' OR v_r.input_version<>v_p.input_version OR v_r.error_count<>0 OR v_p.period_status<>'OPEN' THEN RAISE_APPLICATION_ERROR(-20050,'Run not ready for decision'); END IF;
    UPDATE PAYROLL_RUN SET status=CASE p_decision WHEN 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END WHERE run_id=p_run;
    INSERT INTO PAYROLL_APPROVAL(run_id,action,actor_id,reason) VALUES(p_run,p_decision,p_actor,p_reason);
    IF p_decision='APPROVE' THEN
      FOR a IN (SELECT i.deduction_account_id,SUM(i.amount) amount FROM PAYROLL_ITEM i JOIN PAYROLL_RESULT r ON r.result_id=i.result_id
        WHERE r.run_id=p_run AND i.deduction_account_id IS NOT NULL GROUP BY i.deduction_account_id ORDER BY i.deduction_account_id) LOOP
        UPDATE DEDUCTION_ACCOUNT SET collected_amount=collected_amount+a.amount WHERE deduction_account_id=a.deduction_account_id;
      END LOOP;
      INSERT INTO PAYSLIP(result_id,issued_by) SELECT result_id,p_actor FROM PAYROLL_RESULT WHERE run_id=p_run;
    END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_RUN',p_run,p_decision,p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO decide_call; RAISE;
  END;
END;
/
-- All public procedures leave COMMIT/ROLLBACK of the request transaction to API/caller.
