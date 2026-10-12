-- Run read-only experiments as PAYROLL_APP after adding realistically sized demo data.
-- Do not drop indexes from the main schema merely to force an example.
EXPLAIN PLAN SET STATEMENT_ID='TS_FULL' FOR
SELECT /*+ FULL(t) */ * FROM TIMESHEET_DAILY t WHERE employee_id=1 AND work_date>=DATE '2026-09-01' AND work_date<DATE '2026-10-01';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'TS_FULL','BASIC +PREDICATE +COST'));
EXPLAIN PLAN SET STATEMENT_ID='TS_INDEX' FOR
SELECT /*+ INDEX(t ix_ts_emp_date) */ * FROM TIMESHEET_DAILY t WHERE employee_id=1 AND work_date>=DATE '2026-09-01' AND work_date<DATE '2026-10-01';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'TS_INDEX','BASIC +PREDICATE +COST'));
EXPLAIN PLAN SET STATEMENT_ID='PAYROLL_COST' FOR
SELECT period_start,SUM(company_payroll_cost) FROM VW_PAYROLL_APPROVED GROUP BY period_start;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'PAYROLL_COST','BASIC +PREDICATE +COST'));
-- Forced plans demonstrate alternatives, not proof one is faster.
-- On small data, a full scan can be cheaper. Record data size, optimizer stats and actual execution metrics.
