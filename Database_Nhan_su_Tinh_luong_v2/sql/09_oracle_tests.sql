SET DEFINE OFF;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
-- Run only after 08_demo_data.sql on the dedicated demo schema.
-- Each expected failure validates its exact error code. All test writes roll back.
DECLARE
  v_run NUMBER;v_again NUMBER;v_run2 NUMBER;v_batch NUMBER;v_retry NUMBER;v_doc NUMBER;v_imp NUMBER;v_line NUMBER;v_n NUMBER;v_gross NUMBER;v_net NUMBER;v_ver NUMBER;
  PROCEDURE ok(p BOOLEAN,p_msg VARCHAR2) IS BEGIN IF NOT p OR p IS NULL THEN RAISE_APPLICATION_ERROR(-20999,'FAIL '||p_msg);END IF;DBMS_OUTPUT.PUT_LINE('PASS '||p_msg);END;
  PROCEDURE fails(p_sql VARCHAR2,p_code NUMBER,p_msg VARCHAR2) IS v_c NUMBER:=0;
  BEGIN
    SAVEPOINT expected_failure;
    BEGIN EXECUTE IMMEDIATE p_sql;EXCEPTION WHEN OTHERS THEN v_c:=SQLCODE;END;
    ROLLBACK TO expected_failure;ok(v_c=p_code,p_msg||' expected '||p_code||' got '||v_c);
  END;
BEGIN
  SAVEPOINT suite_start;
  SELECT COUNT(*) INTO v_n FROM USER_ERRORS;ok(v_n=0,'all stored objects compile without errors');
  ok(PKG_PAYROLL_INTERNAL.bracket_tax(1,0)=0,'zero taxable income');
  ok(PKG_PAYROLL_INTERNAL.bracket_tax(1,5000000)=250000,'tax at first bracket boundary');
  ok(PKG_PAYROLL_INTERNAL.bracket_tax(1,12000000)=1150000,'progressive tax through three brackets');
  fails('INSERT INTO TIMESHEET_DAILY(period_id,employee_id,work_date,status) VALUES(1,1,DATE ''2026-09-01'',''VALID'')',-1,'duplicate daily timesheet');
  fails('INSERT INTO EMPLOYMENT_CONTRACT(employee_id,contract_no,valid_from,monthly_salary,insurance_base,calendar_id,created_by,approved_by,approved_at,status) VALUES(1,''BAD_OVERLAP'',DATE ''2026-09-10'',10000000,10000000,1,2,4,SYSTIMESTAMP,''APPROVED'')',-20118,'overlapping approved contract');
  fails('BEGIN PKG_HR_CORE.save_day(2,1,1,DATE ''2026-09-01'',481,0,0);END;',-20013,'excess daily paid minutes');
  fails('BEGIN PKG_HR_CORE.lock_timesheet(1,1);END;',-20002,'employee cannot lock HR timesheets');
  PKG_HR_CORE.lock_timesheet(2,1);
  fails('BEGIN PKG_HR_CORE.save_day(2,1,1,DATE ''2026-09-01'',480,0,0);END;',-20010,'locked timesheet cannot change');
  PKG_PAYROLL_CORE.calculate(3,1,'TEST-CALC-1',v_run);
  SELECT error_count INTO v_n FROM PAYROLL_RUN WHERE run_id=v_run;ok(v_n=0,'all three employees calculate');
  SELECT gross_amount,net_amount INTO v_gross,v_net FROM PAYROLL_RESULT WHERE run_id=v_run AND employee_id=1;
  ok(v_gross=14300000 AND v_net=12000000,'salary allowance insurance tax deduction arithmetic');
  SELECT gross_amount INTO v_gross FROM PAYROLL_RESULT WHERE run_id=v_run AND employee_id=2;ok(v_gross=18700000,'salary increase on September 16');
  SELECT gross_amount INTO v_gross FROM PAYROLL_RESULT WHERE run_id=v_run AND employee_id=3;ok(v_gross=5500000,'hire on September 16 prorated');
  PKG_PAYROLL_CORE.calculate(3,1,'TEST-CALC-1',v_again);ok(v_again=v_run,'idempotent calculation');
  fails('UPDATE PAYROLL_RESULT SET net_amount=net_amount WHERE run_id='||v_run,-20101,'completed result immutable before approval');
  -- Create a stale version by reopening, then correct and calculate V2.
  PKG_HR_CORE.reopen_timesheet(2,1,'Test input correction');
  PKG_HR_CORE.save_day(2,1,1,DATE '2026-09-01',240,0,0);
  PKG_HR_CORE.lock_timesheet(2,1);
  fails('BEGIN PKG_PAYROLL_CORE.submit_run(3,'||v_run||');END;',-20045,'stale V1 cannot be submitted');
  PKG_PAYROLL_CORE.calculate(3,1,'TEST-CALC-2',v_run2);
  SELECT version_no INTO v_ver FROM PAYROLL_RUN WHERE run_id=v_run2;ok(v_ver=2,'recalculation creates V2');
  SELECT net_amount INTO v_net FROM PAYROLL_RESULT WHERE run_id=v_run AND employee_id=1;ok(v_net=12000000,'V1 remains unchanged');
  PKG_PAYROLL_CORE.submit_run(3,v_run2);
  fails('BEGIN PKG_PAYROLL_CORE.decide_run(3,'||v_run2||',''APPROVE'');END;',-20049,'dual-role maker cannot approve own payroll');
  fails('BEGIN PKG_PAYROLL_CORE.decide_run(4,'||v_run2||',''REJECT'');END;',-20048,'reject requires reason');
  PKG_PAYROLL_CORE.decide_run(4,v_run2,'APPROVE');
  SELECT collected_amount INTO v_net FROM DEDUCTION_ACCOUNT WHERE deduction_account_id=1;ok(v_net=1000000,'deduction consumed once at approval');
  SELECT COUNT(*) INTO v_n FROM PAYSLIP s JOIN PAYROLL_RESULT r ON r.result_id=s.result_id WHERE r.run_id=v_run2;ok(v_n=3,'three payslips issued');
  SELECT result_id INTO v_n FROM PAYROLL_RESULT WHERE run_id=v_run2 AND employee_id=2;
  fails('DECLARE c SYS_REFCURSOR;BEGIN PKG_PAYROLL_READ.my_payslip_items(1,'||v_n||',c);END;',-20073,'employee cannot read another payslip');
  fails('BEGIN PKG_HR_CORE.reopen_timesheet(2,1,''bad reopen'');END;',-20023,'approved period cannot reopen');
  PKG_PAYMENT.create_batch(3,v_run2,'TEST-PAY-1',v_batch);
  PKG_PAYMENT.create_batch(3,v_run2,'TEST-PAY-1',v_again);ok(v_again=v_batch,'idempotent payment batch');
  fails('DECLARE x NUMBER;BEGIN PKG_PAYMENT.create_batch(3,'||v_run2||',''TEST-PAY-DUP'',x);END;',-20064,'reserved results prevent second batch');
  PKG_REQUESTS.register_document(3,'test/export1','bank-demo.csv','text/csv',100,RPAD('a',64,'a'),v_doc);
  PKG_PAYMENT.mark_exported(3,v_batch,v_doc,RPAD('a',64,'a'));
  SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE batch_id=v_batch AND status='SUCCEEDED';ok(v_n=0,'export is not payment confirmation');
  PKG_PAYMENT.mark_sent(3,v_batch);
  PKG_REQUESTS.register_document(3,'test/recon1','recon-demo.csv','text/csv',100,RPAD('b',64,'b'),v_doc);
  PKG_REQUESTS.register_recon(3,v_doc,RPAD('b',64,'b'),v_imp);
  FOR i IN (SELECT * FROM PAYMENT_ITEM WHERE batch_id=v_batch AND employee_id=1) LOOP
    SAVEPOINT mismatch_case;
    PKG_REQUESTS.add_recon_line(3,v_imp,99,i.transfer_reference,i.amount+1,'SUCCEEDED','TX-MISMATCH',NULL,v_line);
    PKG_PAYMENT.apply_recon_line(3,v_line);
    SELECT COUNT(*) INTO v_n FROM BANK_RECON_LINE WHERE recon_line_id=v_line AND match_status='AMOUNT_MISMATCH';ok(v_n=1,'wrong bank amount does not confirm payment');
    SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE payment_item_id=i.payment_item_id AND status='PROCESSING';ok(v_n=1,'mismatched transfer stays uncertain');
    ROLLBACK TO mismatch_case;
  END LOOP;
  FOR i IN (SELECT * FROM PAYMENT_ITEM WHERE batch_id=v_batch ORDER BY employee_id) LOOP
    PKG_REQUESTS.add_recon_line(3,v_imp,i.employee_id,i.transfer_reference,i.amount,
      CASE WHEN i.employee_id=3 THEN 'FAILED' ELSE 'SUCCEEDED' END,
      CASE WHEN i.employee_id=3 THEN NULL ELSE 'TX-DEMO-'||i.employee_id END,
      CASE WHEN i.employee_id=3 THEN 'Invalid destination demo' ELSE NULL END,v_line);
    PKG_PAYMENT.apply_recon_line(3,v_line);PKG_PAYMENT.apply_recon_line(3,v_line);
  END LOOP;
  SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE batch_id=v_batch AND status='SUCCEEDED';ok(v_n=2,'two matched success transfers');
  fails('BEGIN PKG_PAYMENT.close_period(4,1);END;',-20069,'failed transfer prevents closing');
  PKG_PAYMENT.create_batch(3,v_run2,'TEST-PAY-RETRY',v_retry);
  SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE batch_id=v_retry;ok(v_n=1,'only failed result retried');
  SELECT COUNT(*) INTO v_n FROM PAYMENT_ITEM WHERE batch_id=v_retry AND employee_id=3 AND attempt_no=2;ok(v_n=1,'retry has distinct reference and attempt');
  ROLLBACK TO suite_start;
  DBMS_OUTPUT.PUT_LINE('ALL TESTS PASSED. Test writes rolled back.');
EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;
END;
/
