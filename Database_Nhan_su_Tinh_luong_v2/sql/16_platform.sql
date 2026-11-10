-- Additive upgrade for existing PAYROLL_APP. No data reset or demo inserts.
CREATE OR REPLACE PACKAGE PKG_PLATFORM AUTHID DEFINER AS
  PROCEDURE dashboard(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE notifications(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE bank_accounts(p_actor NUMBER,p_employee_id NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE save_bank(p_actor NUMBER,p_employee_id NUMBER,p_bank_code VARCHAR2,p_cipher VARCHAR2,
    p_last4 VARCHAR2,p_hmac VARCHAR2,p_holder VARCHAR2,p_from DATE,p_id OUT NUMBER);
  PROCEDURE decide_bank(p_actor NUMBER,p_id NUMBER,p_decision VARCHAR2);
  PROCEDURE change_password(p_actor NUMBER,p_old_hash VARCHAR2,p_version NUMBER,
    p_new_hash VARCHAR2,p_updated OUT NUMBER);
  PROCEDURE audit_rows(p_actor NUMBER,p_rows OUT SYS_REFCURSOR);
  PROCEDURE register_file(p_actor NUMBER,p_key VARCHAR2,p_name VARCHAR2,p_mime VARCHAR2,p_size NUMBER,p_sha VARCHAR2,p_id OUT NUMBER);
  PROCEDURE document_rows(p_actor NUMBER,p_id NUMBER,p_rows OUT SYS_REFCURSOR);
END PKG_PLATFORM;
/
CREATE OR REPLACE PACKAGE BODY PKG_PLATFORM AS
  FUNCTION own_employee(p_actor NUMBER) RETURN NUMBER IS v_id NUMBER;
  BEGIN
    SELECT employee_id INTO v_id FROM APP_USER WHERE user_id=p_actor AND is_active='Y';
    RETURN v_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20002,'Inactive account');
  END;
  FUNCTION has_role(p_actor NUMBER,p_roles VARCHAR2) RETURN BOOLEAN IS v_n NUMBER;v_id NUMBER;
  BEGIN
    v_id:=own_employee(p_actor);
    SELECT COUNT(*) INTO v_n FROM USER_ROLE ur JOIN APP_ROLE r ON r.role_id=ur.role_id
    WHERE ur.user_id=p_actor AND INSTR(','||p_roles||',',','||r.role_code||',')>0;
    RETURN v_n>0;
  END;
  PROCEDURE dashboard(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS v_own NUMBER;v_manager NUMBER:=0;v_finance NUMBER:=0;
  BEGIN
    v_own:=own_employee(p_actor);
    IF has_role(p_actor,'HR,PAYROLL,DIRECTOR') THEN v_manager:=1; END IF;
    IF has_role(p_actor,'PAYROLL,DIRECTOR') THEN v_finance:=1; END IF;
    OPEN p_rows FOR SELECT
      (SELECT COUNT(*) FROM EMPLOYEE WHERE v_manager=1 OR employee_id=v_own) employee_count,
      (SELECT COUNT(*) FROM EMPLOYEE WHERE status='ACTIVE' AND (v_manager=1 OR employee_id=v_own)) active_employee_count,
      (SELECT COUNT(*) FROM PAYROLL_PERIOD WHERE period_status='OPEN' AND v_manager=1) open_period_count,
      ((SELECT COUNT(*) FROM LEAVE_REQUEST WHERE status='PENDING' AND (v_manager=1 OR employee_id=v_own))+
       (SELECT COUNT(*) FROM OVERTIME_REQUEST WHERE status='PENDING' AND (v_manager=1 OR employee_id=v_own))) pending_request_count,
      (SELECT SUM(r.net_amount) FROM PAYROLL_RESULT r JOIN PAYROLL_RUN u ON u.run_id=r.run_id
       WHERE u.run_id=(SELECT MAX(run_id) FROM PAYROLL_RUN WHERE status='APPROVED')
       AND (v_finance=1 OR (v_manager=0 AND r.employee_id=v_own))) latest_payroll_net,
      (SELECT TO_CHAR(MAX(p.period_start),'MM/YYYY') FROM PAYROLL_PERIOD p JOIN PAYROLL_RUN u ON u.period_id=p.period_id
       WHERE u.status='APPROVED' AND (v_finance=1 OR v_manager=0)) latest_period_name
    FROM dual;
  END;
  PROCEDURE notifications(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS v_id NUMBER;
  BEGIN
    v_id:=own_employee(p_actor);
    OPEN p_rows FOR SELECT title,body detail,created_at occurred_at FROM APP_NOTIFICATION
      WHERE user_id=p_actor ORDER BY created_at DESC,notification_id DESC FETCH FIRST 8 ROWS ONLY;
  END;
  PROCEDURE bank_accounts(p_actor NUMBER,p_employee_id NUMBER,p_rows OUT SYS_REFCURSOR) IS
    v_own NUMBER;v_manager NUMBER:=0;
  BEGIN
    v_own:=own_employee(p_actor);
    IF has_role(p_actor,'HR,PAYROLL,DIRECTOR') THEN v_manager:=1;
    ELSIF v_own IS NULL OR (p_employee_id IS NOT NULL AND p_employee_id<>v_own) THEN
      RAISE_APPLICATION_ERROR(-20002,'Bank account ownership');
    END IF;
    OPEN p_rows FOR SELECT b.bank_account_id,b.employee_id,e.employee_code,e.full_name,
      b.bank_code,b.account_last4,b.holder_name,b.valid_from,b.valid_to,b.status,b.created_by,b.verified_by,b.verified_at
      FROM EMPLOYEE_BANK_ACCOUNT b JOIN EMPLOYEE e ON e.employee_id=b.employee_id
      WHERE (p_employee_id IS NULL OR b.employee_id=p_employee_id) AND (v_manager=1 OR b.employee_id=v_own)
      ORDER BY e.employee_code,b.valid_from DESC,b.bank_account_id DESC;
  END;
  PROCEDURE save_bank(p_actor NUMBER,p_employee_id NUMBER,p_bank_code VARCHAR2,p_cipher VARCHAR2,
    p_last4 VARCHAR2,p_hmac VARCHAR2,p_holder VARCHAR2,p_from DATE,p_id OUT NUMBER) IS
    v_employee EMPLOYEE%ROWTYPE;v_own NUMBER;
  BEGIN
    SAVEPOINT platform_bank_save;
    v_own:=own_employee(p_actor);
    IF NOT has_role(p_actor,'HR') AND (NOT has_role(p_actor,'EMPLOYEE') OR v_own IS NULL OR v_own<>p_employee_id) THEN
      RAISE_APPLICATION_ERROR(-20002,'Bank account ownership'); END IF;
    PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_employee FROM EMPLOYEE WHERE employee_id=p_employee_id FOR UPDATE NOWAIT;
    IF p_from IS NULL OR p_from<>TRUNC(p_from) OR p_from<v_employee.hire_date OR
       (v_employee.termination_date IS NOT NULL AND p_from>v_employee.termination_date) THEN
      RAISE_APPLICATION_ERROR(-20901,'Invalid bank effective date'); END IF;
    IF LENGTH(TRIM(p_bank_code)) NOT BETWEEN 2 AND 30 OR p_cipher IS NULL OR LENGTH(p_cipher)>2000
      OR LENGTH(p_last4)<>4 OR p_hmac IS NULL OR TRIM(p_holder) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20902,'Invalid bank details'); END IF;
    INSERT INTO EMPLOYEE_BANK_ACCOUNT(employee_id,bank_code,account_ciphertext,account_last4,
      account_hmac,holder_name,valid_from,status,created_by)
    VALUES(p_employee_id,UPPER(TRIM(p_bank_code)),p_cipher,p_last4,p_hmac,TRIM(p_holder),p_from,'PENDING',p_actor)
    RETURNING bank_account_id INTO p_id;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE_BANK_ACCOUNT',p_id,'CREATE');
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO platform_bank_save;RAISE;
  END;
  PROCEDURE decide_bank(p_actor NUMBER,p_id NUMBER,p_decision VARCHAR2) IS v_bank EMPLOYEE_BANK_ACCOUNT%ROWTYPE;
  BEGIN
    SAVEPOINT platform_bank_decide;
    IF NOT has_role(p_actor,'PAYROLL,DIRECTOR') THEN RAISE_APPLICATION_ERROR(-20002,'Bank verifier role'); END IF;
    PKG_PAYROLL_INTERNAL.lock_inputs;
    SELECT * INTO v_bank FROM EMPLOYEE_BANK_ACCOUNT WHERE bank_account_id=p_id FOR UPDATE NOWAIT;
    IF v_bank.status<>'PENDING' THEN RAISE_APPLICATION_ERROR(-20903,'Bank account is not pending'); END IF;
    IF v_bank.created_by=p_actor THEN RAISE_APPLICATION_ERROR(-20904,'Maker cannot verify own bank account'); END IF;
    IF p_decision='REJECT' THEN
      UPDATE EMPLOYEE_BANK_ACCOUNT SET status='REJECTED' WHERE bank_account_id=p_id;
    ELSIF p_decision='VERIFY' THEN
      FOR old_bank IN (SELECT bank_account_id,valid_from FROM EMPLOYEE_BANK_ACCOUNT
        WHERE employee_id=v_bank.employee_id AND status='VERIFIED'
        AND valid_from<NVL(v_bank.valid_to,DATE '9999-12-31')
        AND v_bank.valid_from<NVL(valid_to,DATE '9999-12-31') FOR UPDATE NOWAIT) LOOP
        IF old_bank.valid_from>=v_bank.valid_from THEN RAISE_APPLICATION_ERROR(-20905,'New bank version must start after old version'); END IF;
        UPDATE EMPLOYEE_BANK_ACCOUNT SET valid_to=v_bank.valid_from WHERE bank_account_id=old_bank.bank_account_id;
      END LOOP;
      UPDATE EMPLOYEE_BANK_ACCOUNT SET status='VERIFIED',verified_by=p_actor,verified_at=SYSTIMESTAMP WHERE bank_account_id=p_id;
      -- Bank changes affect only future payment snapshots, not calculated payroll inputs.
    ELSE RAISE_APPLICATION_ERROR(-20906,'Decision must be VERIFY or REJECT'); END IF;
    PKG_PAYROLL_INTERNAL.audit_event(p_actor,'EMPLOYEE_BANK_ACCOUNT',p_id,p_decision);
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO platform_bank_decide;RAISE;
  END;
  PROCEDURE change_password(p_actor NUMBER,p_old_hash VARCHAR2,p_version NUMBER,p_new_hash VARCHAR2,p_updated OUT NUMBER) IS
  BEGIN
    SAVEPOINT platform_password;
    IF p_new_hash IS NULL OR LENGTH(p_new_hash)>500 THEN RAISE_APPLICATION_ERROR(-20907,'Invalid password hash'); END IF;
    UPDATE APP_USER SET password_hash=p_new_hash,security_version=security_version+1
      WHERE user_id=p_actor AND is_active='Y' AND password_hash=p_old_hash AND security_version=p_version;
    p_updated:=SQL%ROWCOUNT;
    IF p_updated=1 THEN PKG_PAYROLL_INTERNAL.audit_event(p_actor,'APP_USER',p_actor,'CHANGE_PASSWORD'); END IF;
  EXCEPTION WHEN OTHERS THEN ROLLBACK TO platform_password;RAISE;
  END;
  PROCEDURE register_file(p_actor NUMBER,p_key VARCHAR2,p_name VARCHAR2,p_mime VARCHAR2,p_size NUMBER,p_sha VARCHAR2,p_id OUT NUMBER) IS v_own NUMBER;
  BEGIN
    v_own:=own_employee(p_actor);
    IF NOT REGEXP_LIKE(p_key,'^uploads/[a-f0-9]{32}$') OR p_size NOT BETWEEN 1 AND 10485760
      OR LENGTH(p_sha)<>64 OR p_mime NOT IN ('application/pdf','image/png','image/jpeg') THEN
      RAISE_APPLICATION_ERROR(-20908,'Invalid uploaded document'); END IF;
    PKG_REQUESTS.register_document(p_actor,p_key,p_name,p_mime,p_size,p_sha,p_id);
  END;
  PROCEDURE document_rows(p_actor NUMBER,p_id NUMBER,p_rows OUT SYS_REFCURSOR) IS v_own NUMBER;v_manager NUMBER:=0;
  BEGIN
    v_own:=own_employee(p_actor);
    IF has_role(p_actor,'HR,DIRECTOR') THEN v_manager:=1; END IF;
    OPEN p_rows FOR SELECT document_id,storage_key,original_name,mime_type,size_bytes,sha256
      FROM DOCUMENT_FILE WHERE document_id=p_id AND storage_key LIKE 'uploads/%'
      AND (uploaded_by=p_actor OR v_manager=1);
  END;
  PROCEDURE audit_rows(p_actor NUMBER,p_rows OUT SYS_REFCURSOR) IS
  BEGIN
    IF NOT has_role(p_actor,'HR,PAYROLL,DIRECTOR') THEN RAISE_APPLICATION_ERROR(-20002,'Audit role'); END IF;
    OPEN p_rows FOR SELECT a.audit_id,u.username actor_name,a.entity_type,a.entity_id,a.action,a.reason,a.created_at
      FROM AUDIT_LOG a LEFT JOIN APP_USER u ON u.user_id=a.actor_id
      ORDER BY a.created_at DESC,a.audit_id DESC FETCH FIRST 300 ROWS ONLY;
  END;
END PKG_PLATFORM;
/
GRANT EXECUTE ON PKG_PLATFORM TO PAYROLL_API;
