# Finance API contract

All routes start `/api/finance`. Cookie authentication, no-store responses. POSTs require the existing CSRF header/cookie. IDs are positive numbers. Request keys are client-generated UUID strings (max 100), retained for retries of the same command. Errors return `{message}` or ASP.NET validation `{errors}`. Lists are plain arrays with camelCase properties; dates are ISO `yyyy-MM-dd`, timestamps ISO strings. No browser-supplied actor is accepted.

## Periods and payroll

- `GET /periods` (HR/PAYROLL/DIRECTOR): `[{periodId,periodStart,periodEnd,periodStatus,timesheetStatus,inputVersion,lockedAt}]`.
- `POST /periods` (PAYROLL): `{periodStart:"2026-11-01"}` -> 201 `{periodId,message}`. First of month; end is exclusive next month.
- `GET /runs?periodId=1` (PAYROLL/DIRECTOR; filter optional): `[{runId,periodId,periodStart,versionNo,status,inputVersion,policyId,calculatedBy,createdAt,finishedAt,successCount,errorCount,grossAmount,netAmount,employerInsurance}]`.
- `POST /runs` (PAYROLL): `{periodId,requestKey}` -> 201 `{runId,message}`. Calls the real calculate procedure; a returned run can have ERROR status. Refresh runs/errors afterwards.
- `POST /runs/{runId}/calculate` (PAYROLL): `{requestKey}` -> `{runId,message}`. Creates another version for that run's period; never edits an immutable completed run.
- `GET /runs/{runId}/results`: `[{resultId,runId,employeeId,employeeCode,employeeName,departmentName,grossAmount,employeeInsurance,pitAmount,otherDeduction,netAmount,employerInsurance,taxableIncome,dependentCount,paymentStatus}]`.
- `GET /runs/{runId}/errors`: `[{errorId,employeeId,employeeCode,employeeName,errorCode,errorMessage,createdAt}]`.
- `GET /results/{resultId}/items`: `[{itemId,componentCode,kind,departmentName,sourceType,sourceDate,amount,taxableAmount,quantity,unitRate,multiplier,formula}]`.
- `POST /runs/{runId}/submit` (PAYROLL): `{}` -> `{message}`.
- `POST /runs/{runId}/approve` (DIRECTOR): `{}` -> `{message}`.
- `POST /runs/{runId}/reject` (DIRECTOR): `{reason}` -> `{message}`. Maker cannot approve own work; DB enforces.

## Payments

Reads PAYROLL/DIRECTOR, commands PAYROLL unless noted.

- `GET /payments?runId=1` (optional filter): `[{batchId,runId,periodStart,status,createdBy,createdAt,exportDocumentId,exportSha256,exportedAt,itemCount,totalAmount,paidAmount,processingAmount,failedAmount}]`.
- `POST /payments`: `{runId,requestKey}` -> 201 `{batchId,message}`. Requires approved payroll and verified effective bank accounts.
- `GET /payments/{batchId}/items`: `[{paymentItemId,resultId,employeeId,employeeCode,employeeName,transferReference,attemptNo,amount,bankCode,accountLast4,holderName,status,bankTransactionId,confirmedAt,failureReason}]`. Never exposes full bank accounts/ciphertext.
- `POST /payments/{batchId}/export`: `{}` -> downloadable UTF-8 CSV `text/csv` (use response.blob(), NOT JSON on success). Columns `transferReference,bankCode,accountNumber,holderName,amount`. This is a generic bank instruction export, not a live bank submission. Requires server bank decryption key, supports encrypted `v1:base64(nonce12):base64(cipher):base64(tag16)`. Missing key/unsupported demo ciphertext returns controlled error, never pretends export succeeded. Re-download regenerates the identical snapshot CSV/hash/document.
- `POST /payments/{batchId}/sent`: `{}` -> `{message}`. Human confirmation that the exported file was actually sent externally; marks processing, does not claim payment succeeded.
- `POST /payments/{batchId}/reconcile`: `{fileName:"bank-result.csv",content:"transferReference,reportedAmount,bankStatus,bankTransactionId,failureReason\nPR-1-A1,1000000,SUCCEEDED,BANK-TX-123,\n"}` -> `{importId,lineCount,message}`. User supplies bank evidence; accepts statuses PROCESSING/SUCCEEDED/FAILED. Successful rows require transaction ID, failed rows require reason. Original CSV hash registered with document metadata; each row processed by guarded DB procedure. Duplicate import hash rejected with 409; conflicts/amount mismatches are persisted and visible, not falsely reported as paid.
- `GET /payments/{batchId}/reconciliation`: `[{reconLineId,importId,lineNo,transferReference,reportedAmount,bankStatus,bankTransactionId,failureReason,matchStatus}]`.
- `POST /periods/{periodId}/close` (DIRECTOR): `{}` -> `{message}`. DB refuses unpaid/conflicting results.

## Employee payslips and management reports

- `GET /payslips` (EMPLOYEE): `[{resultId,periodStart,grossAmount,employeeInsurance,pitAmount,otherDeduction,netAmount,issuedAt,paymentStatus}]`. Only the authenticated employee's approved/published payslips.
- `GET /payslips/{resultId}/items` (EMPLOYEE): `[{componentCodeSnapshot,kindSnapshot,sourceDate,amount,taxableAmount,quantity,unitRate,multiplier,formulaSnapshot}]`; ownership rechecked in DB.
- `GET /reports?periodId=1` (PAYROLL/DIRECTOR, filter optional): `[{periodId,periodStart,runId,departmentId,departmentName,employeeCount,grossAmount,netAmount,employeeInsurance,pitAmount,employerInsurance,companyCost}]`. Approved versions only, snapshot department at result level. `GET /reports/export?periodId=1` returns same data as CSV.

Generic error policy: 400 invalid input, 403 role/ownership, 404 absent entity, 409 invalid/frozen state or maker-checker conflict, 503 database busy or missing export configuration. No automatic POST retry. A successful command followed by a failed refresh remains a successful command; show a separate reload warning.
