# Platform API

All endpoints require cookie login, no-store. POST requires X-CSRF-TOKEN. Errors {message}; dates ISO.

- GET /api/dashboard -> {employeeCount,activeEmployeeCount,openPeriodCount,pendingRequestCount,latestPayrollNet,latestPeriodName,recentActivity:[{title,detail,occurredAt}]}. Financial totals only PAYROLL/DIRECTOR or employee own, HR total null.
- GET /api/bank-accounts?employeeId= -> [{bankAccountId,employeeId,employeeCode,fullName,bankCode,accountLast4,holderName,validFrom,validTo,status,createdBy,verifiedBy,verifiedAt}]. HR/PAYROLL/DIRECTOR see management data; employee only own. Never returns full account/ciphertext/hash.
- POST /api/bank-accounts -> {employeeId,bankCode,accountHolder,accountNumber,validFrom}. HR any, EMPLOYEE own; status PENDING. Account number string6..34 letters/digits, holder<=150, bankCode2..30. Encrypted server-side AESGCM, key never reaches browser.
- POST /api/bank-accounts/{id}/decision -> {decision:"VERIFY"|"REJECT"}. PAYROLL/DIRECTOR; maker cannot verify own. Verified replacements close older verified open interval. Already-created payment snapshots remain immutable.
- POST /api/auth/password -> {currentPassword,newPassword}. New password8..50, different. Success signs out and revokes other sessions; return to login.
- GET /api/audit -> latest300 safe rows [{auditId,actorName,entityType,entityId,action,reason,createdAt}], managers only. No before/after JSON or account details exposed.

Existing demo ciphertext cannot be exported as a real bank instruction: enter a fresh bank account and have another authorized user verify it first. Production BankEncryptionKey is mandatory 32bytebase64; Development creates encrypted persisted key under backend/.local (never commit).
