# Configuration module contract

Page `ConfigurationPage.jsx`, route suggested `/configuration`. All endpoints below start `/api/configuration`, cookie+CSRF, no-store; actor always from claims. List responses plain arrays camelCase. Rates/factors are user-supplied policy parameters, not assertions about current law. Validity ranges are start-inclusive/end-exclusive.

Manager GETs require HR/PAYROLL/DIRECTOR. EMPLOYEE may also call `/catalogs` (only own employee; other arrays empty) and `/dependents` (only own claims; selecting another employee is forbidden in Oracle):

- `/catalogs` -> `{employees:[{employeeId,employeeCode,fullName}],periods:[{periodId,periodStart,periodStatus}],components:[{componentId,componentCode,componentName,componentKind,taxableFraction}],deductionAccounts:[{deductionAccountId,employeeId,employeeCode,principalAmount,collectedAmount,monthlyLimit,description}]}`.
- `/policies` -> policy parameter fields below plus policyId/status/createdBy/approvedBy.
- `/policies/{id}/brackets` -> `[{bracketId,lowerBound,upperBound,rate}]`.
- `/allowances?employeeId=` -> `[{allowanceId,employeeId,employeeCode,fullName,componentId,componentName,amount,allocationMethod,validFrom,validTo,status,createdBy,approvedBy}]`.
- `/entries?employeeId=&periodId=` -> `[{entryId,employeeId,employeeCode,fullName,periodId,periodStart,componentId,componentName,componentKind,amount,deductionAccountId,reason,status,createdBy,approvedBy}]`.
- `/dependents?employeeId=` -> `[{claimId,employeeId,employeeCode,employeeName,dependentName,birthDate,validFrom,validTo,documentId,status,requestedBy,verifiedBy}]`. No raw identity or HMAC is returned.

Commands return `{id,message}` (201) or `{message}` (200):

- PAYROLL `POST /policies`: `{policyCode,validFrom,validTo?,employeeInsuranceRate,employerInsuranceRate,insuranceCap,personalRelief,dependentRelief,otWorkdayFactor,otRestdayFactor,otHolidayFactor,nightExtraFactor,otTaxableFraction,roundScale,sourceNote,brackets:[{lowerBound,upperBound:null|number,rate}]}`. Creates PENDING plus tax brackets atomically. Brackets must start at 0, contiguous, final band unbounded, rates [0,1].
- DIRECTOR `POST /policies/{id}/decision`: `{decision:"APPROVE"|"REJECT",reason?}`. Different maker/checker; only PENDING; approval verifies no other APPROVED interval overlaps and valid bracket coverage.
- DIRECTOR `POST /policies/{id}/end`: `{validTo,reason}`. Only shortens an APPROVED interval; immutable existing payroll/locked periods remain protected by triggers. Values/rates never edited in place.
- HR or PAYROLL `POST /allowances`: `{employeeId,componentId,amount,allocationMethod:"FULL_MONTH"|"PAID_MINUTES"|"CALENDAR_DAYS",validFrom,validTo?}`. Manual EARNING component; PENDING.
- DIRECTOR `POST /allowances/{id}/decision`: same decision body. Different creator/approver; overlap/frozen-input triggers retained.
- PAYROLL `POST /deduction-accounts`: `{employeeId,principalAmount,monthlyLimit,description}`. Creates an uncollected balance account, does not deduct money by itself.
- HR or PAYROLL `POST /entries`: `{employeeId,periodId,componentId,amount,deductionAccountId?,reason}`. PENDING one-period bonus/deduction. Manual DEDUCTION requires a matching balance account; EARNING must not supply one. Core BASE/OT/INS_EMP/PIT/INS_COMPANY codes cannot be manually duplicated.
- DIRECTOR `POST /entries/{id}/decision`: same decision body; maker/checker and freeze rules apply.
- HR or EMPLOYEE (own employee only) `POST /dependents`: `{employeeId,identity,fullName,birthDate?,validFrom,validTo?,documentId}`. Raw identity normalized and HMACed server-side using BankSecurityService.Fingerprint("Dependent",normalizedIdentity), never stored/returned in plaintext. Required documentId must come from actual multipart `POST /api/documents` upload, owned by actor, upload storage prefix `uploads/`, PDF/PNG/JPEG. Creates PENDING claim.
- DIRECTOR `POST /dependents/{id}/decision`: same decision body; APPROVE -> VERIFIED, REJECT -> REJECTED, actor different from requester. Verified dependent cannot overlap another employee's verified claim for the same identity.

Document upload contract (implemented by root): multipart field `file`, response `{documentId,fileName,sha256,sizeBytes}`. UI must upload real selected bytes first and only then send returned documentId; never invent placeholder document IDs.

Pending records are immutable through these APIs except their explicit decision. No DELETE endpoints. Errors safe `{message}`: invalid input 400, no permission 403, absent record 404, maker-checker/state/overlap/frozen 409, busy 503. Money IDs numeric; date ISO strings. Integration DI: `AddScoped<OracleConfigurationRepository>()`.
