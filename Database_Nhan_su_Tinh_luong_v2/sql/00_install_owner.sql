-- SQL*Plus: connect PAYROLL_APP@//localhost:1521/FREEPDB1 first.
-- Place all .sql files in one folder and run @00_install_owner.sql.
-- Schema must be empty; this is not a migration or a destructive reset.
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
@@02_tables.sql
@@03_indexes.sql
@@04_foundation.sql
@@05_payroll_packages.sql
@@06_payment_read_packages.sql
@@06b_request_io_packages.sql
@@07_guards.sql
@@10_reports_validation.sql
DECLARE v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM USER_ERRORS;
  IF v_n>0 THEN RAISE_APPLICATION_ERROR(-20998,'Compilation errors: inspect USER_ERRORS before continuing'); END IF;
END;
/
@@11_api_grants.sql
PROMPT Installation complete. Load 08_demo_data.sql separately, then 09_oracle_tests.sql.
