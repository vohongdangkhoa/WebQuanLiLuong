CREATE OR REPLACE VIEW VW_PAYROLL_APPROVED AS
SELECT p.period_id,p.period_start,u.run_id,r.result_id,r.employee_id,r.employee_code_snapshot,r.employee_name_snapshot,
  r.department_id_snapshot,r.department_name_snapshot,r.gross_amount,r.employee_insurance,r.pit_amount,r.other_deduction,r.net_amount,
  r.employer_insurance,r.gross_amount+r.employer_insurance company_payroll_cost
FROM PAYROLL_PERIOD p JOIN PAYROLL_RUN u ON u.period_id=p.period_id AND u.status='APPROVED' JOIN PAYROLL_RESULT r ON r.run_id=u.run_id;

CREATE OR REPLACE VIEW VW_DEPARTMENT_COST AS
SELECT p.period_start,u.run_id,i.department_id,i.department_name_snapshot,
  SUM(CASE WHEN i.kind_snapshot='EARNING' THEN i.amount ELSE 0 END) gross,
  SUM(CASE WHEN i.kind_snapshot='EMPLOYER_COST' THEN i.amount ELSE 0 END) employer_cost,
  SUM(i.amount) company_payroll_cost
FROM PAYROLL_PERIOD p JOIN PAYROLL_RUN u ON u.period_id=p.period_id AND u.status='APPROVED'
JOIN PAYROLL_RESULT r ON r.run_id=u.run_id JOIN PAYROLL_ITEM i ON i.result_id=r.result_id
WHERE i.kind_snapshot IN ('EARNING','EMPLOYER_COST')
GROUP BY p.period_start,u.run_id,i.department_id,i.department_name_snapshot;

CREATE OR REPLACE VIEW VW_PAYMENT_PROGRESS AS
SELECT b.batch_id,b.run_id,b.status export_status,COUNT(i.payment_item_id) transfer_count,
  NVL(SUM(i.amount),0) total_amount,
  NVL(SUM(CASE WHEN i.status='SUCCEEDED' THEN i.amount ELSE 0 END),0) paid_amount,
  NVL(SUM(CASE WHEN i.status IN ('READY','PROCESSING') THEN i.amount ELSE 0 END),0) reserved_amount,
  NVL(SUM(CASE WHEN i.status='FAILED' THEN i.amount ELSE 0 END),0) failed_amount
FROM PAYMENT_BATCH b LEFT JOIN PAYMENT_ITEM i ON i.batch_id=b.batch_id GROUP BY b.batch_id,b.run_id,b.status;
-- Do NOT sum total_amount across retry batches as the total obligation.
-- Obligation = approved PAYROLL_RESULT.net_amount. Progress comes from attempts by result_id.

-- Read-only compilation and dictionary checks. Execute as owner.
SELECT object_type,object_name,status FROM USER_OBJECTS WHERE status<>'VALID' ORDER BY object_type,object_name;
SELECT name,type,line,position,text FROM USER_ERRORS ORDER BY name,sequence;
SELECT constraint_name,table_name,status,validated FROM USER_CONSTRAINTS WHERE status<>'ENABLED' OR validated<>'VALIDATED';

-- Chapter 2: CTE + LAG, approved versions only so recalculation cannot inflate totals.
WITH monthly_cost AS (
 SELECT period_start,SUM(company_payroll_cost) payroll_cost FROM VW_PAYROLL_APPROVED GROUP BY period_start
), comparisons AS (
 SELECT period_start,payroll_cost,LAG(payroll_cost) OVER (ORDER BY period_start) previous_cost FROM monthly_cost
)
SELECT period_start,payroll_cost,previous_cost,payroll_cost-previous_cost difference,
  ROUND((payroll_cost-previous_cost)/NULLIF(previous_cost,0)*100,2) pct_change FROM comparisons ORDER BY period_start;

-- Chapter 2: top three salary amounts per month-end department (ties preserved).
WITH ranked AS (
 SELECT v.*,DENSE_RANK() OVER (PARTITION BY period_id,department_id_snapshot ORDER BY gross_amount DESC) salary_rank FROM VW_PAYROLL_APPROVED v
)
SELECT employee_code_snapshot,employee_name_snapshot,department_name_snapshot,gross_amount,salary_rank FROM ranked WHERE salary_rank<=3;

-- Chapter 2: organization tree. NOCYCLE exposes corrupted cycles during manual owner maintenance.
SELECT department_id,department_name,LEVEL depth,CONNECT_BY_ISCYCLE cycle_found,
 SYS_CONNECT_BY_PATH(department_name,' / ') full_path FROM DEPARTMENT START WITH parent_id IS NULL CONNECT BY NOCYCLE PRIOR department_id=parent_id;

-- Reconciliation of totals must return zero rows after calculation.
SELECT r.result_id FROM PAYROLL_RESULT r LEFT JOIN PAYROLL_ITEM i ON i.result_id=r.result_id
GROUP BY r.result_id,r.gross_amount,r.employee_insurance,r.pit_amount,r.other_deduction,r.employer_insurance
HAVING r.gross_amount<>NVL(SUM(CASE WHEN i.kind_snapshot='EARNING' THEN i.amount ELSE 0 END),0)
 OR r.employee_insurance<>NVL(SUM(CASE WHEN i.component_code_snapshot='INS_EMP' THEN i.amount ELSE 0 END),0)
 OR r.pit_amount<>NVL(SUM(CASE WHEN i.component_code_snapshot='PIT' THEN i.amount ELSE 0 END),0)
 OR r.other_deduction<>NVL(SUM(CASE WHEN i.kind_snapshot='DEDUCTION' AND i.component_code_snapshot NOT IN ('INS_EMP','PIT') THEN i.amount ELSE 0 END),0)
 OR r.employer_insurance<>NVL(SUM(CASE WHEN i.kind_snapshot='EMPLOYER_COST' THEN i.amount ELSE 0 END),0);
