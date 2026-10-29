INSERT INTO SYSTEM_MUTEX VALUES ('PAYROLL_INPUT','Serialize payroll input changes and calculations');
INSERT INTO APP_ROLE (role_id,role_code,role_name) VALUES (1,'EMPLOYEE','Nhan vien');
INSERT INTO APP_ROLE (role_id,role_code,role_name) VALUES (2,'HR','Nhan su');
INSERT INTO APP_ROLE (role_id,role_code,role_name) VALUES (3,'PAYROLL','Ke toan luong');
INSERT INTO APP_ROLE (role_id,role_code,role_name) VALUES (4,'DIRECTOR','Giam doc');
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (1,'BASE','Luong theo cong','EARNING',1);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (2,'OT','Tien tang ca','EARNING',1);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (3,'INS_EMP','Bao hiem nhan vien','DEDUCTION',0);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (4,'PIT','Thue TNCN','DEDUCTION',0);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (5,'INS_COMPANY','Bao hiem cong ty','EMPLOYER_COST',0);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (6,'MEAL','Phu cap an','EARNING',0);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (7,'BONUS','Thuong','EARNING',1);
INSERT INTO PAY_COMPONENT (component_id,component_code,component_name,component_kind,taxable_fraction) VALUES (8,'OTHER_DED','Khau tru tu nguyen','DEDUCTION',0);
INSERT INTO WORK_CALENDAR (calendar_id,calendar_code,calendar_name) VALUES (1,'VN_STANDARD','Lich demo 8 gio thu hai den thu sau');
INSERT INTO LEAVE_TYPE (leave_type_id,leave_code,leave_name,paid_fraction,uses_balance) VALUES (1,'ANNUAL','Phep nam',1,'Y');
INSERT INTO LEAVE_TYPE (leave_type_id,leave_code,leave_name,paid_fraction,uses_balance) VALUES (2,'UNPAID','Nghi khong luong',0,'N');
INSERT INTO WORK_SHIFT (shift_id,shift_code,shift_name,start_minute,end_minute,end_day_offset,break_minutes) VALUES (1,'DAY','08:00-17:00',480,1020,0,60);
INSERT INTO WORK_SHIFT (shift_id,shift_code,shift_name,start_minute,end_minute,end_day_offset,break_minutes) VALUES (2,'NIGHT','22:00-07:00 hom sau',1320,420,1,60);
COMMIT;

CREATE OR REPLACE PACKAGE PKG_PAYROLL_INTERNAL AUTHID DEFINER AS
  PROCEDURE require_role(p_actor NUMBER,p_role VARCHAR2);
  PROCEDURE lock_inputs;
  PROCEDURE touch_period(p_period NUMBER);
  PROCEDURE touch_range(p_from DATE,p_to DATE);
  PROCEDURE audit_event(p_actor NUMBER,p_entity VARCHAR2,p_id NUMBER,p_action VARCHAR2,p_reason VARCHAR2 DEFAULT NULL,p_before CLOB DEFAULT NULL,p_after CLOB DEFAULT NULL,p_key VARCHAR2 DEFAULT NULL);
  FUNCTION bracket_tax(p_policy NUMBER,p_income NUMBER) RETURN NUMBER;
END;
/

CREATE OR REPLACE PACKAGE BODY PKG_PAYROLL_INTERNAL AS
  PROCEDURE require_role(p_actor NUMBER,p_role VARCHAR2) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u JOIN USER_ROLE ur ON ur.user_id=u.user_id JOIN APP_ROLE r ON r.role_id=ur.role_id
      WHERE u.user_id=p_actor AND u.is_active='Y' AND r.role_code=p_role;
    IF v_n=0 THEN RAISE_APPLICATION_ERROR(-20002,'Actor inactive or missing required role'); END IF;
  END;
  PROCEDURE lock_inputs IS v_key SYSTEM_MUTEX.lock_key%TYPE;
  BEGIN
    SELECT lock_key INTO v_key FROM SYSTEM_MUTEX WHERE lock_key='PAYROLL_INPUT' FOR UPDATE NOWAIT;
  END;
  PROCEDURE touch_period(p_period NUMBER) IS v_status VARCHAR2(10); v_n NUMBER;
  BEGIN
    lock_inputs;
    SELECT period_status INTO v_status FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE period_id=p_period AND status IN ('CALCULATING','PENDING_APPROVAL','APPROVED');
    IF v_status='CLOSED' OR v_n>0 THEN RAISE_APPLICATION_ERROR(-20003,'Payroll input is frozen'); END IF;
    UPDATE PAYROLL_PERIOD SET input_version=input_version+1 WHERE period_id=p_period;
  END;
  PROCEDURE touch_range(p_from DATE,p_to DATE) IS
  BEGIN
    lock_inputs;
    FOR p IN (SELECT period_id,timesheet_status FROM PAYROLL_PERIOD WHERE period_start<NVL(p_to,DATE '9999-12-31') AND period_end>p_from ORDER BY period_id) LOOP
      IF p.timesheet_status='LOCKED' THEN RAISE_APPLICATION_ERROR(-20006,'Reopen timesheet before changing payroll input'); END IF;
      touch_period(p.period_id);
    END LOOP;
  END;
  PROCEDURE audit_event(p_actor NUMBER,p_entity VARCHAR2,p_id NUMBER,p_action VARCHAR2,p_reason VARCHAR2 DEFAULT NULL,p_before CLOB DEFAULT NULL,p_after CLOB DEFAULT NULL,p_key VARCHAR2 DEFAULT NULL) IS
  BEGIN
    INSERT INTO AUDIT_LOG(actor_id,entity_type,entity_id,action,reason,before_json,after_json,correlation_key)
      VALUES(p_actor,p_entity,p_id,p_action,p_reason,p_before,p_after,p_key);
  END;
  FUNCTION bracket_tax(p_policy NUMBER,p_income NUMBER) RETURN NUMBER IS v_tax NUMBER:=0; v_next NUMBER:=0; v_n NUMBER:=0; v_open NUMBER:=0;
  BEGIN
    IF p_income IS NULL OR p_income<0 THEN RAISE_APPLICATION_ERROR(-20004,'Invalid taxable income'); END IF;
    FOR b IN (SELECT lower_bound,upper_bound,rate FROM TAX_BRACKET WHERE policy_id=p_policy ORDER BY lower_bound) LOOP
      IF b.lower_bound<>v_next OR v_open>0 THEN RAISE_APPLICATION_ERROR(-20005,'Tax brackets have a gap or overlap'); END IF;
      v_tax:=v_tax+GREATEST(0,LEAST(p_income,NVL(b.upper_bound,p_income))-b.lower_bound)*b.rate;
      v_next:=NVL(b.upper_bound,b.lower_bound); v_n:=v_n+1;
      IF b.upper_bound IS NULL THEN v_open:=v_open+1; END IF;
    END LOOP;
    IF v_n=0 OR v_open<>1 THEN RAISE_APPLICATION_ERROR(-20005,'Tax brackets must start at zero and end unbounded'); END IF;
    RETURN v_tax;
  END;
END;
/
-- No grants on this INTERNAL package to PAYROLL_API.
