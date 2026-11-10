# HR API contract

All endpoints use authenticated cookie and all writes require `X-CSRF-TOKEN`. Dates are `yyyy-MM-dd`, timestamps local Vietnam wall time `yyyy-MM-ddTHH:mm:ss`. Actor never appears in request bodies. Response JSON camelCase. Lists are arrays. Errors `{message}`. Managers are HR / PAYROLL / DIRECTOR; mutations are HR unless explicitly stated.

- `GET /api/hr/catalogs` -> `{employees,departments,positions,calendars,shifts,leaveTypes,periods}`. Employees `{employeeId,employeeCode,fullName,hireDate,status}`; departments `{departmentId,departmentCode,departmentName}`; positions `{positionId,positionCode,positionName}`; calendars `{calendarId,calendarCode,calendarName}`; shifts `{shiftId,shiftCode,shiftName}`; leaveTypes `{leaveTypeId,leaveCode,leaveName,usesBalance}`; periods `{periodId,periodStart,periodEnd,periodStatus,timesheetStatus}`. Ordinary EMPLOYEE sees only their own employee in lookup; others common catalogs.
- `GET /api/hr/attendance?periodId=&employeeId=` -> rows `{timesheetId,periodId,employeeId,employeeCode,fullName,workDate,workedMinutes,paidLeaveMinutes,paidHolidayMinutes,paidMinutes,lateMinutes,status,errorMessage}`. Managers all, employee own.
- `POST /api/hr/attendance` body `{periodId,employeeId,workDate,workedMinutes,leaveMinutes,holidayMinutes,certified:true}` -> `{message}`. HR certifies values then PKG_HR_CORE.save_day.
- `POST /api/hr/attendance/lock` body `{periodId}` -> `{message}` HR.
- `POST /api/hr/attendance/reopen` body `{periodId,reason}` -> `{message}` HR, reason required.
- `POST /api/hr/calendar/month` body `{calendarId,monthDate:"2026-11-01"}` -> `{message}` HR. Adds missing days for selected month, default Mon-Fri480/rest0; preserves existing holidays/days.
- `GET /api/hr/calendar?calendarId=1&monthDate=2026-11-01` -> day rows `{calendarId,workDate,dayType,standardMinutes}` HR.
- `PUT /api/hr/calendar/day` body `{calendarId,workDate,dayType:"WORKDAY"|"RESTDAY"|"HOLIDAY",standardMinutes}` -> `{message}` HR. RESTDAY must be0, WORKDAY/HOLIDAY 0..1440. Frozen/approved payroll inputs cannot be changed. HR explicitly sets paid holidays; month initializer does not infer legal holidays.
- `POST /api/hr/leave-balances` body `{employeeId,leaveTypeId,effectiveDate,minutes,reason,requestKey}` -> `{id,message}` HR. Positive minutes, leave type usesBalance=Y, requestKey UUID for idempotent credit.
- `GET /api/hr/shifts?periodId=&employeeId=` -> scheduled rows `{employeeShiftId,employeeId,employeeCode,fullName,workDate,shiftId,shiftName,startsAt,endsAt}` HR.
- `POST /api/hr/shifts` body `{employeeId,workDate,shiftId}` -> `{id,message}` HR; assigns/updates one main shift per employee/day, blocks overlap/frozen periods.
- `GET /api/hr/attendance/raw` -> last raw events `{rawId,importId,sourceDevice,sourceEventKey,employeeId,sourceEmployeeCode,eventAt,eventType,validationError}` HR.
- `POST /api/hr/attendance/import` multipart field `file` .csv <=2MB, <=5000 rows. UTF8 comma CSV header `employeeCode,eventAt,eventType,sourceDevice,sourceEventKey`, timestamps local ISO e.g. `2026-11-05T08:00:00`, type IN/OUT/UNKNOWN. -> `{id,importedRows,skippedDuplicates,validationErrors,alreadyImported,message}`. Raw only, never certifies/overwrites timesheet. SHA256 blocks repeat-file import, event key blocks replay; unmatched employees preserved with validationError.
- `GET /api/hr/requests?employeeId=` -> `{leaves,overtime,corrections,balances}`. Leave rows `{leaveId,employeeId,employeeCode,fullName,leaveTypeId,leaveName,startsAt,endsAt,reason,status,requestedBy,decisionReason}`. Overtime rows `{overtimeId,employeeId,employeeCode,fullName,startsAt,endsAt,approvedMinutes,actualMinutes,status,reason,requestedBy}`. Corrections rows `{changeRequestId,periodId,employeeId,employeeCode,sourceType,sourceId,reason,status,requestedBy}`. Balance rows `{employeeId,employeeCode,leaveTypeId,leaveName,balanceMinutes}`. Employees see own; HR sees all; PAYROLL correction creation/list allowed.
- `POST /api/hr/requests/leave` body `{employeeId,leaveTypeId,startDate,endDate,minutesPerDay:480,reason}` -> `{id,message}`. Date interval inclusive start, EXCLUSIVE end (label endDate as "Đến trước ngày"). Creates allocations per effective contract/calendar, skipping zero-standard days and limiting minutesPerDay. HR may create for any employee, EMPLOYEE own only. Paid leave balance approval checks existing PKG_REQUESTS; creator cannot approve self.
- `POST /api/hr/requests/leave/{id}/decision` body `{decision:"APPROVE"|"REJECT",reason}` -> `{message}` HR. Rejection reason required.
- `POST /api/hr/requests/overtime` body `{employeeId,startsAt,endsAt,reason}` -> `{id,message}` HR any / EMPLOYEE own.
- `POST /api/hr/requests/overtime/{id}/approve` body `{minutes}` -> `{message}` HR, creator cannot approve self.
- `POST /api/hr/requests/overtime/{id}/confirm` body `{actualStart,actualEnd}` -> `{message}` HR; local timestamps.
- `POST /api/hr/requests/overtime/{id}/reject` body `{reason}` -> `{message}` HR.
- `POST /api/hr/requests/correction` body `{periodId,employeeId,reason,sourceType:"TIMESHEET",sourceId:null}` -> `{id,message}` HR/PAYROLL/EMPLOYEE-own.
- `POST /api/hr/requests/correction/{id}/resolve` body `{reason}` -> `{message}` HR. Resolves request; editing/locking actual timesheet remains separate guarded flow.
- `GET /api/hr/contracts?employeeId=` -> rows `{contractId,employeeId,employeeCode,fullName,contractNo,validFrom,validTo,monthlySalary,insuranceBase,insuranceEnabled,calendarId,calendarName,status,createdBy,approvedBy}` HR/PAYROLL/DIRECTOR.
- `POST /api/hr/contracts` body `{employeeId,contractNo,validFrom,validTo:null,monthlySalary,insuranceBase,insuranceEnabled:true,calendarId}` -> `{id,message}` HR; creates PENDING version.
- `POST /api/hr/contracts/{id}/decision` body `{decision:"APPROVE"|"REJECT",reason}` -> `{message}` DIRECTOR, creator != approver. Existing approved versions immutable; overlapping approval is rejected, create successive dates.
- `GET /api/hr/employees/{id}` -> `{employeeId,employeeCode,fullName,email,birthDate,hireDate,terminationDate,status,rowVersion}` HR.
- `PUT /api/hr/employees/{id}` body `{fullName,email:null,birthDate:null,status:"ACTIVE"|"INACTIVE"|"TERMINATED",terminationDate:null,rowVersion}` -> `{message}` HR optimistic concurrency. Terminated needs end date; no code/hire-date edits.
- `POST /api/hr/employees/{id}/transfer` body `{departmentId,positionId,validFrom,reason}` -> `{id,message}` HR. Closes current open interval, adds version. Must be after old start; cannot overwrite closed history or approved payroll period.

Existing endpoints remain: `/api/employees`, `/api/departments`, `/api/job-positions`, `/api/employees/{id}/assignments` GET history / POST initial assignment.
