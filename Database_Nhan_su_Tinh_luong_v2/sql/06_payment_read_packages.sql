CREATE OR REPLACE PACKAGE PKG_PAYMENT AUTHID DEFINER AS
  PROCEDURE create_batch(p_actor NUMBER,p_run NUMBER,p_request_key VARCHAR2,p_batch OUT NUMBER);
  PROCEDURE mark_exported(p_actor NUMBER,p_batch NUMBER,p_document NUMBER,p_sha256 VARCHAR2);
  PROCEDURE mark_sent(p_actor NUMBER,p_batch NUMBER);
  PROCEDURE apply_recon_line(p_actor NUMBER,p_line NUMBER);
  PROCEDURE close_period(p_actor NUMBER,p_period NUMBER);
  PROCEDURE export_rows(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR);
END;
/
CREATE OR REPLACE PACKAGE BODY PKG_PAYMENT AS
  PROCEDURE create_batch(p_actor NUMBER,p_run NUMBER,p_request_key VARCHAR2,p_batch OUT NUMBER) IS
    v_run PAYROLL_RUN%ROWTYPE; v_old PAYMENT_BATCH%ROWTYPE; v_bank EMPLOYEE_BANK_ACCOUNT%ROWTYPE; v_n NUMBER; v_attempt NUMBER; v_id NUMBER;
    v_date DATE:=TRUNC(CAST(SYSTIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE));v_count NUMBER:=0;
  BEGIN
    SAVEPOINT batch_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_request_key) IS NULL THEN RAISE_APPLICATION_ERROR(-20060,'request_key required'); END IF;
    SELECT * INTO v_run FROM PAYROLL_RUN WHERE run_id=p_run FOR UPDATE NOWAIT;
    BEGIN
      SELECT * INTO v_old FROM PAYMENT_BATCH WHERE request_key=p_request_key;
      IF v_old.run_id<>p_run OR v_old.created_by<>p_actor THEN RAISE_APPLICATION_ERROR(-20061,'Payment key belongs to different request'); END IF;
      p_batch:=v_old.batch_id;RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
    IF v_run.status<>'APPROVED' THEN RAISE_APPLICATION_ERROR(-20062,'Only approved payroll can be paid'); END IF;
    SELECT COUNT(*) INTO v_n FROM PAYROLL_PERIOD WHERE period_id=v_run.period_id AND period_status='OPEN';
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20063,'Period closed'); END IF;
    INSERT INTO PAYMENT_BATCH(run_id,request_key,created_by) VALUES(p_run,p_request_key,p_actor) RETURNING batch_id INTO p_batch;
    FOR r IN (SELECT * FROM PAYROLL_RESULT WHERE run_id=p_run AND net_amount>0 ORDER BY result_id) LOOP
      SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE result_id=r.result_id AND status IN ('READY','PROCESSING','SUCCEEDED');
      IF v_n=0 THEN
        SELECT * INTO v_bank FROM EMPLOYEE_BANK_ACCOUNT WHERE employee_id=r.employee_id AND status='VERIFIED' AND valid_from<=v_date AND (valid_to IS NULL OR valid_to>v_date);
        SELECT NVL(MAX(attempt_no),0)+1 INTO v_attempt FROM PAYMENT_ITEM WHERE result_id=r.result_id;
        -- All previous attempts are terminal FAILED/CANCELLED. No retry of an uncertain PROCESSING transfer.
        INSERT INTO PAYMENT_ITEM(batch_id,run_id,result_id,employee_id,bank_account_id,attempt_no,transfer_reference,amount,
          bank_code_snapshot,account_ciphertext_snapshot,account_last4_snapshot,holder_name_snapshot)
        VALUES(p_batch,p_run,r.result_id,r.employee_id,v_bank.bank_account_id,v_attempt,
          'PR-'||TO_CHAR(r.result_id)||'-A'||TO_CHAR(v_attempt),r.net_amount,v_bank.bank_code,v_bank.account_ciphertext,v_bank.account_last4,v_bank.holder_name);
        v_count:=v_count+1;
      END IF;
    END LOOP;
    IF v_count=0 THEN RAISE_APPLICATION_ERROR(-20064,'No unpaid eligible results; retrieve existing batch instead'); END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYMENT_BATCH',p_batch,'CREATE',NULL,NULL,NULL,p_request_key);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO batch_call; RAISE;
  END;
  PROCEDURE mark_exported(p_actor NUMBER,p_batch NUMBER,p_document NUMBER,p_sha256 VARCHAR2) IS v_b PAYMENT_BATCH%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT export_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_b FROM PAYMENT_BATCH WHERE batch_id=p_batch FOR UPDATE NOWAIT;
    IF v_b.status IN ('EXPORTED','SENT') THEN
      IF v_b.export_sha256=p_sha256 AND v_b.export_document_id=p_document THEN RETURN; END IF;
      RAISE_APPLICATION_ERROR(-20065,'Batch already exported; download same document');
    END IF;
    IF v_b.status<>'CREATED' OR LENGTH(p_sha256)<>64 OR p_sha256 IS NULL THEN RAISE_APPLICATION_ERROR(-20066,'Invalid export state/hash'); END IF;
    SELECT COUNT(*) INTO v_n FROM DOCUMENT_FILE WHERE document_id=p_document AND sha256=p_sha256 AND uploaded_by=p_actor;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20067,'Export document/hash/owner mismatch'); END IF;
    UPDATE PAYMENT_BATCH SET status='EXPORTED',export_document_id=p_document,export_sha256=p_sha256,exported_at=SYSTIMESTAMP WHERE batch_id=p_batch;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYMENT_BATCH',p_batch,'EXPORT');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO export_call; RAISE;
  END;
  PROCEDURE mark_sent(p_actor NUMBER,p_batch NUMBER) IS v_b PAYMENT_BATCH%ROWTYPE;
  BEGIN
    SAVEPOINT sent_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_b FROM PAYMENT_BATCH WHERE batch_id=p_batch FOR UPDATE NOWAIT;
    IF v_b.status='SENT' THEN RETURN; END IF;
    IF v_b.status<>'EXPORTED' THEN RAISE_APPLICATION_ERROR(-20068,'Export first'); END IF;
    UPDATE PAYMENT_BATCH SET status='SENT' WHERE batch_id=p_batch;
    UPDATE PAYMENT_ITEM SET status='PROCESSING' WHERE batch_id=p_batch AND status='READY';
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYMENT_BATCH',p_batch,'SENT');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO sent_call; RAISE;
  END;
  PROCEDURE apply_recon_line(p_actor NUMBER,p_line NUMBER) IS v_l BANK_RECON_LINE%ROWTYPE;v_i PAYMENT_ITEM%ROWTYPE; v_n NUMBER;
  BEGIN
    SAVEPOINT recon_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_l FROM BANK_RECON_LINE WHERE recon_line_id=p_line FOR UPDATE NOWAIT;
    IF v_l.match_status='MATCHED' THEN RETURN; END IF;
    BEGIN SELECT * INTO v_i FROM PAYMENT_ITEM WHERE transfer_reference=v_l.transfer_reference FOR UPDATE NOWAIT;
    EXCEPTION WHEN NO_DATA_FOUND THEN UPDATE BANK_RECON_LINE SET match_status='UNMATCHED' WHERE recon_line_id=p_line;RETURN; END;
    IF v_l.reported_amount<>v_i.amount THEN UPDATE BANK_RECON_LINE SET payment_item_id=v_i.payment_item_id,match_status='AMOUNT_MISMATCH' WHERE recon_line_id=p_line;RETURN; END IF;
    SELECT COUNT(*) INTO v_n FROM PAYMENT_BATCH WHERE batch_id=v_i.batch_id AND status='SENT';
    IF v_n<>1 THEN UPDATE BANK_RECON_LINE SET payment_item_id=v_i.payment_item_id,match_status='CONFLICT' WHERE recon_line_id=p_line;RETURN; END IF;
    IF v_i.status IN ('FAILED','CANCELLED') OR (v_i.status='SUCCEEDED' AND (v_l.bank_status<>'SUCCEEDED' OR v_l.bank_transaction_id<>v_i.bank_transaction_id)) THEN
      UPDATE BANK_RECON_LINE SET payment_item_id=v_i.payment_item_id,match_status='CONFLICT' WHERE recon_line_id=p_line;RETURN;
    END IF;
    SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE bank_code_snapshot=v_i.bank_code_snapshot AND bank_transaction_id=v_l.bank_transaction_id AND payment_item_id<>v_i.payment_item_id;
    IF v_n>0 THEN UPDATE BANK_RECON_LINE SET payment_item_id=v_i.payment_item_id,match_status='CONFLICT' WHERE recon_line_id=p_line;RETURN; END IF;
    IF v_i.status<>'SUCCEEDED' THEN
      UPDATE PAYMENT_ITEM SET status=v_l.bank_status,
        bank_transaction_id=CASE WHEN v_l.bank_status='SUCCEEDED' THEN v_l.bank_transaction_id ELSE NULL END,
        confirmed_at=CASE WHEN v_l.bank_status IN ('SUCCEEDED','FAILED') THEN SYSTIMESTAMP ELSE NULL END,
        failure_reason=CASE WHEN v_l.bank_status='FAILED' THEN v_l.failure_reason ELSE NULL END WHERE payment_item_id=v_i.payment_item_id;
    END IF;
    UPDATE BANK_RECON_LINE SET payment_item_id=v_i.payment_item_id,match_status='MATCHED' WHERE recon_line_id=p_line;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYMENT_ITEM',v_i.payment_item_id,'RECONCILE','Evidence line '||p_line);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO recon_call; RAISE;
  END;
  PROCEDURE close_period(p_actor NUMBER,p_period NUMBER) IS v_p PAYROLL_PERIOD%ROWTYPE;v_r NUMBER;v_n NUMBER;
  BEGIN
    SAVEPOINT close_call;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'DIRECTOR');PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_p FROM PAYROLL_PERIOD WHERE period_id=p_period FOR UPDATE NOWAIT;
    IF v_p.period_status='CLOSED' THEN RETURN; END IF;
    SELECT run_id INTO v_r FROM PAYROLL_RUN WHERE period_id=p_period AND status='APPROVED';
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RESULT r WHERE r.run_id=v_r AND r.net_amount>0
      AND NOT EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.result_id=r.result_id AND i.status='SUCCEEDED');
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20069,'Unpaid results remain'); END IF;
    SELECT COUNT(*) INTO v_n FROM BANK_RECON_LINE l JOIN PAYMENT_ITEM i ON i.transfer_reference=l.transfer_reference
      WHERE i.run_id=v_r AND l.match_status IN ('AMOUNT_MISMATCH','CONFLICT');
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20070,'Reconciliation conflicts require review'); END IF;
    UPDATE PAYROLL_PERIOD SET period_status='CLOSED' WHERE period_id=p_period;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_PERIOD',p_period,'CLOSE');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO close_call; RAISE;
  END;
  PROCEDURE export_rows(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR) IS v_n NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');
    SELECT COUNT(*) INTO v_n FROM PAYMENT_BATCH WHERE batch_id=p_batch AND status IN ('CREATED','EXPORTED','SENT');
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20071,'Batch missing or cancelled'); END IF;
    OPEN p_rows FOR SELECT transfer_reference,bank_code_snapshot,account_ciphertext_snapshot,holder_name_snapshot,amount
      FROM PAYMENT_ITEM WHERE batch_id=p_batch ORDER BY payment_item_id;
    -- API decrypts only here and renders a bank-format file; it never returns full accounts to ordinary browser tables.
  END;
END;
/
CREATE OR REPLACE PACKAGE PKG_PAYROLL_READ AUTHID DEFINER AS
  PROCEDURE my_payslips(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE my_payslip_items(p_actor NUMBER,p_result NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE management_summary(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
END;
/
CREATE OR REPLACE PACKAGE BODY PKG_PAYROLL_READ AS
  PROCEDURE my_payslips(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS v_e NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'EMPLOYEE');
    SELECT employee_id INTO v_e FROM APP_USER WHERE user_id=p_actor;
    IF v_e IS NULL THEN RAISE_APPLICATION_ERROR(-20072,'Employee link missing'); END IF;
    OPEN p_rows FOR SELECT r.result_id,p.period_start,r.gross_amount,r.employee_insurance,r.pit_amount,r.other_deduction,r.net_amount,s.issued_at,
      CASE WHEN r.net_amount=0 THEN 'NO_TRANSFER_NEEDED' WHEN EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.result_id=r.result_id AND i.status='SUCCEEDED') THEN 'PAID'
        WHEN EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.result_id=r.result_id AND i.status IN ('READY','PROCESSING')) THEN 'PROCESSING' ELSE 'UNPAID' END payment_status
      FROM PAYROLL_RESULT r JOIN PAYSLIP s ON s.result_id=r.result_id JOIN PAYROLL_RUN u ON u.run_id=r.run_id JOIN PAYROLL_PERIOD p ON p.period_id=u.period_id
      WHERE r.employee_id=v_e AND u.status='APPROVED' ORDER BY p.period_start DESC;
  END;
  PROCEDURE my_payslip_items(p_actor NUMBER,p_result NUMBER,p_rows OUT SYS_REFCURSOR) IS v_n NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'EMPLOYEE');
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RESULT r JOIN PAYSLIP s ON s.result_id=r.result_id JOIN APP_USER u ON u.employee_id=r.employee_id
      WHERE u.user_id=p_actor AND r.result_id=p_result;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20073,'Payslip missing or belongs to another employee'); END IF;
    OPEN p_rows FOR SELECT component_code_snapshot,kind_snapshot,source_date,amount,taxable_amount,quantity,unit_rate,multiplier,formula_snapshot
      FROM PAYROLL_ITEM WHERE result_id=p_result ORDER BY item_id;
  END;
  PROCEDURE management_summary(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u JOIN USER_ROLE ur ON ur.user_id=u.user_id JOIN APP_ROLE r ON r.role_id=ur.role_id
      WHERE u.user_id=p_actor AND u.is_active='Y' AND r.role_code IN ('PAYROLL','DIRECTOR');
    IF v_n=0 THEN RAISE_APPLICATION_ERROR(-20074,'No management report permission'); END IF;
    OPEN p_rows FOR SELECT p.period_start,u.run_id,u.version_no,u.status,COUNT(r.result_id) employee_count,
      NVL(SUM(r.gross_amount),0) gross,NVL(SUM(r.net_amount),0) net,NVL(SUM(r.employer_insurance),0) company_insurance,
      NVL(SUM(r.gross_amount+r.employer_insurance),0) company_payroll_cost
      FROM PAYROLL_RUN u JOIN PAYROLL_PERIOD p ON p.period_id=u.period_id LEFT JOIN PAYROLL_RESULT r ON r.run_id=u.run_id
      GROUP BY p.period_start,u.run_id,u.version_no,u.status ORDER BY p.period_start DESC,u.version_no DESC;
  END;
END;
/
