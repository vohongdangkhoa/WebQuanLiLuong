-- Install as PAYROLL_APP after 02..10. Public API never receives table privileges.
CREATE OR REPLACE PACKAGE PKG_FINANCE_PORTAL AUTHID DEFINER AS
  PROCEDURE list_periods(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE create_period(p_actor NUMBER,p_start DATE,p_period OUT NUMBER);
  PROCEDURE list_runs(p_actor NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE run_period(p_actor NUMBER,p_run NUMBER,p_period OUT NUMBER);
  PROCEDURE withdraw_run(p_actor NUMBER,p_run NUMBER,p_reason VARCHAR2);
  PROCEDURE list_results(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE list_errors(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE list_items(p_actor NUMBER,p_result NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE list_batches(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE list_payment_items(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE list_recon(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE recon_context(p_actor NUMBER,p_batch NUMBER,p_hash VARCHAR2);
  PROCEDURE reports(p_actor NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR);
END PKG_FINANCE_PORTAL;
/
CREATE OR REPLACE PACKAGE BODY PKG_FINANCE_PORTAL AS
  PROCEDURE require_reader(p_actor NUMBER,p_allow_hr NUMBER DEFAULT 0) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM APP_USER u JOIN USER_ROLE ur ON ur.user_id=u.user_id
      JOIN APP_ROLE r ON r.role_id=ur.role_id WHERE u.user_id=p_actor AND u.is_active='Y'
      AND (r.role_code IN ('PAYROLL','DIRECTOR') OR (p_allow_hr=1 AND r.role_code='HR'));
    IF v_n=0 THEN RAISE_APPLICATION_ERROR(-20002,'Finance permission required'); END IF;
  END;
  PROCEDURE require_run(p_run NUMBER) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RUN WHERE run_id=p_run;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20601,'Payroll run not found'); END IF;
  END;
  PROCEDURE require_batch(p_batch NUMBER) IS v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM PAYMENT_BATCH WHERE batch_id=p_batch;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20601,'Payment batch not found'); END IF;
  END;
  PROCEDURE list_periods(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor,1);
    OPEN p_rows FOR SELECT period_id,period_start,period_end,period_status,timesheet_status,input_version,locked_at
      FROM PAYROLL_PERIOD ORDER BY period_start DESC;
  END;
  PROCEDURE create_period(p_actor NUMBER,p_start DATE,p_period OUT NUMBER) IS
  BEGIN
    SAVEPOINT finance_period;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    IF p_start IS NULL OR p_start<>TRUNC(p_start,'MM') THEN RAISE_APPLICATION_ERROR(-20602,'First day of month required'); END IF;
    INSERT INTO PAYROLL_PERIOD(period_start,period_end) VALUES(p_start,ADD_MONTHS(p_start,1)) RETURNING period_id INTO p_period;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_PERIOD',p_period,'CREATE');
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN ROLLBACK TO finance_period;RAISE_APPLICATION_ERROR(-20603,'Period already exists');
    WHEN OTHERS THEN ROLLBACK TO finance_period;RAISE;
  END;
  PROCEDURE list_runs(p_actor NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);
    OPEN p_rows FOR SELECT u.run_id,u.period_id,p.period_start,u.version_no,u.status,u.input_version,u.policy_id,u.calculated_by,
      u.created_at,u.finished_at,u.success_count,u.error_count,
      NVL((SELECT SUM(r.gross_amount) FROM PAYROLL_RESULT r WHERE r.run_id=u.run_id),0) gross_amount,
      NVL((SELECT SUM(r.net_amount) FROM PAYROLL_RESULT r WHERE r.run_id=u.run_id),0) net_amount,
      NVL((SELECT SUM(r.employer_insurance) FROM PAYROLL_RESULT r WHERE r.run_id=u.run_id),0) employer_insurance
      FROM PAYROLL_RUN u JOIN PAYROLL_PERIOD p ON p.period_id=u.period_id
      WHERE p_period IS NULL OR u.period_id=p_period ORDER BY p.period_start DESC,u.version_no DESC;
  END;
  PROCEDURE run_period(p_actor NUMBER,p_run NUMBER,p_period OUT NUMBER) IS
  BEGIN
    require_reader(p_actor);require_run(p_run);
    SELECT period_id INTO p_period FROM PAYROLL_RUN WHERE run_id=p_run;
  END;
  PROCEDURE withdraw_run(p_actor NUMBER,p_run NUMBER,p_reason VARCHAR2) IS
    v_run PAYROLL_RUN%ROWTYPE;
    v_period_status PAYROLL_PERIOD.period_status%TYPE;
  BEGIN
    SAVEPOINT finance_withdraw;
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');
    PKG_PAYROLL_INTERNAL.lock_inputs;
    IF TRIM(p_reason) IS NULL OR LENGTH(TRIM(p_reason)) NOT BETWEEN 3 AND 1000 THEN
      RAISE_APPLICATION_ERROR(-20607,'Withdrawal reason must be 3 to 1000 characters');
    END IF;
    SELECT * INTO v_run FROM PAYROLL_RUN WHERE run_id=p_run FOR UPDATE NOWAIT;
    SELECT period_status INTO v_period_status FROM PAYROLL_PERIOD WHERE period_id=v_run.period_id FOR UPDATE NOWAIT;
    IF v_run.status<>'PENDING_APPROVAL' OR v_period_status<>'OPEN' THEN
      RAISE_APPLICATION_ERROR(-20606,'Only pending approval runs in open periods may be withdrawn');
    END IF;
    UPDATE PAYROLL_RUN SET status='CANCELLED' WHERE run_id=p_run;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'PAYROLL_RUN',p_run,'WITHDRAW',TRIM(p_reason));
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO finance_withdraw; RAISE;
  END;
  PROCEDURE list_results(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);require_run(p_run);
    OPEN p_rows FOR SELECT r.result_id,r.run_id,r.employee_id,r.employee_code_snapshot employee_code,
      r.employee_name_snapshot employee_name,r.department_name_snapshot department_name,r.gross_amount,r.employee_insurance,
      r.pit_amount,r.other_deduction,r.net_amount,r.employer_insurance,r.taxable_income,r.dependent_count,
      CASE WHEN r.net_amount=0 THEN 'NO_TRANSFER_NEEDED'
        WHEN EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.result_id=r.result_id AND i.status='SUCCEEDED') THEN 'PAID'
        WHEN EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.result_id=r.result_id AND i.status IN ('READY','PROCESSING')) THEN 'PROCESSING'
        ELSE 'UNPAID' END payment_status FROM PAYROLL_RESULT r WHERE r.run_id=p_run ORDER BY r.employee_code_snapshot;
  END;
  PROCEDURE list_errors(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);require_run(p_run);
    OPEN p_rows FOR SELECT x.error_id,x.employee_id,e.employee_code,e.full_name employee_name,x.error_code,x.error_message,x.created_at
      FROM PAYROLL_ERROR x JOIN EMPLOYEE e ON e.employee_id=x.employee_id WHERE x.run_id=p_run ORDER BY e.employee_code;
  END;
  PROCEDURE list_items(p_actor NUMBER,p_result NUMBER,p_rows OUT SYS_REFCURSOR) IS v_n NUMBER;
  BEGIN
    require_reader(p_actor);
    SELECT COUNT(*) INTO v_n FROM PAYROLL_RESULT WHERE result_id=p_result;
    IF v_n<>1 THEN RAISE_APPLICATION_ERROR(-20601,'Payroll result not found'); END IF;
    OPEN p_rows FOR SELECT item_id,component_code_snapshot component_code,kind_snapshot kind,department_name_snapshot department_name,
      source_type,source_date,amount,taxable_amount,quantity,unit_rate,multiplier,formula_snapshot formula
      FROM PAYROLL_ITEM WHERE result_id=p_result ORDER BY item_id;
  END;
  PROCEDURE list_batches(p_actor NUMBER,p_run NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);
    OPEN p_rows FOR SELECT b.batch_id,b.run_id,p.period_start,b.status,b.created_by,b.created_at,b.export_document_id,b.export_sha256,b.exported_at,
      (SELECT COUNT(*) FROM PAYMENT_ITEM i WHERE i.batch_id=b.batch_id) item_count,
      NVL((SELECT SUM(i.amount) FROM PAYMENT_ITEM i WHERE i.batch_id=b.batch_id),0) total_amount,
      NVL((SELECT SUM(i.amount) FROM PAYMENT_ITEM i WHERE i.batch_id=b.batch_id AND i.status='SUCCEEDED'),0) paid_amount,
      NVL((SELECT SUM(i.amount) FROM PAYMENT_ITEM i WHERE i.batch_id=b.batch_id AND i.status IN ('READY','PROCESSING')),0) processing_amount,
      NVL((SELECT SUM(i.amount) FROM PAYMENT_ITEM i WHERE i.batch_id=b.batch_id AND i.status='FAILED'),0) failed_amount
      FROM PAYMENT_BATCH b JOIN PAYROLL_RUN u ON u.run_id=b.run_id JOIN PAYROLL_PERIOD p ON p.period_id=u.period_id
      WHERE p_run IS NULL OR b.run_id=p_run ORDER BY b.batch_id DESC;
  END;
  PROCEDURE list_payment_items(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);require_batch(p_batch);
    OPEN p_rows FOR SELECT i.payment_item_id,i.result_id,i.employee_id,r.employee_code_snapshot employee_code,
      r.employee_name_snapshot employee_name,i.transfer_reference,i.attempt_no,i.amount,i.bank_code_snapshot bank_code,
      i.account_last4_snapshot account_last4,i.holder_name_snapshot holder_name,i.status,i.bank_transaction_id,i.confirmed_at,i.failure_reason
      FROM PAYMENT_ITEM i JOIN PAYROLL_RESULT r ON r.result_id=i.result_id WHERE i.batch_id=p_batch ORDER BY i.payment_item_id;
  END;
  PROCEDURE list_recon(p_actor NUMBER,p_batch NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);require_batch(p_batch);
    OPEN p_rows FOR SELECT l.recon_line_id,l.recon_import_id import_id,l.line_no,l.transfer_reference,l.reported_amount,l.bank_status,
      l.bank_transaction_id,l.failure_reason,l.match_status FROM BANK_RECON_LINE l
      WHERE EXISTS(SELECT 1 FROM PAYMENT_ITEM i WHERE i.batch_id=p_batch AND i.transfer_reference=l.transfer_reference)
      ORDER BY l.recon_import_id DESC,l.line_no;
  END;
  PROCEDURE recon_context(p_actor NUMBER,p_batch NUMBER,p_hash VARCHAR2) IS v_status PAYMENT_BATCH.status%TYPE;v_n NUMBER;
  BEGIN
    PKG_PAYROLL_INTERNAL.require_role(p_actor,'PAYROLL');PKG_PAYROLL_INTERNAL.lock_inputs;
    BEGIN SELECT status INTO v_status FROM PAYMENT_BATCH WHERE batch_id=p_batch FOR UPDATE NOWAIT;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20601,'Payment batch not found');END;
    IF v_status<>'SENT' THEN RAISE_APPLICATION_ERROR(-20605,'Reconcile only sent batch'); END IF;
    SELECT COUNT(*) INTO v_n FROM BANK_RECON_IMPORT WHERE file_sha256=p_hash;
    IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20604,'Reconciliation file already imported');END IF;
  END;
  PROCEDURE reports(p_actor NUMBER,p_period NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    require_reader(p_actor);
    OPEN p_rows FOR SELECT p.period_id,p.period_start,u.run_id,r.department_id_snapshot department_id,
      r.department_name_snapshot department_name,COUNT(*) employee_count,SUM(r.gross_amount) gross_amount,SUM(r.net_amount) net_amount,
      SUM(r.employee_insurance) employee_insurance,SUM(r.pit_amount) pit_amount,SUM(r.employer_insurance) employer_insurance,
      SUM(r.gross_amount+r.employer_insurance) company_cost
      FROM PAYROLL_RUN u JOIN PAYROLL_PERIOD p ON p.period_id=u.period_id JOIN PAYROLL_RESULT r ON r.run_id=u.run_id
      WHERE u.status='APPROVED' AND (p_period IS NULL OR p.period_id=p_period)
      GROUP BY p.period_id,p.period_start,u.run_id,r.department_id_snapshot,r.department_name_snapshot
      ORDER BY p.period_start DESC,r.department_name_snapshot;
  END;
END PKG_FINANCE_PORTAL;
/
GRANT EXECUTE ON PKG_FINANCE_PORTAL TO PAYROLL_API;
