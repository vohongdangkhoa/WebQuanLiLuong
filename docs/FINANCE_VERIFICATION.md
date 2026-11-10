# Finance verification and isolated exam scenario

## Evidence already obtained

- Backend compiles in a separate `.work/finance-build` artifacts tree. An offline NuGet audit warning (`NU1900`) does not mean compilation failed.
- `tools/FinanceSmoke` exercises the actual pure CSV/crypto/error-mapping helpers, with no Oracle connections. Run:

```powershell
dotnet run --project tools/FinanceSmoke/FinanceSmoke.csproj --artifacts-path .work/finance-smoke -p:NuGetAudit=false --no-launch-profile
```

The checks cover correct evidence, BOM plus quoted headers, escaped commas/newlines, malformed quotes, duplicate references, fractional cents, missing transaction/reason, authenticated AES-GCM round trip/tampering, CSV formula safety, and controlled permission/business/busy errors. This does not substitute for Oracle and HTTP verification.

## Important separation of test strategies

Existing command APIs deliberately commit one transaction per successful request. A later ROLLBACK on a different owner connection cannot undo those HTTP requests.

1. For a zero-persistent-write business-procedure test, run a single owner-session anonymous PL/SQL block with a starting SAVEPOINT, NO DDL and NO COMMIT, and unconditional ROLLBACK on success and exception. All expected failures use nested savepoints. This tests database logic, not the entire HTTP stack.
2. For a real HTTP happy path, use a disposable cloned schema, or a clearly named, additive isolated exam fixture period with no existing eligible employees. The latter preserves original records but intentionally persists new fixture records and their audit trail. Do not claim these writes were rolled back.

Never run `00_install_owner.sql` or demo seed installation over an existing populated schema just to reset a test. DDL commits implicitly. Do not disable triggers or edit published payroll/history to make tests pass.

## Original `09_oracle_tests.sql` constraints

This suite is for the original dedicated seed schema, not an arbitrary populated installation. It hardcodes period 1, employees 1–3, actors 1–4, fixed request keys and expected arithmetic. Actors must still be active. Seed actor 3 has PAYROLL and DIRECTOR: this is intentional so the maker-checker test reaches `-20049`; otherwise the earlier role check yields `-20002`. Preserve that distinction when adapting the suite to newly bootstrapped users.

The source suite has one starting savepoint and rolls its changes back. It inserts placeholder document hashes to test DB transitions, so it does NOT validate actual encrypted-bank CSV export or durable file storage. The new HTTP path must prove those separately.

## Preflight, before any runtime writes

Owner can inspect only metadata and ordinary status/ID fields; do not print password hashes, connection strings, full accounts, encrypted account envelopes or the encryption key.

```sql
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('PKG_PAYROLL_INTERNAL','PKG_HR_CORE','PKG_PAYROLL_CORE',
  'PKG_PAYMENT','PKG_PAYROLL_READ','PKG_REQUESTS','PKG_FINANCE_PORTAL')
ORDER BY object_name, object_type;
SELECT name,type,line,position,text FROM user_errors ORDER BY name,sequence;
SELECT p.period_id,p.period_start,p.period_status,p.timesheet_status,
  (SELECT COUNT(*) FROM payroll_run u WHERE u.period_id=p.period_id) run_count
FROM payroll_period p ORDER BY p.period_start;
SELECT u.user_id,u.username,u.is_active,r.role_code
FROM app_user u JOIN user_role ur ON ur.user_id=u.user_id
JOIN app_role r ON r.role_id=ur.role_id ORDER BY u.user_id,r.role_code;
```

Select separate active PAYROLL and DIRECTOR identities. Confirm an EMPLOYEE identity links to the test employee for payslip ownership checks. Keep the actor server-derived in every HTTP test; never add actor fields to request JSON.

## Suggested isolated fixture

Pick a month strictly before the earliest existing hire date and absent from PAYROLL_PERIOD; `1999-01` is an example, not a requirement. Prove those preconditions before choosing it. Because `calculate` includes every employee employed during the period, merely creating a new recent/future period is NOT sufficient isolation.

Prepare the fixture with owner-approved setup in one transaction:

- One explicitly named TEST employee with hire date at month start and termination date at month end. The bounded employment prevents it entering present/future real payroll runs. This fixture setup is distinct from the normal initial-assignment endpoint, which intentionally rejects employees with termination dates.
- One department/position assignment bounded to `[monthStart,nextMonthStart)`, one APPROVED contract with the same range and a complete calendar covering every calendar day.
- One APPROVED demo policy bounded to that month; exactly one effective policy must cover it. Mark policy source notes as a test/demonstration; use valid progressive brackets covering zero through an unbounded upper range. No published policy is edited.
- A full daily timesheet, including zero minutes on rest days. For straightforward arithmetic, use weekday 480 minutes, rest-day 0, monthly salary = working-day count × 1,000,000, and explicit zero insurance/tax test policy if permitted. The expected full-month gross/net then equals that salary with no allowance/deduction rows.
- A verified, encrypted TEST bank destination effective TODAY, since `create_batch` selects the bank account on the current Vietnam date rather than the payroll month. Use the agreed AES-GCM server key; do not copy plaintext or placeholder ciphertext into production rows. Use a deliberately fictitious test destination and never send the resulting test file to a real bank.
- One active employee login linked to the TEST employee, and distinct maker/checker identities. Fixture creation must not change existing credentials or roles.

Snapshot original period/run/result/payment status and input versions before setup; after the scenario verify only the isolated fixture and its audit records changed. Keep test identifiers and purpose documented. The fixture can remain as clearly labeled exam data; cleanup must respect append-only financial records, never DELETE published history.

## HTTP end-to-end sequence

Use fresh CSRF tokens before POSTs and cookie sessions for the right identity. Read endpoint contracts in `FINANCE_API.md`. Keep one request key for retries of the same calculation or batch creation.

| Step | Expected evidence |
|---|---|
| Anonymous GET `/api/finance/periods` | 401 |
| HR GET `/api/finance/periods`; HR GET `/runs` | First permitted, second 403 |
| PAYROLL create fixture period if setup did not create it | 201; first-of-month/end-exclusive dates; duplicate month 409 |
| HR certifies every day and locks fixture month using guarded HR APIs | Month ended in Vietnam; timesheetStatus LOCKED |
| PAYROLL POST `/runs` | 201 with runId; GET runs status CALCULATED, errorCount 0, actual amounts equal independently computed fixture totals |
| Repeat identical calculation request key | Same runId, no second run/result set |
| PAYROLL GET results/items/errors | Result totals reconcile to item sums; errors empty |
| PAYROLL POST submit | PENDING_APPROVAL |
| Maker attempts approve | 403 if not DIRECTOR; for a deliberately dual-role maker, 409 from maker-checker DB rule |
| Distinct DIRECTOR approves | APPROVED; published payslip exists; repeat terminal action rejected, no extra deduction consumption |
| EMPLOYEE GET own payslips/items | Own published result visible; another employee's result forbidden |
| PAYROLL creates payment batch | CREATED with expected positive net amounts; only masked account fields in ordinary JSON |
| Same payment request key repeated | Same batchId; another key cannot reserve the same READY/PROCESSING/SUCCEEDED result again |
| Remove/misconfigure bank key in an isolated process only | Export fails controlled 503, no export metadata/state change. Restore original key without printing it |
| PAYROLL exports bank CSV | Real decrypted TEST destination, stable references, precise decimal amounts; Content-Disposition download; database EXPORTED + document/hash + encrypted durable document file |
| Re-export | Identical downloaded bytes/hash/document ID; no new payment attempts |
| Human/test harness explicitly confirms simulated test transmission | POST sent -> SENT; payment items PROCESSING. No code claims a live bank transfer occurred |
| Import test-bank evidence CSV for this isolated fixture | Saved proof/hash; SUCCEEDED rows have unique transaction IDs; FAILED rows have reasons; inspect every matchStatus |
| Re-import same bytes | 409; no duplicate import/payment effect |
| Try closing before every positive-net result succeeds | 409 |
| DIRECTOR closes after all proof is MATCHED and obligations paid | CLOSED; summary/report only includes the approved version once |

Inspect the original unrelated records after completion. This test intentionally uses simulated bank evidence for a marked test fixture; live operation must use actual bank-returned evidence. The application does not connect to a bank or transfer real money.

## Negative evidence and rollback-only branches

`PKG_PAYMENT.close_period` blocks when ANY related BANK_RECON_LINE has AMOUNT_MISMATCH or CONFLICT. An imported bad proof row remains historical evidence; uploading another file does not erase it. Therefore do not persist intentionally bad evidence into the happy-path fixture and then expect that same period to close automatically.

Exercise wrong amount, duplicate bank transaction, uncertain PROCESSING, invalid status, and role failures inside a single SQL savepoint branch or in a separate disposable fixture. Roll back the branch before continuing the successful-close case. Use actual reference/amount returned for the chosen test payment item, never invent production references. A failed reconciliation request is atomic: no document metadata/import/line/payment change may remain if any processing command throws; an orphan encrypted content-addressed file can exist without committed metadata and must never be served as a committed document.

For transient connectivity/timeout around a command response, query status by request key/reference before any retry. The client must not silently resend a payment command or reinterpret a failed refresh as failed creation.
