-- Extend the original transition guard without changing historical runs or results.
CREATE OR REPLACE TRIGGER tg_run_transition
BEFORE UPDATE OR DELETE ON PAYROLL_RUN FOR EACH ROW
BEGIN
  IF DELETING THEN RAISE_APPLICATION_ERROR(-20103,'Payroll run cannot be deleted'); END IF;
  IF UPDATING('period_id') OR UPDATING('version_no') OR UPDATING('request_key') OR UPDATING('input_version') OR UPDATING('policy_id') OR UPDATING('calculated_by') OR UPDATING('engine_version') THEN
    RAISE_APPLICATION_ERROR(-20104,'Run identity and inputs immutable'); END IF;
  IF :OLD.status IN ('APPROVED','REJECTED','CANCELLED') THEN RAISE_APPLICATION_ERROR(-20105,'Terminal run immutable'); END IF;
  IF :OLD.status<>:NEW.status AND NOT (
    (:OLD.status='CALCULATING' AND :NEW.status IN ('CALCULATED','ERROR')) OR
    (:OLD.status='CALCULATED' AND :NEW.status IN ('PENDING_APPROVAL','CANCELLED')) OR
    (:OLD.status='ERROR' AND :NEW.status='CANCELLED') OR
    (:OLD.status='PENDING_APPROVAL' AND :NEW.status IN ('APPROVED','REJECTED','CANCELLED')))
  THEN RAISE_APPLICATION_ERROR(-20106,'Invalid payroll state transition'); END IF;
END;
/
