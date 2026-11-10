-- Additive, owner-installed configuration API. No commits; no direct table grants.
CREATE OR REPLACE PACKAGE PKG_CONFIGURATION AUTHID DEFINER AS
  PROCEDURE read_data(p_actor NUMBER,p_resource VARCHAR2,p_employee NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE create_policy(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER);
  PROCEDURE create_allowance(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER);
  PROCEDURE create_entry(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER);
  PROCEDURE create_account(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER);
  PROCEDURE create_dependent(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER);
  PROCEDURE decide(p_actor NUMBER,p_resource VARCHAR2,p_id NUMBER,p_decision VARCHAR2,p_reason VARCHAR2);
  PROCEDURE end_policy(p_actor NUMBER,p_policy NUMBER,p_to DATE,p_reason VARCHAR2);
END PKG_CONFIGURATION;
/
CREATE OR REPLACE PACKAGE BODY PKG_CONFIGURATION AS
  FUNCTION role_count(p_actor NUMBER,p_role VARCHAR2) RETURN NUMBER IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u JOIN USER_ROLE ur ON ur.user_id=u.user_id JOIN APP_ROLE r ON r.role_id=ur.role_id
      WHERE u.user_id=p_actor AND u.is_active='Y' AND r.role_code=p_role;RETURN v_n;
  END;
  FUNCTION manager(p_actor NUMBER) RETURN NUMBER IS
  BEGIN RETURN GREATEST(role_count(p_actor,'HR'),role_count(p_actor,'PAYROLL'),role_count(p_actor,'DIRECTOR'));END;
  PROCEDURE require_manager(p_actor NUMBER) IS
  BEGIN IF manager(p_actor)=0 THEN RAISE_APPLICATION_ERROR(-20002,'Manager required');END IF;END;
  PROCEDURE require_writer(p_actor NUMBER) IS
  BEGIN IF GREATEST(role_count(p_actor,'HR'),role_count(p_actor,'PAYROLL'))=0 THEN RAISE_APPLICATION_ERROR(-20002,'HR or payroll required');END IF;END;
  PROCEDURE positive(p_id NUMBER) IS
  BEGIN IF p_id IS NULL OR p_id<=0 OR p_id<>TRUNC(p_id) THEN RAISE_APPLICATION_ERROR(-20700,'Positive ID required');END IF;END;
  FUNCTION json_day(p_json JSON_OBJECT_T,p_key VARCHAR2) RETURN DATE IS v_text VARCHAR2(30);
  BEGIN v_text:=p_json.get_string(p_key);IF v_text IS NULL THEN RETURN NULL;END IF;RETURN TO_DATE(v_text,'FXYYYY-MM-DD');
  EXCEPTION WHEN OTHERS THEN RAISE_APPLICATION_ERROR(-20700,'Invalid calendar date');END;
  PROCEDURE interval_ok(p_from DATE,p_to DATE) IS
  BEGIN IF p_from IS NULL OR p_from<>TRUNC(p_from) OR (p_to IS NOT NULL AND (p_to<>TRUNC(p_to) OR p_to<=p_from)) THEN RAISE_APPLICATION_ERROR(-20700,'Invalid effective interval');END IF;END;
  PROCEDURE employee_ok(p_employee NUMBER,p_from DATE DEFAULT NULL,p_to DATE DEFAULT NULL) IS v_e EMPLOYEE%ROWTYPE;
  BEGIN
    positive(p_employee);BEGIN SELECT * INTO v_e FROM EMPLOYEE WHERE employee_id=p_employee FOR UPDATE NOWAIT;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20704,'Employee not found');END;
    IF p_from IS NOT NULL AND (p_from<v_e.hire_date OR (v_e.termination_date IS NOT NULL AND (p_from>v_e.termination_date OR p_to IS NULL OR p_to>v_e.termination_date+1))) THEN RAISE_APPLICATION_ERROR(-20700,'Interval outside employment');END IF;
  END;
  PROCEDURE dependent_actor(p_actor NUMBER,p_employee NUMBER) IS v_e NUMBER;
  BEGIN
    IF role_count(p_actor,'HR')>0 THEN RETURN;END IF;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'EMPLOYEE');
    SELECT employee_id INTO v_e FROM APP_USER WHERE user_id=p_actor;
    IF v_e IS NULL OR v_e<>p_employee THEN RAISE_APPLICATION_ERROR(-20002,'Only own dependent registration allowed');END IF;
  END;
  PROCEDURE read_data(p_actor NUMBER,p_resource VARCHAR2,p_employee NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR) IS v_own NUMBER;v_manager NUMBER;
  BEGIN
    v_manager:=manager(p_actor);
    IF v_manager=0 THEN PKG_PAYROLL_INTERNAL.require_role(p_actor,'EMPLOYEE');SELECT employee_id INTO v_own FROM APP_USER WHERE user_id=p_actor;END IF;
    IF p_resource='employees' THEN
      OPEN p_rows FOR SELECT employee_id,employee_code,full_name FROM EMPLOYEE WHERE v_manager>0 OR employee_id=v_own ORDER BY employee_code;
    ELSIF p_resource='dependents' THEN
      IF v_manager=0 AND (v_own IS NULL OR (p_employee IS NOT NULL AND p_employee<>v_own)) THEN RAISE_APPLICATION_ERROR(-20002,'Own dependents only');END IF;
      OPEN p_rows FOR SELECT c.claim_id,c.employee_id,e.employee_code,e.full_name employee_name,d.full_name dependent_name,d.birth_date,
        c.valid_from,c.valid_to,c.document_id,c.status,c.requested_by,c.verified_by FROM DEPENDENT_CLAIM c
        JOIN DEPENDENT_PERSON d ON d.dependent_person_id=c.dependent_person_id JOIN EMPLOYEE e ON e.employee_id=c.employee_id
        WHERE (v_manager>0 OR c.employee_id=v_own) AND (p_employee IS NULL OR c.employee_id=p_employee) ORDER BY c.claim_id DESC;
    ELSE
      require_manager(p_actor);
      IF p_resource='periods' THEN OPEN p_rows FOR SELECT period_id,period_start,period_status FROM PAYROLL_PERIOD ORDER BY period_start DESC;
      ELSIF p_resource='components' THEN OPEN p_rows FOR SELECT component_id,component_code,component_name,component_kind,taxable_fraction FROM PAY_COMPONENT WHERE component_code NOT IN ('BASE','OT','INS_EMP','PIT','INS_COMPANY') ORDER BY component_code;
      ELSIF p_resource='accounts' THEN OPEN p_rows FOR SELECT a.deduction_account_id,a.employee_id,e.employee_code,a.principal_amount,a.collected_amount,a.monthly_limit,a.description FROM DEDUCTION_ACCOUNT a JOIN EMPLOYEE e ON e.employee_id=a.employee_id ORDER BY a.deduction_account_id DESC;
      ELSIF p_resource='policies' THEN OPEN p_rows FOR SELECT policy_id,policy_code,valid_from,valid_to,employee_insurance_rate,employer_insurance_rate,insurance_cap,personal_relief,dependent_relief,ot_workday_factor,ot_restday_factor,ot_holiday_factor,night_extra_factor,ot_taxable_fraction,round_scale,status,created_by,approved_by,source_note FROM PAYROLL_POLICY ORDER BY valid_from DESC,policy_id DESC;
      ELSIF p_resource='brackets' THEN OPEN p_rows FOR SELECT bracket_id,lower_bound,upper_bound,rate FROM TAX_BRACKET WHERE policy_id=p_period ORDER BY lower_bound;
      ELSIF p_resource='allowances' THEN OPEN p_rows FOR SELECT a.allowance_id,a.employee_id,e.employee_code,e.full_name,a.component_id,c.component_name,a.amount,a.allocation_method,a.valid_from,a.valid_to,a.status,a.created_by,a.approved_by FROM EMPLOYEE_ALLOWANCE a JOIN EMPLOYEE e ON e.employee_id=a.employee_id JOIN PAY_COMPONENT c ON c.component_id=a.component_id WHERE p_employee IS NULL OR a.employee_id=p_employee ORDER BY a.allowance_id DESC;
      ELSIF p_resource='entries' THEN OPEN p_rows FOR SELECT b.entry_id,b.employee_id,e.employee_code,e.full_name,b.period_id,p.period_start,b.component_id,c.component_name,c.component_kind,b.amount,b.deduction_account_id,b.reason,b.status,b.created_by,b.approved_by FROM BONUS_DEDUCTION b JOIN EMPLOYEE e ON e.employee_id=b.employee_id JOIN PAY_COMPONENT c ON c.component_id=b.component_id JOIN PAYROLL_PERIOD p ON p.period_id=b.period_id WHERE (p_employee IS NULL OR b.employee_id=p_employee) AND (p_period IS NULL OR b.period_id=p_period) ORDER BY b.entry_id DESC;
      ELSE RAISE_APPLICATION_ERROR(-20700,'Unknown configuration resource');END IF;
    END IF;
  END;
  PROCEDURE create_policy(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER) IS j JSON_OBJECT_T;b JSON_OBJECT_T;bands JSON_ARRAY_T;v_from DATE;v_to DATE;v_tax NUMBER;
  BEGIN
    SAVEPOINT config_policy;PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    j:=JSON_OBJECT_T.parse(p_data);v_from:=json_day(j,'validFrom');v_to:=json_day(j,'validTo');interval_ok(v_from,v_to);
    IF TRIM(j.get_string('policyCode')) IS NULL OR LENGTH(TRIM(j.get_string('policyCode')))>40 OR TRIM(j.get_string('sourceNote')) IS NULL THEN RAISE_APPLICATION_ERROR(-20700,'Policy code and source note required');END IF;
    INSERT INTO PAYROLL_POLICY(policy_code,valid_from,valid_to,employee_insurance_rate,employer_insurance_rate,insurance_cap,personal_relief,dependent_relief,ot_workday_factor,ot_restday_factor,ot_holiday_factor,night_extra_factor,ot_taxable_fraction,round_scale,status,created_by,source_note,parameters_json)
    VALUES(TRIM(j.get_string('policyCode')),v_from,v_to,j.get_number('employeeInsuranceRate'),j.get_number('employerInsuranceRate'),j.get_number('insuranceCap'),j.get_number('personalRelief'),j.get_number('dependentRelief'),j.get_number('otWorkdayFactor'),j.get_number('otRestdayFactor'),j.get_number('otHolidayFactor'),j.get_number('nightExtraFactor'),j.get_number('otTaxableFraction'),j.get_number('roundScale'),'PENDING',p_actor,j.get_string('sourceNote'),p_data) RETURNING policy_id INTO p_id;
    bands:=j.get_array('brackets');IF bands IS NULL THEN RAISE_APPLICATION_ERROR(-20700,'Tax brackets required');END IF;
    IF bands.get_size<1 OR bands.get_size>50 THEN RAISE_APPLICATION_ERROR(-20700,'One to fifty tax brackets required');END IF;
    FOR i IN 0..bands.get_size-1 LOOP
      b:=TREAT(bands.get(i) AS JSON_OBJECT_T);
      INSERT INTO TAX_BRACKET(policy_id,lower_bound,upper_bound,rate) VALUES(p_id,b.get_number('lowerBound'),b.get_number('upperBound'),b.get_number('rate'));
    END LOOP;
    v_tax:=PKG_PAYROLL_INTERNAL.bracket_tax(p_id,0);
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_POLICY',p_id,'CREATE_PENDING',j.get_string('sourceNote'));
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_policy;RAISE;END;
  PROCEDURE create_allowance(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER) IS j JSON_OBJECT_T;v_from DATE;v_to DATE;v_c PAY_COMPONENT%ROWTYPE;
  BEGIN
    SAVEPOINT config_allowance;require_writer(p_actor);PKG_PAYROLL_INTERNAL.lock_inputs;j:=JSON_OBJECT_T.parse(p_data);
    v_from:=json_day(j,'validFrom');v_to:=json_day(j,'validTo');interval_ok(v_from,v_to);employee_ok(j.get_number('employeeId'),v_from,v_to);
    SELECT * INTO v_c FROM PAY_COMPONENT WHERE component_id=j.get_number('componentId');
    IF v_c.component_kind<>'EARNING' OR v_c.component_code IN ('BASE','OT') THEN RAISE_APPLICATION_ERROR(-20700,'Manual earning component required');END IF;
    IF j.get_number('amount') IS NULL OR j.get_number('amount')<0 OR j.get_string('allocationMethod') NOT IN ('FULL_MONTH','PAID_MINUTES','CALENDAR_DAYS') THEN RAISE_APPLICATION_ERROR(-20700,'Invalid allowance');END IF;
    INSERT INTO EMPLOYEE_ALLOWANCE(employee_id,component_id,amount,allocation_method,valid_from,valid_to,created_by) VALUES(j.get_number('employeeId'),v_c.component_id,j.get_number('amount'),j.get_string('allocationMethod'),v_from,v_to,p_actor) RETURNING allowance_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE_ALLOWANCE',p_id,'CREATE_PENDING');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_allowance;RAISE;END;
  PROCEDURE create_account(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER) IS j JSON_OBJECT_T;
  BEGIN
    SAVEPOINT config_account;PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;j:=JSON_OBJECT_T.parse(p_data);employee_ok(j.get_number('employeeId'));
    IF TRIM(j.get_string('description')) IS NULL OR j.get_number('principalAmount') IS NULL OR j.get_number('principalAmount')<=0 OR j.get_number('monthlyLimit') IS NULL OR j.get_number('monthlyLimit')<=0 THEN RAISE_APPLICATION_ERROR(-20700,'Invalid deduction balance');END IF;
    INSERT INTO DEDUCTION_ACCOUNT(employee_id,principal_amount,monthly_limit,opened_by,description) VALUES(j.get_number('employeeId'),j.get_number('principalAmount'),j.get_number('monthlyLimit'),p_actor,j.get_string('description')) RETURNING deduction_account_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'DEDUCTION_ACCOUNT',p_id,'CREATE');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_account;RAISE;END;
  PROCEDURE create_entry(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER) IS j JSON_OBJECT_T;v_c PAY_COMPONENT%ROWTYPE;v_p PAYROLL_PERIOD%ROWTYPE;v_n NUMBER;
  BEGIN
    SAVEPOINT config_entry;require_writer(p_actor);PKG_PAYROLL_INTERNAL.lock_inputs;j:=JSON_OBJECT_T.parse(p_data);employee_ok(j.get_number('employeeId'));positive(j.get_number('periodId'));
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=j.get_number('periodId') FOR UPDATE NOWAIT;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE WHERE employee_id=j.get_number('employeeId') AND hire_date<v_p.period_end AND (termination_date IS NULL OR termination_date>=v_p.period_start);
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20700,'Employee not employed during period');END IF;
    SELECT * INTO v_c FROM PAY_COMPONENT WHERE component_id=j.get_number('componentId');
    IF v_c.component_kind NOT IN ('EARNING','DEDUCTION') OR v_c.component_code IN ('BASE','OT','INS_EMP','PIT','INS_COMPANY') OR j.get_number('amount') IS NULL OR j.get_number('amount')<=0 OR TRIM(j.get_string('reason')) IS NULL THEN RAISE_APPLICATION_ERROR(-20700,'Invalid manual earning or deduction');END IF;
    IF v_c.component_kind='DEDUCTION' THEN
      SELECT COUNT(*) INTO v_n FROM DEDUCTION_ACCOUNT WHERE deduction_account_id=j.get_number('deductionAccountId') AND employee_id=j.get_number('employeeId') AND principal_amount>collected_amount;
      IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20700,'Matching uncollected balance account required');END IF;
    ELSIF j.get_number('deductionAccountId') IS NOT NULL THEN RAISE_APPLICATION_ERROR(-20700,'Earning cannot link deduction balance');END IF;
    INSERT INTO BONUS_DEDUCTION(employee_id,period_id,component_id,amount,deduction_account_id,reason,created_by) VALUES(j.get_number('employeeId'),v_p.period_id,v_c.component_id,j.get_number('amount'),j.get_number('deductionAccountId'),j.get_string('reason'),p_actor) RETURNING entry_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'BONUS_DEDUCTION',p_id,'CREATE_PENDING',j.get_string('reason'));
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_entry;RAISE;END;
  PROCEDURE create_dependent(p_actor NUMBER,p_data CLOB,p_id OUT NUMBER) IS j JSON_OBJECT_T;v_from DATE;v_to DATE;v_birth DATE;v_person DEPENDENT_PERSON%ROWTYPE;v_n NUMBER;v_hash VARCHAR2(128);v_name VARCHAR2(150);
  BEGIN
    SAVEPOINT config_dependent;PKG_PAYROLL_INTERNAL.lock_inputs;j:=JSON_OBJECT_T.parse(p_data);dependent_actor(p_actor,j.get_number('employeeId'));
    v_from:=json_day(j,'validFrom');v_to:=json_day(j,'validTo');v_birth:=json_day(j,'birthDate');interval_ok(v_from,v_to);employee_ok(j.get_number('employeeId'),v_from,v_to);
    v_hash:=j.get_string('identityHmac');v_name:=TRIM(j.get_string('fullName'));
    IF v_hash IS NULL OR NOT REGEXP_LIKE(v_hash,'^[0-9A-Fa-f]{64}$') OR v_name IS NULL OR (v_birth IS NOT NULL AND v_birth>TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE))) THEN RAISE_APPLICATION_ERROR(-20700,'Invalid dependent identity or birth date');END IF;
    SELECT COUNT(*) INTO v_n FROM DOCUMENT_FILE WHERE document_id=j.get_number('documentId') AND uploaded_by=p_actor AND size_bytes>0 AND REGEXP_LIKE(storage_key,'^uploads/[0-9a-fA-F]{32}$') AND mime_type IN ('application/pdf','image/png','image/jpeg');
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20708,'Actual owned uploaded proof required');END IF;
    BEGIN SELECT * INTO v_person FROM DEPENDENT_PERSON WHERE identity_hmac=v_hash FOR UPDATE NOWAIT;
      IF UPPER(v_person.full_name)<>UPPER(v_name) OR NVL(TO_CHAR(v_person.birth_date,'YYYY-MM-DD'),'?')<>NVL(TO_CHAR(v_birth,'YYYY-MM-DD'),'?') THEN RAISE_APPLICATION_ERROR(-20709,'Identity already registered with different details');END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      INSERT INTO DEPENDENT_PERSON(identity_hmac,full_name,birth_date) VALUES(v_hash,v_name,v_birth) RETURNING dependent_person_id INTO v_person.dependent_person_id;
    END;
    SELECT COUNT(*) INTO v_n FROM DEPENDENT_CLAIM WHERE dependent_person_id=v_person.dependent_person_id AND employee_id=j.get_number('employeeId') AND status IN ('PENDING','VERIFIED') AND valid_from<NVL(v_to,DATE '9999-12-31') AND NVL(valid_to,DATE '9999-12-31')>v_from;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20706,'Overlapping dependent claim already exists');END IF;
    INSERT INTO DEPENDENT_CLAIM(dependent_person_id,employee_id,valid_from,valid_to,document_id,requested_by) VALUES(v_person.dependent_person_id,j.get_number('employeeId'),v_from,v_to,j.get_number('documentId'),p_actor) RETURNING claim_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'DEPENDENT_CLAIM',p_id,'CREATE_PENDING','Owned uploaded proof checked; no identity logged');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_dependent;RAISE;END;
  PROCEDURE decide(p_actor NUMBER,p_resource VARCHAR2,p_id NUMBER,p_decision VARCHAR2,p_reason VARCHAR2) IS v_policy PAYROLL_POLICY%ROWTYPE;v_allow EMPLOYEE_ALLOWANCE%ROWTYPE;v_entry BONUS_DEDUCTION%ROWTYPE;v_claim DEPENDENT_CLAIM%ROWTYPE;v_creator NUMBER;v_state VARCHAR2(20);v_n NUMBER;v_tax NUMBER;v_entity VARCHAR2(40);
  BEGIN
    SAVEPOINT config_decide;PKG_PAYROLL_INTERNAL.require_role(p_actor,'DIRECTOR');PKG_PAYROLL_INTERNAL.lock_inputs;positive(p_id);
    IF p_decision IS NULL OR p_decision NOT IN ('APPROVE','REJECT') OR (p_decision='REJECT' AND TRIM(p_reason) IS NULL) THEN RAISE_APPLICATION_ERROR(-20700,'Decision and rejection reason required');END IF;
    IF p_resource='policies' THEN SELECT * INTO v_policy FROM PAYROLL_POLICY WHERE policy_id=p_id FOR UPDATE NOWAIT;v_creator:=v_policy.created_by;v_state:=v_policy.status;v_entity:='PAYROLL_POLICY';
    ELSIF p_resource='allowances' THEN SELECT * INTO v_allow FROM EMPLOYEE_ALLOWANCE WHERE allowance_id=p_id FOR UPDATE NOWAIT;v_creator:=v_allow.created_by;v_state:=v_allow.status;v_entity:='EMPLOYEE_ALLOWANCE';
    ELSIF p_resource='entries' THEN SELECT * INTO v_entry FROM BONUS_DEDUCTION WHERE entry_id=p_id FOR UPDATE NOWAIT;v_creator:=v_entry.created_by;v_state:=v_entry.status;v_entity:='BONUS_DEDUCTION';
    ELSIF p_resource='dependents' THEN SELECT * INTO v_claim FROM DEPENDENT_CLAIM WHERE claim_id=p_id FOR UPDATE NOWAIT;v_creator:=v_claim.requested_by;v_state:=v_claim.status;v_entity:='DEPENDENT_CLAIM';
    ELSE RAISE_APPLICATION_ERROR(-20700,'Unknown decision resource');END IF;
    IF v_state<>'PENDING' THEN RAISE_APPLICATION_ERROR(-20705,'Pending record required');END IF;
    IF v_creator=p_actor THEN RAISE_APPLICATION_ERROR(-20703,'Maker cannot approve own record');END IF;
    IF p_resource='policies' THEN
      IF p_decision='APPROVE' THEN
        SELECT COUNT(*) INTO v_n FROM PAYROLL_POLICY WHERE policy_id<>p_id AND status='APPROVED' AND valid_from<NVL(v_policy.valid_to,DATE '9999-12-31') AND NVL(valid_to,DATE '9999-12-31')>v_policy.valid_from;
        IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20706,'Approved policy overlap; close previous version first');END IF;
        v_tax:=PKG_PAYROLL_INTERNAL.bracket_tax(p_id,0);
      END IF;
      UPDATE PAYROLL_POLICY SET status=CASE WHEN p_decision='APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,approved_by=CASE WHEN p_decision='APPROVE' THEN p_actor END WHERE policy_id=p_id;
    ELSIF p_resource='allowances' THEN UPDATE EMPLOYEE_ALLOWANCE SET status=CASE WHEN p_decision='APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,approved_by=CASE WHEN p_decision='APPROVE' THEN p_actor END WHERE allowance_id=p_id;
    ELSIF p_resource='entries' THEN UPDATE BONUS_DEDUCTION SET status=CASE WHEN p_decision='APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,approved_by=CASE WHEN p_decision='APPROVE' THEN p_actor END WHERE entry_id=p_id;
    ELSE UPDATE DEPENDENT_CLAIM SET status=CASE WHEN p_decision='APPROVE' THEN 'VERIFIED' ELSE 'REJECTED' END,verified_by=CASE WHEN p_decision='APPROVE' THEN p_actor END,verified_at=CASE WHEN p_decision='APPROVE' THEN SYSTIMESTAMP END WHERE claim_id=p_id;END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,v_entity,p_id,p_decision,p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_decide;RAISE;END;
  PROCEDURE end_policy(p_actor NUMBER,p_policy NUMBER,p_to DATE,p_reason VARCHAR2) IS v_p PAYROLL_POLICY%ROWTYPE;
  BEGIN
    SAVEPOINT config_end;PKG_PAYROLL_INTERNAL.require_role(p_actor,'DIRECTOR');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_p FROM PAYROLL_POLICY WHERE policy_id=p_policy FOR UPDATE NOWAIT;
    IF v_p.status<>'APPROVED' OR p_to IS NULL OR p_to<>TRUNC(p_to) OR p_to<=v_p.valid_from OR (v_p.valid_to IS NOT NULL AND p_to>=v_p.valid_to) OR TRIM(p_reason) IS NULL THEN RAISE_APPLICATION_ERROR(-20700,'Only shorten approved policy interval with reason');END IF;
    UPDATE PAYROLL_POLICY SET valid_to=p_to WHERE policy_id=p_policy;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_POLICY',p_policy,'END_VERSION',p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO config_end;RAISE;END;
END PKG_CONFIGURATION;
/
GRANT EXECUTE ON PKG_CONFIGURATION TO PAYROLL_API;
