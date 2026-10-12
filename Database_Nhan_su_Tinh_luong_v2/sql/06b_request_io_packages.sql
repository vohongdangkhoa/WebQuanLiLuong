CREATE OR REPLACE PACKAGE PKG_REQUESTS AUTHID DEFINER AS
  PROCEDURE decide_leave(p_actor NUMBER,p_leave NUMBER,p_decision VARCHAR2,p_reason VARCHAR2 DEFAULT NULL);
  PROCEDURE approve_ot(p_actor NUMBER,p_ot NUMBER,p_minutes NUMBER);
  PROCEDURE confirm_ot(p_actor NUMBER,p_ot NUMBER,p_actual_start TIMESTAMP,p_actual_end TIMESTAMP);
  PROCEDURE register_document(p_actor NUMBER,p_storage_key VARCHAR2,p_name VARCHAR2,p_mime VARCHAR2,p_size NUMBER,p_hash VARCHAR2,p_document OUT NUMBER);
  PROCEDURE register_recon(p_actor NUMBER,p_document NUMBER,p_hash VARCHAR2,p_import OUT NUMBER);
  PROCEDURE add_recon_line(p_actor NUMBER,p_import NUMBER,p_line NUMBER,p_ref VARCHAR2,p_amount NUMBER,p_status VARCHAR2,p_bank_tx VARCHAR2,p_reason VARCHAR2,p_id OUT NUMBER);
END;
/
CREATE OR REPLACE PACKAGE BODY PKG_REQUESTS AS
  PROCEDURE decide_leave(p_actor NUMBER,p_leave NUMBER,p_decision VARCHAR2,p_reason VARCHAR2 DEFAULT NULL) IS
    v_l LEAVE_REQUEST%ROWTYPE;v_t LEAVE_TYPE%ROWTYPE;v_total NUMBER;v_balance NUMBER;v_n NUMBER;v_std NUMBER;v_emp NUMBER;
  BEGIN
    SAVEPOINT leave_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF p_decision IS NULL OR p_decision NOT IN ('APPROVE','REJECT') THEN RAISE_APPLICATION_ERROR(-20080,'Invalid leave decision'); END IF;
    SELECT * INTO v_l FROM LEAVE_REQUEST WHERE leave_id=p_leave FOR UPDATE NOWAIT;
    IF v_l.status<>'PENDING' OR v_l.requested_by=p_actor THEN RAISE_APPLICATION_ERROR(-20081,'Pending leave and different approver required'); END IF;
    SELECT employee_id INTO v_emp FROM EMPLOYEE WHERE employee_id=v_l.employee_id FOR UPDATE NOWAIT;
    IF p_decision='REJECT' THEN
      IF TRIM(p_reason) IS NULL THEN RAISE_APPLICATION_ERROR(-20082,'Rejection reason required'); END IF;
      UPDATE LEAVE_REQUEST SET status='REJECTED',decided_by=p_actor,decided_at=SYSTIMESTAMP,decision_reason=p_reason WHERE leave_id=p_leave;
    ELSE
      SELECT * INTO v_t FROM LEAVE_TYPE WHERE leave_type_id=v_l.leave_type_id;
      SELECT COUNT(*) INTO v_n FROM LEAVE_REQUEST WHERE employee_id=v_l.employee_id AND status='APPROVED'
        AND starts_at<v_l.ends_at AND ends_at>v_l.starts_at AND leave_id<>p_leave;
      IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20083,'Overlapping approved leave'); END IF;
      SELECT NVL(SUM(minutes),0) INTO v_total FROM LEAVE_DAY WHERE leave_id=p_leave;
      IF v_total=0 THEN RAISE_APPLICATION_ERROR(-20084,'Leave day allocation required'); END IF;
      IF v_t.uses_balance='Y' THEN
        SELECT NVL(SUM(delta_minutes),0) INTO v_balance FROM LEAVE_LEDGER
          WHERE employee_id=v_l.employee_id AND leave_type_id=v_l.leave_type_id
          AND (delta_minutes<0 OR effective_date<=TRUNC(CAST(v_l.starts_at AS DATE)));
        IF v_balance<v_total THEN RAISE_APPLICATION_ERROR(-20087,'Insufficient unreserved leave balance'); END IF;
      END IF;
      FOR d IN (SELECT * FROM LEAVE_DAY WHERE leave_id=p_leave ORDER BY work_date) LOOP
        IF d.work_date<TRUNC(CAST(v_l.starts_at AS DATE)) OR d.work_date>=CAST(v_l.ends_at AS DATE) THEN RAISE_APPLICATION_ERROR(-20085,'Leave allocation outside request'); END IF;
        SELECT cd.standard_minutes INTO v_std FROM EMPLOYMENT_CONTRACT c JOIN CALENDAR_DAY cd ON cd.calendar_id=c.calendar_id AND cd.work_date=d.work_date
          WHERE c.employee_id=v_l.employee_id AND c.status='APPROVED' AND c.valid_from<=d.work_date AND (c.valid_to IS NULL OR c.valid_to>d.work_date);
        IF d.minutes>v_std THEN RAISE_APPLICATION_ERROR(-20086,'Leave minutes exceed work calendar'); END IF;
        IF v_t.uses_balance='Y' THEN
          SELECT NVL(SUM(delta_minutes),0) INTO v_balance FROM LEAVE_LEDGER WHERE employee_id=v_l.employee_id AND leave_type_id=v_l.leave_type_id AND effective_date<=d.work_date;
          IF v_balance<d.minutes THEN RAISE_APPLICATION_ERROR(-20087,'Insufficient leave balance'); END IF;
          INSERT INTO LEAVE_LEDGER(employee_id,leave_type_id,leave_id,effective_date,delta_minutes,source_key,created_by)
            VALUES(v_l.employee_id,v_l.leave_type_id,p_leave,d.work_date,-d.minutes,'LEAVE-'||p_leave||'-'||TO_CHAR(d.work_date,'YYYYMMDD'),p_actor);
        END IF;
      END LOOP;
      UPDATE LEAVE_REQUEST SET status='APPROVED',decided_by=p_actor,decided_at=SYSTIMESTAMP,decision_reason=p_reason WHERE leave_id=p_leave;
    END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'LEAVE_REQUEST',p_leave,p_decision,p_reason);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO leave_call;RAISE;
  END;
  PROCEDURE approve_ot(p_actor NUMBER,p_ot NUMBER,p_minutes NUMBER) IS v_o OVERTIME_REQUEST%ROWTYPE;v_n NUMBER;
  BEGIN
    SAVEPOINT ot_approve_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_o FROM OVERTIME_REQUEST WHERE overtime_id=p_ot FOR UPDATE NOWAIT;
    IF v_o.status<>'PENDING' OR v_o.requested_by=p_actor OR p_minutes IS NULL OR p_minutes<=0 OR p_minutes<>TRUNC(p_minutes)
      OR p_minutes>(CAST(v_o.ends_at AS DATE)-CAST(v_o.starts_at AS DATE))*1440 THEN RAISE_APPLICATION_ERROR(-20088,'Invalid OT approval'); END IF;
    SELECT COUNT(*) INTO v_n FROM OVERTIME_REQUEST WHERE employee_id=v_o.employee_id AND overtime_id<>p_ot AND status IN ('APPROVED','CONFIRMED')
      AND starts_at<v_o.ends_at AND ends_at>v_o.starts_at;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20089,'OT overlaps another approved request'); END IF;
    SELECT COUNT(*) INTO v_n FROM EMPLOYEE_SHIFT WHERE employee_id=v_o.employee_id AND starts_at<v_o.ends_at AND ends_at>v_o.starts_at;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20090,'OT overlaps scheduled regular shift'); END IF;
    UPDATE OVERTIME_REQUEST SET status='APPROVED',approved_minutes=p_minutes,approved_by=p_actor WHERE overtime_id=p_ot;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'OVERTIME_REQUEST',p_ot,'APPROVE');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO ot_approve_call;RAISE;
  END;
  PROCEDURE confirm_ot(p_actor NUMBER,p_ot NUMBER,p_actual_start TIMESTAMP,p_actual_end TIMESTAMP) IS
    v_o OVERTIME_REQUEST%ROWTYPE;v_start TIMESTAMP;v_end TIMESTAMP;v_cut TIMESTAMP;v_day DATE;v_actual NUMBER;v_pay NUMBER;v_minutes NUMBER;v_night CHAR(1);
  BEGIN
    SAVEPOINT ot_confirm_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'HR');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_o FROM OVERTIME_REQUEST WHERE overtime_id=p_ot FOR UPDATE NOWAIT;
    IF v_o.status<>'APPROVED' OR v_o.requested_by=p_actor OR p_actual_start IS NULL OR p_actual_end IS NULL OR p_actual_end<=p_actual_start THEN RAISE_APPLICATION_ERROR(-20091,'Invalid actual OT interval'); END IF;
    v_start:=GREATEST(v_o.starts_at,p_actual_start);v_end:=LEAST(v_o.ends_at,p_actual_end);
    v_actual:=GREATEST(0,FLOOR((CAST(v_end AS DATE)-CAST(v_start AS DATE))*1440));
    v_pay:=LEAST(v_o.approved_minutes,v_actual);
    -- MVP: one contiguous actual interval, no break deduction. Payable minutes occupy its earliest eligible prefix.
    v_end:=v_start+NUMTODSINTERVAL(v_pay,'MINUTE');
    WHILE v_start<v_end LOOP
      v_day:=TRUNC(CAST(v_start AS DATE));
      IF v_start<CAST(v_day AS TIMESTAMP)+INTERVAL '6' HOUR THEN v_cut:=CAST(v_day AS TIMESTAMP)+INTERVAL '6' HOUR;v_night:='Y';
      ELSIF v_start<CAST(v_day AS TIMESTAMP)+INTERVAL '22' HOUR THEN v_cut:=CAST(v_day AS TIMESTAMP)+INTERVAL '22' HOUR;v_night:='N';
      ELSE v_cut:=CAST(v_day+1 AS TIMESTAMP);v_night:='Y'; END IF;
      v_cut:=LEAST(v_cut,v_end);v_minutes:=ROUND((CAST(v_cut AS DATE)-CAST(v_start AS DATE))*1440);
      IF v_minutes>0 THEN INSERT INTO OVERTIME_SEGMENT(overtime_id,work_date,starts_at,ends_at,payable_minutes,is_night)
        VALUES(p_ot,v_day,v_start,v_cut,v_minutes,v_night); END IF;
      v_start:=v_cut;
    END LOOP;
    UPDATE OVERTIME_REQUEST SET status='CONFIRMED',actual_minutes=v_actual,actual_starts_at=p_actual_start,actual_ends_at=p_actual_end,confirmed_by=p_actor WHERE overtime_id=p_ot;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'OVERTIME_REQUEST',p_ot,'CONFIRM');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO ot_confirm_call;RAISE;
  END;
  PROCEDURE register_document(p_actor NUMBER,p_storage_key VARCHAR2,p_name VARCHAR2,p_mime VARCHAR2,p_size NUMBER,p_hash VARCHAR2,p_document OUT NUMBER) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER WHERE user_id=p_actor AND is_active='Y';
    IF v_n<>1 OR LENGTH(p_hash)<>64 OR p_hash IS NULL THEN RAISE_APPLICATION_ERROR(-20092,'Invalid document actor/hash'); END IF;
    INSERT INTO DOCUMENT_FILE(storage_key,original_name,mime_type,size_bytes,sha256,uploaded_by)
      VALUES(p_storage_key,p_name,p_mime,p_size,p_hash,p_actor) RETURNING document_id INTO p_document;
  END;
  PROCEDURE register_recon(p_actor NUMBER,p_document NUMBER,p_hash VARCHAR2,p_import OUT NUMBER) IS v_n NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');
    SELECT COUNT(*) INTO v_n FROM DOCUMENT_FILE WHERE document_id=p_document AND sha256=p_hash AND uploaded_by=p_actor;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20093,'Reconciliation file owner/hash mismatch'); END IF;
    BEGIN SELECT recon_import_id INTO p_import FROM BANK_RECON_IMPORT WHERE file_sha256=p_hash;RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
    INSERT INTO BANK_RECON_IMPORT(file_sha256,document_id,imported_by) VALUES(p_hash,p_document,p_actor) RETURNING recon_import_id INTO p_import;
  END;
  PROCEDURE add_recon_line(p_actor NUMBER,p_import NUMBER,p_line NUMBER,p_ref VARCHAR2,p_amount NUMBER,p_status VARCHAR2,p_bank_tx VARCHAR2,p_reason VARCHAR2,p_id OUT NUMBER) IS v_n NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');
    SELECT COUNT(*) INTO v_n FROM BANK_RECON_IMPORT WHERE recon_import_id=p_import AND imported_by=p_actor;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20094,'Reconciliation import not owned by actor'); END IF;
    INSERT INTO BANK_RECON_LINE(recon_import_id,line_no,transfer_reference,reported_amount,bank_status,bank_transaction_id,failure_reason)
      VALUES(p_import,p_line,p_ref,p_amount,p_status,p_bank_tx,p_reason) RETURNING recon_line_id INTO p_id;
  END;
END;
/
