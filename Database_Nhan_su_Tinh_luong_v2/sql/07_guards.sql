CREATE OR REPLACE TRIGGER tg_append_timekeeping_raw
BEFORE UPDATE OR DELETE ON TIMEKEEPING_RAW
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only TIMEKEEPING_RAW'); END;
/

CREATE OR REPLACE TRIGGER tg_append_audit_log
BEFORE UPDATE OR DELETE ON AUDIT_LOG
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only AUDIT_LOG'); END;
/

CREATE OR REPLACE TRIGGER tg_append_payroll_approval
BEFORE UPDATE OR DELETE ON PAYROLL_APPROVAL
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only PAYROLL_APPROVAL'); END;
/

CREATE OR REPLACE TRIGGER tg_append_leave_ledger
BEFORE UPDATE OR DELETE ON LEAVE_LEDGER
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only LEAVE_LEDGER'); END;
/

CREATE OR REPLACE TRIGGER tg_append_payroll_snapshot
BEFORE UPDATE OR DELETE ON PAYROLL_SNAPSHOT
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only PAYROLL_SNAPSHOT'); END;
/

CREATE OR REPLACE TRIGGER tg_append_payroll_error
BEFORE UPDATE OR DELETE ON PAYROLL_ERROR
BEGIN RAISE_APPLICATION_ERROR(-20100,'Append-only PAYROLL_ERROR'); END;
/

CREATE OR REPLACE TRIGGER tg_guard_payroll_item
BEFORE INSERT OR UPDATE OR DELETE ON PAYROLL_ITEM FOR EACH ROW
DECLARE v_status VARCHAR2(20);
BEGIN
  SELECT u.status INTO v_status FROM PAYROLL_RUN u JOIN PAYROLL_RESULT r ON r.run_id=u.run_id WHERE r.result_id=NVL(:OLD.result_id,:NEW.result_id);
  IF v_status<>'CALCULATING' THEN RAISE_APPLICATION_ERROR(-20101,'Completed payroll data is immutable'); END IF;
  
END;
/

CREATE OR REPLACE TRIGGER tg_guard_payroll_snapshot
BEFORE INSERT ON PAYROLL_SNAPSHOT FOR EACH ROW
DECLARE v_status VARCHAR2(20);
BEGIN
  SELECT u.status INTO v_status FROM PAYROLL_RUN u JOIN PAYROLL_RESULT r ON r.run_id=u.run_id WHERE r.result_id=:NEW.result_id;
  IF v_status<>'CALCULATING' THEN RAISE_APPLICATION_ERROR(-20101,'Completed payroll data is immutable'); END IF;
  
END;
/

CREATE OR REPLACE TRIGGER tg_guard_payroll_result
BEFORE INSERT OR UPDATE OR DELETE ON PAYROLL_RESULT FOR EACH ROW
DECLARE v_status VARCHAR2(20);
BEGIN
  SELECT u.status INTO v_status FROM PAYROLL_RUN u WHERE u.run_id=NVL(:OLD.run_id,:NEW.run_id);
  IF v_status<>'CALCULATING' THEN RAISE_APPLICATION_ERROR(-20101,'Completed payroll data is immutable'); END IF;
  IF UPDATING('run_id') OR UPDATING('employee_id') OR UPDATING('result_id') THEN RAISE_APPLICATION_ERROR(-20102,'Payroll identity immutable'); END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_run_transition
BEFORE UPDATE OR DELETE ON PAYROLL_RUN FOR EACH ROW
BEGIN
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20103,'Payroll run cannot be deleted'); END IF;
  IF UPDATING('period_id') OR UPDATING('version_no') OR UPDATING('request_key') OR UPDATING('input_version') OR UPDATING('policy_id') OR UPDATING('calculated_by') OR UPDATING('engine_version') THEN
    RAISE_APPLICATION_ERROR(-20104,'Run identity and inputs immutable'); END IF;
  IF :OLD.status IN ('APPROVED','REJECTED','CANCELLED') THEN RAISE_APPLICATION_ERROR(-20105,'Terminal run immutable'); END IF;
  IF :OLD.status<>:NEW.status AND NOT (
    (:OLD.status='CALCULATING' AND :NEW.status IN ('CALCULATED','ERROR')) OR
    (:OLD.status='CALCULATED' AND :NEW.status IN ('PENDING_APPROVAL','CANCELLED')) OR
    (:OLD.status='ERROR' AND :NEW.status='CANCELLED') OR
    (:OLD.status='PENDING_APPROVAL' AND :NEW.status IN ('APPROVED','REJECTED')))
  THEN RAISE_APPLICATION_ERROR(-20106,'Invalid payroll state transition'); END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_payment_guard
BEFORE INSERT OR UPDATE OR DELETE ON PAYMENT_ITEM FOR EACH ROW
DECLARE v_amount NUMBER;v_state VARCHAR2(20);v_batch VARCHAR2(20);
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20107,'Payment attempt cannot be deleted'); END IF;
  IF INSERTING THEN
    SELECT r.net_amount,u.status INTO v_amount,v_state FROM PAYROLL_RESULT r JOIN PAYROLL_RUN u ON u.run_id=r.run_id WHERE r.result_id=:NEW.result_id;
    SELECT status INTO v_batch FROM PAYMENT_BATCH WHERE batch_id=:NEW.batch_id;
    IF v_state<>'APPROVED' OR v_amount<>:NEW.amount OR :NEW.status<>'READY' OR v_batch<>'CREATED' THEN RAISE_APPLICATION_ERROR(-20108,'Payment not tied to approved amount/batch'); END IF;
  ELSE
    IF UPDATING('batch_id') OR UPDATING('run_id') OR UPDATING('result_id') OR UPDATING('employee_id') OR UPDATING('bank_account_id') OR UPDATING('amount') OR UPDATING('attempt_no') OR UPDATING('transfer_reference') OR UPDATING('account_ciphertext_snapshot') OR UPDATING('account_last4_snapshot') OR UPDATING('holder_name_snapshot') OR UPDATING('bank_code_snapshot') THEN
      RAISE_APPLICATION_ERROR(-20109,'Payment amount, destination and identity immutable'); END IF;
    IF :OLD.status IN ('SUCCEEDED','FAILED','CANCELLED') THEN RAISE_APPLICATION_ERROR(-20110,'Terminal payment immutable'); END IF;
    IF :OLD.status<>:NEW.status AND NOT ((:OLD.status='READY' AND :NEW.status IN ('PROCESSING','CANCELLED')) OR (:OLD.status='PROCESSING' AND :NEW.status IN ('SUCCEEDED','FAILED'))) THEN
      RAISE_APPLICATION_ERROR(-20111,'Invalid payment transition'); END IF;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_timesheet_input
BEFORE INSERT OR UPDATE OR DELETE ON TIMESHEET_DAILY FOR EACH ROW
DECLARE v_p PAYROLL_PERIOD%ROWTYPE;
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=NVL(:OLD.period_id,:NEW.period_id) FOR UPDATE NOWAIT;
  IF v_p.timesheet_status='LOCKED' THEN RAISE_APPLICATION_ERROR(-20112,'Timesheet locked'); END IF;
  IF NOT DELETING AND (:NEW.work_date<v_p.period_start OR :NEW.work_date>=v_p.period_end) THEN RAISE_APPLICATION_ERROR(-20113,'Timesheet outside month'); END IF;
  IF UPDATING('employee_id') OR UPDATING('work_date') OR UPDATING('period_id') THEN RAISE_APPLICATION_ERROR(-20114,'Daily identity immutable'); END IF;
  PKG_PAYROLL_INTERNAL.touch_period(v_p.period_id);
END;
/

CREATE OR REPLACE TRIGGER tg_range_employment_contract
FOR INSERT OR UPDATE OR DELETE ON EMPLOYMENT_CONTRACT COMPOUND TRIGGER
  TYPE ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids ids;g_count PLS_INTEGER:=0;
  BEFORE EACH ROW IS v_id NUMBER;v_from DATE;v_to DATE;
  BEGIN
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF UPDATING('employee_id') THEN RAISE_APPLICATION_ERROR(-20116,'Source parent cannot be reassigned'); END IF;
    IF UPDATING AND :OLD.status='APPROVED' AND (UPDATING('monthly_salary') OR UPDATING('insurance_base') OR UPDATING('calendar_id') OR UPDATING('insurance_enabled') OR UPDATING('valid_from') OR UPDATING('employee_id') OR UPDATING('status') OR UPDATING('approved_by') OR UPDATING('created_by')) THEN RAISE_APPLICATION_ERROR(-20115,'Published source: create a new version'); END IF;
    IF DELETING THEN RAISE_APPLICATION_ERROR(-20117,'Temporal history cannot be deleted'); END IF;
    SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id=:NEW.employee_id FOR UPDATE NOWAIT;
    g_count:=g_count+1;g_ids(g_count):=v_id;
    v_from:=:NEW.valid_from;v_to:=:NEW.valid_to;
    IF UPDATING THEN
      IF UPDATING('valid_to') AND NOT UPDATING('valid_from') THEN
        v_from:=LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
        v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      ELSE
        v_from:=LEAST(:OLD.valid_from,:NEW.valid_from);v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      END IF;
    END IF;
    PKG_PAYROLL_INTERNAL.touch_range(v_from,v_to);
  END BEFORE EACH ROW;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    FOR i IN 1..g_count LOOP
      SELECT COUNT(*) INTO v_n FROM EMPLOYMENT_CONTRACT a JOIN EMPLOYMENT_CONTRACT b ON a.employee_id=b.employee_id AND a.ROWID<b.ROWID 
        WHERE a.employee_id=g_ids(i) AND a.status='APPROVED' AND b.status='APPROVED'
        AND a.valid_from<NVL(b.valid_to,DATE '9999-12-31') AND b.valid_from<NVL(a.valid_to,DATE '9999-12-31');
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20118,'Overlapping active intervals in EMPLOYMENT_CONTRACT'); END IF;
    END LOOP;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_range_employee_assignment
FOR INSERT OR UPDATE OR DELETE ON EMPLOYEE_ASSIGNMENT COMPOUND TRIGGER
  TYPE ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids ids;g_count PLS_INTEGER:=0;
  BEFORE EACH ROW IS v_id NUMBER;v_from DATE;v_to DATE;
  BEGIN
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF UPDATING('employee_id') THEN RAISE_APPLICATION_ERROR(-20116,'Source parent cannot be reassigned'); END IF;
    IF UPDATING('department_id') OR UPDATING('position_id') OR UPDATING('valid_from') THEN RAISE_APPLICATION_ERROR(-20115,'Assignment immutable; close interval and create new version'); END IF;
    IF DELETING THEN RAISE_APPLICATION_ERROR(-20117,'Temporal history cannot be deleted'); END IF;
    SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id=:NEW.employee_id FOR UPDATE NOWAIT;
    g_count:=g_count+1;g_ids(g_count):=v_id;
    v_from:=:NEW.valid_from;v_to:=:NEW.valid_to;
    IF UPDATING THEN
      IF UPDATING('valid_to') AND NOT UPDATING('valid_from') THEN
        v_from:=LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
        v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      ELSE
        v_from:=LEAST(:OLD.valid_from,:NEW.valid_from);v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      END IF;
    END IF;
    PKG_PAYROLL_INTERNAL.touch_range(v_from,v_to);
  END BEFORE EACH ROW;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    FOR i IN 1..g_count LOOP
      SELECT COUNT(*) INTO v_n FROM EMPLOYEE_ASSIGNMENT a JOIN EMPLOYEE_ASSIGNMENT b ON a.employee_id=b.employee_id AND a.ROWID<b.ROWID 
        WHERE a.employee_id=g_ids(i) AND 1=1 AND 1=1
        AND a.valid_from<NVL(b.valid_to,DATE '9999-12-31') AND b.valid_from<NVL(a.valid_to,DATE '9999-12-31');
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20118,'Overlapping active intervals in EMPLOYEE_ASSIGNMENT'); END IF;
    END LOOP;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_range_employee_bank_account
FOR INSERT OR UPDATE OR DELETE ON EMPLOYEE_BANK_ACCOUNT COMPOUND TRIGGER
  TYPE ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids ids;g_count PLS_INTEGER:=0;
  BEFORE EACH ROW IS v_id NUMBER;v_from DATE;v_to DATE;
  BEGIN
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF UPDATING('employee_id') THEN RAISE_APPLICATION_ERROR(-20116,'Source parent cannot be reassigned'); END IF;
    IF UPDATING AND :OLD.status='VERIFIED' AND (UPDATING('account_ciphertext') OR UPDATING('account_hmac') OR UPDATING('account_last4') OR UPDATING('bank_code') OR UPDATING('holder_name') OR UPDATING('valid_from') OR UPDATING('employee_id') OR UPDATING('status') OR UPDATING('verified_by') OR UPDATING('created_by')) THEN RAISE_APPLICATION_ERROR(-20115,'Published source: create a new version'); END IF;
    IF DELETING THEN RAISE_APPLICATION_ERROR(-20117,'Temporal history cannot be deleted'); END IF;
    SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id=:NEW.employee_id FOR UPDATE NOWAIT;
    g_count:=g_count+1;g_ids(g_count):=v_id;
    v_from:=:NEW.valid_from;v_to:=:NEW.valid_to;
    IF UPDATING THEN
      IF UPDATING('valid_to') AND NOT UPDATING('valid_from') THEN
        v_from:=LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
        v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      ELSE
        v_from:=LEAST(:OLD.valid_from,:NEW.valid_from);v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      END IF;
    END IF;
    
  END BEFORE EACH ROW;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    FOR i IN 1..g_count LOOP
      SELECT COUNT(*) INTO v_n FROM EMPLOYEE_BANK_ACCOUNT a JOIN EMPLOYEE_BANK_ACCOUNT b ON a.employee_id=b.employee_id AND a.ROWID<b.ROWID 
        WHERE a.employee_id=g_ids(i) AND a.status='VERIFIED' AND b.status='VERIFIED'
        AND a.valid_from<NVL(b.valid_to,DATE '9999-12-31') AND b.valid_from<NVL(a.valid_to,DATE '9999-12-31');
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20118,'Overlapping active intervals in EMPLOYEE_BANK_ACCOUNT'); END IF;
    END LOOP;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_range_dependent_claim
FOR INSERT OR UPDATE OR DELETE ON DEPENDENT_CLAIM COMPOUND TRIGGER
  TYPE ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids ids;g_count PLS_INTEGER:=0;
  BEFORE EACH ROW IS v_id NUMBER;v_from DATE;v_to DATE;
  BEGIN
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF UPDATING('dependent_person_id') THEN RAISE_APPLICATION_ERROR(-20116,'Source parent cannot be reassigned'); END IF;
    IF UPDATING AND :OLD.status='VERIFIED' AND (UPDATING('employee_id') OR UPDATING('dependent_person_id') OR UPDATING('valid_from') OR UPDATING('status') OR UPDATING('verified_by') OR UPDATING('requested_by')) THEN RAISE_APPLICATION_ERROR(-20115,'Published source: create a new version'); END IF;
    IF DELETING THEN RAISE_APPLICATION_ERROR(-20117,'Temporal history cannot be deleted'); END IF;
    SELECT dependent_person_id INTO v_id FROM DEPENDENT_PERSON WHERE dependent_person_id=:NEW.dependent_person_id FOR UPDATE NOWAIT;
    g_count:=g_count+1;g_ids(g_count):=v_id;
    v_from:=:NEW.valid_from;v_to:=:NEW.valid_to;
    IF UPDATING THEN
      IF UPDATING('valid_to') AND NOT UPDATING('valid_from') THEN
        v_from:=LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
        v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      ELSE
        v_from:=LEAST(:OLD.valid_from,:NEW.valid_from);v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      END IF;
    END IF;
    PKG_PAYROLL_INTERNAL.touch_range(v_from,v_to);
  END BEFORE EACH ROW;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    FOR i IN 1..g_count LOOP
      SELECT COUNT(*) INTO v_n FROM DEPENDENT_CLAIM a JOIN DEPENDENT_CLAIM b ON a.dependent_person_id=b.dependent_person_id AND a.ROWID<b.ROWID 
        WHERE a.dependent_person_id=g_ids(i) AND a.status='VERIFIED' AND b.status='VERIFIED'
        AND a.valid_from<NVL(b.valid_to,DATE '9999-12-31') AND b.valid_from<NVL(a.valid_to,DATE '9999-12-31');
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20118,'Overlapping active intervals in DEPENDENT_CLAIM'); END IF;
    END LOOP;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_range_employee_allowance
FOR INSERT OR UPDATE OR DELETE ON EMPLOYEE_ALLOWANCE COMPOUND TRIGGER
  TYPE ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_ids ids;g_count PLS_INTEGER:=0;
  BEFORE EACH ROW IS v_id NUMBER;v_from DATE;v_to DATE;
  BEGIN
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF UPDATING('employee_id') THEN RAISE_APPLICATION_ERROR(-20116,'Source parent cannot be reassigned'); END IF;
    IF UPDATING AND :OLD.status='APPROVED' AND (UPDATING('amount') OR UPDATING('allocation_method') OR UPDATING('component_id') OR UPDATING('valid_from') OR UPDATING('employee_id') OR UPDATING('status') OR UPDATING('approved_by') OR UPDATING('created_by')) THEN RAISE_APPLICATION_ERROR(-20115,'Published source: create a new version'); END IF;
    IF DELETING THEN RAISE_APPLICATION_ERROR(-20117,'Temporal history cannot be deleted'); END IF;
    SELECT employee_id INTO v_id FROM EMPLOYEE WHERE employee_id=:NEW.employee_id FOR UPDATE NOWAIT;
    g_count:=g_count+1;g_ids(g_count):=v_id;
    v_from:=:NEW.valid_from;v_to:=:NEW.valid_to;
    IF UPDATING THEN
      IF UPDATING('valid_to') AND NOT UPDATING('valid_from') THEN
        v_from:=LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
        v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      ELSE
        v_from:=LEAST(:OLD.valid_from,:NEW.valid_from);v_to:=GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31'));
      END IF;
    END IF;
    PKG_PAYROLL_INTERNAL.touch_range(v_from,v_to);
  END BEFORE EACH ROW;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    FOR i IN 1..g_count LOOP
      SELECT COUNT(*) INTO v_n FROM EMPLOYEE_ALLOWANCE a JOIN EMPLOYEE_ALLOWANCE b ON a.employee_id=b.employee_id AND a.ROWID<b.ROWID  AND a.component_id=b.component_id
        WHERE a.employee_id=g_ids(i) AND a.status='APPROVED' AND b.status='APPROVED'
        AND a.valid_from<NVL(b.valid_to,DATE '9999-12-31') AND b.valid_from<NVL(a.valid_to,DATE '9999-12-31');
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20118,'Overlapping active intervals in EMPLOYEE_ALLOWANCE'); END IF;
    END LOOP;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_calendar_input
BEFORE INSERT OR UPDATE OR DELETE ON CALENDAR_DAY FOR EACH ROW
BEGIN
  IF UPDATING('calendar_id') OR UPDATING('work_date') THEN RAISE_APPLICATION_ERROR(-20131,'Calendar day identity immutable'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(NVL(:OLD.work_date,:NEW.work_date),NVL(:OLD.work_date,:NEW.work_date)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_input_payroll_policy
BEFORE INSERT OR UPDATE OR DELETE ON PAYROLL_POLICY FOR EACH ROW
DECLARE v_n NUMBER;
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20122,'Configuration history cannot be deleted'); END IF;
  IF UPDATING AND :OLD.status='APPROVED' THEN
      IF UPDATING('valid_from') OR UPDATING('employee_insurance_rate') OR UPDATING('employer_insurance_rate') OR UPDATING('insurance_cap') OR UPDATING('personal_relief') OR UPDATING('dependent_relief') OR UPDATING('ot_workday_factor') OR UPDATING('ot_restday_factor') OR UPDATING('ot_holiday_factor') OR UPDATING('night_extra_factor') OR UPDATING('ot_taxable_fraction') OR UPDATING('round_scale') OR UPDATING('status') OR UPDATING('source_note') OR UPDATING('approved_by') OR UPDATING('created_by') OR UPDATING('parameters_json') OR UPDATING('policy_code') THEN
        RAISE_APPLICATION_ERROR(-20119,'Approved policy values immutable; create new version'); END IF;
      PKG_PAYROLL_INTERNAL.touch_range(LEAST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31')),GREATEST(NVL(:OLD.valid_to,DATE '9999-12-31'),NVL(:NEW.valid_to,DATE '9999-12-31')));
    ELSE PKG_PAYROLL_INTERNAL.touch_range(:NEW.valid_from,:NEW.valid_to); END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_input_tax_bracket
BEFORE INSERT OR UPDATE OR DELETE ON TAX_BRACKET FOR EACH ROW
DECLARE v_n NUMBER;
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20122,'Configuration history cannot be deleted'); END IF;
  SELECT COUNT(*) INTO v_n FROM PAYROLL_POLICY WHERE policy_id=NVL(:OLD.policy_id,:NEW.policy_id) AND status='APPROVED';
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20120,'Tax brackets of approved policy immutable'); END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_input_pay_component
BEFORE INSERT OR UPDATE OR DELETE ON PAY_COMPONENT FOR EACH ROW
DECLARE v_n NUMBER;
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20122,'Configuration history cannot be deleted'); END IF;
  SELECT COUNT(*) INTO v_n FROM PAYROLL_ITEM WHERE component_id=NVL(:OLD.component_id,:NEW.component_id);
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20121,'Used component immutable; create a new component'); END IF;
    FOR p IN (SELECT period_id FROM PAYROLL_PERIOD WHERE period_status='OPEN' AND timesheet_status<>'LOCKED') LOOP PKG_PAYROLL_INTERNAL.touch_period(p.period_id);END LOOP;
END;
/

CREATE OR REPLACE TRIGGER tg_source_leave_request
BEFORE INSERT OR UPDATE OR DELETE ON LEAVE_REQUEST FOR EACH ROW
BEGIN
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20123,'Source history cannot be deleted'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(CAST(NVL(:OLD.starts_at,:NEW.starts_at) AS DATE),CAST(NVL(:OLD.ends_at,:NEW.ends_at) AS DATE)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_source_overtime_request
BEFORE INSERT OR UPDATE OR DELETE ON OVERTIME_REQUEST FOR EACH ROW
BEGIN
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20123,'Source history cannot be deleted'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(CAST(NVL(:OLD.starts_at,:NEW.starts_at) AS DATE),CAST(NVL(:OLD.ends_at,:NEW.ends_at) AS DATE)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_source_employee_shift
BEFORE INSERT OR UPDATE OR DELETE ON EMPLOYEE_SHIFT FOR EACH ROW
BEGIN
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20123,'Source history cannot be deleted'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(NVL(:OLD.work_date,:NEW.work_date),NVL(:OLD.work_date,:NEW.work_date)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_source_leave_day
BEFORE INSERT OR UPDATE OR DELETE ON LEAVE_DAY FOR EACH ROW
DECLARE v_state VARCHAR2(20);
BEGIN
  SELECT status INTO v_state FROM LEAVE_REQUEST WHERE leave_id=NVL(:OLD.leave_id,:NEW.leave_id);
  IF v_state IN ('APPROVED','REJECTED','CANCELLED') THEN RAISE_APPLICATION_ERROR(-20124,'Approved leave allocation immutable'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(NVL(:OLD.work_date,:NEW.work_date),NVL(:OLD.work_date,:NEW.work_date)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_source_overtime_segment
BEFORE INSERT OR UPDATE OR DELETE ON OVERTIME_SEGMENT FOR EACH ROW
DECLARE v_state VARCHAR2(20);
BEGIN
  SELECT status INTO v_state FROM OVERTIME_REQUEST WHERE overtime_id=NVL(:OLD.overtime_id,:NEW.overtime_id);
  IF DELETING OR UPDATING THEN RAISE_APPLICATION_ERROR(-20125,'OT segments immutable'); END IF;
  PKG_PAYROLL_INTERNAL.touch_range(NVL(:OLD.work_date,:NEW.work_date),NVL(:OLD.work_date,:NEW.work_date)+1);
END;
/

CREATE OR REPLACE TRIGGER tg_bonus_input
BEFORE INSERT OR UPDATE OR DELETE ON BONUS_DEDUCTION FOR EACH ROW
DECLARE v_p PAYROLL_PERIOD%ROWTYPE;
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=NVL(:OLD.period_id,:NEW.period_id);
  IF v_p.timesheet_status='LOCKED' THEN RAISE_APPLICATION_ERROR(-20126,'Reopen inputs first'); END IF;
  PKG_PAYROLL_INTERNAL.touch_period(v_p.period_id);
END;
/

CREATE OR REPLACE TRIGGER tg_employee_input
BEFORE INSERT OR UPDATE OR DELETE ON EMPLOYEE FOR EACH ROW
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20127,'Employee history cannot be deleted'); END IF;
  IF INSERTING THEN
    PKG_PAYROLL_INTERNAL.touch_range(:NEW.hire_date,:NEW.termination_date+1);
  ELSIF UPDATING('hire_date') THEN
    PKG_PAYROLL_INTERNAL.touch_range(LEAST(:OLD.hire_date,:NEW.hire_date),GREATEST(:OLD.hire_date,:NEW.hire_date));
  ELSIF UPDATING('termination_date') THEN
    PKG_PAYROLL_INTERNAL.touch_range(LEAST(NVL(:OLD.termination_date+1,DATE '9999-12-31'),NVL(:NEW.termination_date+1,DATE '9999-12-31')),
      GREATEST(NVL(:OLD.termination_date+1,DATE '9999-12-31'),NVL(:NEW.termination_date+1,DATE '9999-12-31')));
  ELSE
    FOR p IN (SELECT period_id FROM PAYROLL_PERIOD WHERE period_status='OPEN' AND timesheet_status<>'LOCKED') LOOP PKG_PAYROLL_INTERNAL.touch_period(p.period_id);END LOOP;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_deduction_balance
BEFORE INSERT OR UPDATE OR DELETE ON DEDUCTION_ACCOUNT FOR EACH ROW
BEGIN
  PKG_PAYROLL_INTERNAL.lock_inputs;
  IF DELETING OR UPDATING('employee_id') THEN RAISE_APPLICATION_ERROR(-20128,'Balance account identity immutable'); END IF;
  -- collected_amount is settlement at approval, not editable through the runtime account.
  IF INSERTING OR UPDATING('principal_amount') OR UPDATING('monthly_limit') THEN
    FOR p IN (SELECT p.period_id,p.period_start,p.period_end FROM PAYROLL_PERIOD p WHERE p.period_status='OPEN'
      AND NOT EXISTS(SELECT 1 FROM PAYROLL_RUN r WHERE r.period_id=p.period_id AND r.status='APPROVED')) LOOP
      PKG_PAYROLL_INTERNAL.touch_range(p.period_start,p.period_end);END LOOP;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER tg_department_cycle
FOR INSERT OR UPDATE ON DEPARTMENT COMPOUND TRIGGER
  BEFORE STATEMENT IS BEGIN PKG_PAYROLL_INTERNAL.lock_inputs; END BEFORE STATEMENT;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM (SELECT CONNECT_BY_ISCYCLE cyc FROM DEPARTMENT CONNECT BY NOCYCLE PRIOR department_id=parent_id) WHERE cyc=1;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20129,'Department hierarchy contains a cycle'); END IF;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_shift_overlap
FOR INSERT OR UPDATE ON EMPLOYEE_SHIFT COMPOUND TRIGGER
  BEFORE STATEMENT IS BEGIN PKG_PAYROLL_INTERNAL.lock_inputs; END BEFORE STATEMENT;
  AFTER STATEMENT IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE_SHIFT a JOIN EMPLOYEE_SHIFT b ON a.employee_id=b.employee_id AND a.employee_shift_id<b.employee_shift_id
      AND a.starts_at<b.ends_at AND b.starts_at<a.ends_at;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20130,'Scheduled shifts overlap'); END IF;
  END AFTER STATEMENT;
END;
/

CREATE OR REPLACE TRIGGER tg_contract_audit
AFTER INSERT OR UPDATE ON EMPLOYMENT_CONTRACT FOR EACH ROW
DECLARE v_before CLOB;v_after CLOB;
BEGIN
  IF UPDATING THEN SELECT JSON_OBJECT('salary' VALUE :OLD.monthly_salary,'insurance_base' VALUE :OLD.insurance_base,'status' VALUE :OLD.status,
    'valid_from' VALUE TO_CHAR(:OLD.valid_from,'YYYY-MM-DD'),'valid_to' VALUE TO_CHAR(:OLD.valid_to,'YYYY-MM-DD') RETURNING CLOB) INTO v_before FROM dual; END IF;
  SELECT JSON_OBJECT('salary' VALUE :NEW.monthly_salary,'insurance_base' VALUE :NEW.insurance_base,'status' VALUE :NEW.status,
    'valid_from' VALUE TO_CHAR(:NEW.valid_from,'YYYY-MM-DD'),'valid_to' VALUE TO_CHAR(:NEW.valid_to,'YYYY-MM-DD') RETURNING CLOB) INTO v_after FROM dual;
  PKG_PAYROLL_INTERNAL.audit_event(NULL,'EMPLOYMENT_CONTRACT',:NEW.contract_id,'SOURCE_DML','Database DML; see db_username',v_before,v_after);
END;
/

CREATE OR REPLACE TRIGGER tg_timesheet_audit
AFTER INSERT OR UPDATE ON TIMESHEET_DAILY FOR EACH ROW
DECLARE v_before CLOB;v_after CLOB;
BEGIN
  IF UPDATING THEN SELECT JSON_OBJECT('worked' VALUE :OLD.worked_minutes,'paid_leave' VALUE :OLD.paid_leave_minutes,'paid_holiday' VALUE :OLD.paid_holiday_minutes,
    'paid' VALUE :OLD.paid_minutes,'status' VALUE :OLD.status,'version' VALUE :OLD.row_version RETURNING CLOB) INTO v_before FROM dual; END IF;
  SELECT JSON_OBJECT('worked' VALUE :NEW.worked_minutes,'paid_leave' VALUE :NEW.paid_leave_minutes,'paid_holiday' VALUE :NEW.paid_holiday_minutes,
    'paid' VALUE :NEW.paid_minutes,'status' VALUE :NEW.status,'version' VALUE :NEW.row_version RETURNING CLOB) INTO v_after FROM dual;
  PKG_PAYROLL_INTERNAL.audit_event(NULL,'TIMESHEET_DAILY',:NEW.timesheet_id,'SOURCE_DML','Database DML; actor recorded by HR package separately',v_before,v_after);
END;
/
