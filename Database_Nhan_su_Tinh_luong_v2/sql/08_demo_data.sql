-- Fictional inputs only. The DEMO policy is NOT Vietnamese payroll legislation.
-- Hash placeholders cannot authenticate; create real ASP.NET Identity users in API later.
INSERT INTO APP_USER(user_id,username,password_hash) VALUES(1,'employee.demo','DEMO_DISABLED_HASH');
INSERT INTO APP_USER(user_id,username,password_hash) VALUES(2,'hr.demo','DEMO_DISABLED_HASH');
INSERT INTO APP_USER(user_id,username,password_hash) VALUES(3,'payroll.demo','DEMO_DISABLED_HASH');
INSERT INTO APP_USER(user_id,username,password_hash) VALUES(4,'director.demo','DEMO_DISABLED_HASH');
INSERT INTO USER_ROLE(user_id,role_id) VALUES(1,1);
INSERT INTO USER_ROLE(user_id,role_id) VALUES(2,2);
INSERT INTO USER_ROLE(user_id,role_id) VALUES(3,3);
INSERT INTO USER_ROLE(user_id,role_id) VALUES(4,4);
-- Dual-role actor used to prove checking identity, not merely role name, prevents self-approval.
INSERT INTO USER_ROLE(user_id,role_id) VALUES(3,4);
INSERT INTO DEPARTMENT(department_id,department_code,department_name) VALUES(1,'IT','Cong nghe thong tin');
INSERT INTO DEPARTMENT(department_id,department_code,department_name) VALUES(2,'HR','Nhan su');
INSERT INTO DEPARTMENT(department_id,department_code,department_name) VALUES(3,'FIN','Tai chinh');
INSERT INTO JOB_POSITION(position_id,position_code,position_name) VALUES(1,'DEV','Lap trinh vien');
INSERT INTO JOB_POSITION(position_id,position_code,position_name) VALUES(2,'SPECIALIST','Chuyen vien');
INSERT INTO EMPLOYEE(employee_id,employee_code,full_name,hire_date) VALUES(1,'NV001','Vo Hong Dang Khoa',DATE '2026-01-01');
INSERT INTO EMPLOYEE(employee_id,employee_code,full_name,hire_date) VALUES(2,'NV002','Bui Quang Huy',DATE '2026-01-01');
INSERT INTO EMPLOYEE(employee_id,employee_code,full_name,hire_date) VALUES(3,'NV003','Tran Minh Khoi',DATE '2026-09-16');
UPDATE APP_USER SET employee_id=1 WHERE user_id=1;
INSERT INTO EMPLOYEE_ASSIGNMENT(assignment_id,employee_id,department_id,position_id,valid_from,created_by) VALUES(1,1,1,1,DATE '2026-01-01',2);
INSERT INTO EMPLOYEE_ASSIGNMENT(assignment_id,employee_id,department_id,position_id,valid_from,created_by) VALUES(2,2,2,2,DATE '2026-01-01',2);
INSERT INTO EMPLOYEE_ASSIGNMENT(assignment_id,employee_id,department_id,position_id,valid_from,created_by) VALUES(3,3,3,2,DATE '2026-09-16',2);
INSERT INTO CALENDAR_DAY(calendar_id,work_date,day_type,standard_minutes)
SELECT 1,DATE '2026-09-01'+LEVEL-1,
  CASE WHEN TRUNC(DATE '2026-09-01'+LEVEL-1)-TRUNC(DATE '2026-09-01'+LEVEL-1,'IW') IN (5,6) THEN 'RESTDAY' ELSE 'WORKDAY' END,
  CASE WHEN TRUNC(DATE '2026-09-01'+LEVEL-1)-TRUNC(DATE '2026-09-01'+LEVEL-1,'IW') IN (5,6) THEN 0 ELSE 480 END
FROM dual CONNECT BY LEVEL<=30;
-- No holiday law is assumed in this fictional calendar.
INSERT INTO EMPLOYMENT_CONTRACT(contract_id,employee_id,contract_no,valid_from,monthly_salary,insurance_base,calendar_id,created_by,approved_by,approved_at,status)
VALUES(1,1,'HD001-A',DATE '2026-01-01',13200000,12000000,1,2,4,SYSTIMESTAMP,'APPROVED');
INSERT INTO EMPLOYMENT_CONTRACT(contract_id,employee_id,contract_no,valid_from,valid_to,monthly_salary,insurance_base,calendar_id,created_by,approved_by,approved_at,status)
VALUES(2,2,'HD002-A',DATE '2026-01-01',DATE '2026-09-16',17600000,15000000,1,2,4,SYSTIMESTAMP,'APPROVED');
INSERT INTO EMPLOYMENT_CONTRACT(contract_id,employee_id,contract_no,valid_from,monthly_salary,insurance_base,calendar_id,created_by,approved_by,approved_at,status)
VALUES(3,2,'HD002-B',DATE '2026-09-16',19800000,18000000,1,2,4,SYSTIMESTAMP,'APPROVED');
INSERT INTO EMPLOYMENT_CONTRACT(contract_id,employee_id,contract_no,valid_from,monthly_salary,insurance_base,calendar_id,created_by,approved_by,approved_at,status)
VALUES(4,3,'HD003-A',DATE '2026-09-16',11000000,10000000,1,2,4,SYSTIMESTAMP,'APPROVED');
INSERT INTO PAYROLL_POLICY(policy_id,policy_code,valid_from,valid_to,employee_insurance_rate,employer_insurance_rate,insurance_cap,personal_relief,dependent_relief,
  ot_workday_factor,ot_restday_factor,ot_holiday_factor,night_extra_factor,ot_taxable_fraction,round_scale,created_by,source_note)
VALUES(1,'DEMO_2026',DATE '2026-01-01',DATE '2027-01-01',0.10,0.20,20000000,10000000,3000000,1.5,2,3,0.3,1,0,2,'DEMO FICTIONAL POLICY FOR TESTING ONLY');
INSERT INTO TAX_BRACKET(bracket_id,policy_id,lower_bound,upper_bound,rate) VALUES(1,1,0,5000000,0.05);
INSERT INTO TAX_BRACKET(bracket_id,policy_id,lower_bound,upper_bound,rate) VALUES(2,1,5000000,10000000,0.10);
INSERT INTO TAX_BRACKET(bracket_id,policy_id,lower_bound,upper_bound,rate) VALUES(3,1,10000000,NULL,0.20);
UPDATE PAYROLL_POLICY SET status='APPROVED',approved_by=4 WHERE policy_id=1;
INSERT INTO EMPLOYEE_ALLOWANCE(allowance_id,employee_id,component_id,amount,allocation_method,valid_from,created_by,approved_by,status)
VALUES(1,1,6,1100000,'PAID_MINUTES',DATE '2026-01-01',2,4,'APPROVED');
INSERT INTO DEDUCTION_ACCOUNT(deduction_account_id,employee_id,principal_amount,monthly_limit,opened_by,description)
VALUES(1,1,5000000,1000000,3,'Tam ung demo');
INSERT INTO EMPLOYEE_BANK_ACCOUNT(bank_account_id,employee_id,bank_code,account_ciphertext,account_last4,account_hmac,holder_name,valid_from,created_by,verified_by,verified_at,status)
VALUES(1,1,'DEMO_BANK','DEMO_CIPHERTEXT_NOT_REAL','0001','demo_hmac_1','VO HONG DANG KHOA',DATE '2026-01-01',1,2,SYSTIMESTAMP,'VERIFIED');
INSERT INTO EMPLOYEE_BANK_ACCOUNT(bank_account_id,employee_id,bank_code,account_ciphertext,account_last4,account_hmac,holder_name,valid_from,created_by,verified_by,verified_at,status)
VALUES(2,2,'DEMO_BANK','DEMO_CIPHERTEXT_NOT_REAL','0002','demo_hmac_2','NGUYEN THI AN',DATE '2026-01-01',2,4,SYSTIMESTAMP,'VERIFIED');
INSERT INTO EMPLOYEE_BANK_ACCOUNT(bank_account_id,employee_id,bank_code,account_ciphertext,account_last4,account_hmac,holder_name,valid_from,created_by,verified_by,verified_at,status)
VALUES(3,3,'DEMO_BANK','DEMO_CIPHERTEXT_NOT_REAL','0003','demo_hmac_3','TRAN MINH BINH',DATE '2026-09-16',2,4,SYSTIMESTAMP,'VERIFIED');
INSERT INTO PAYROLL_PERIOD(period_id,period_start,period_end) VALUES(1,DATE '2026-09-01',DATE '2026-10-01');
INSERT INTO BONUS_DEDUCTION(entry_id,employee_id,period_id,component_id,amount,deduction_account_id,reason,status,created_by,approved_by)
VALUES(1,1,1,8,1000000,1,'Thu hoi tam ung demo','APPROVED',3,4);
BEGIN
  FOR e IN (SELECT employee_id,hire_date FROM EMPLOYEE) LOOP
    FOR d IN (SELECT work_date,standard_minutes FROM CALENDAR_DAY WHERE calendar_id=1 AND work_date>=e.hire_date ORDER BY work_date) LOOP
      PKG_HR_CORE.save_day(2,1,e.employee_id,d.work_date,d.standard_minutes,0,0);
    END LOOP;
  END LOOP;
END;
/
COMMIT;
-- Payroll stays OPEN. 09 tests use ROLLBACK so demo input remains reusable.
