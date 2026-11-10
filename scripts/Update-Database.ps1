param([string]$Container='oracle23ai',[string]$Pdb='FREEPDB1')
$ErrorActionPreference='Stop'
if ($Container -notmatch '^[A-Za-z0-9_.-]+$' -or $Pdb -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid database target' }
$projectRoot=Split-Path $PSScriptRoot -Parent
$sqlRoot=Join-Path $projectRoot 'Database_Nhan_su_Tinh_luong_v2\sql'
$upgradeFiles=@('16_platform.sql','17_hr_portal.sql','18_finance_portal.sql','19_configuration.sql','20_payroll_withdraw.sql')
& docker exec $Container mkdir -p /tmp/payroll_upgrade
if($LASTEXITCODE -ne 0){throw 'Oracle container is not running.'}
foreach($file in $upgradeFiles){
    & docker cp (Join-Path $sqlRoot $file) "${Container}:/tmp/payroll_upgrade/$file"
    if($LASTEXITCODE -ne 0){throw "Could not copy $file"}
}
$commands=@(
 'whenever sqlerror exit failure rollback',
 'set define off',
 'set pages 200 lines 240 trimspool on',
 "alter session set container=$Pdb;",
 'alter session set current_schema=PAYROLL_APP;'
)
foreach($file in $upgradeFiles){$commands+="@/tmp/payroll_upgrade/$file"}
$objects="'PKG_PLATFORM','PKG_HR_PORTAL','PKG_FINANCE_PORTAL','PKG_CONFIGURATION','TG_RUN_TRANSITION'"
$commands+=@(
 "select name,type,line,position,text from all_errors where owner='PAYROLL_APP' and attribute='ERROR' and name in ($objects) order by name,type,sequence;",
 "declare n number; begin select count(*) into n from all_objects where owner='PAYROLL_APP' and object_name in ($objects) and status='VALID'; if n<>9 then raise_application_error(-20999,'Upgrade contains missing or invalid objects. Review compilation errors above.'); end if; end;",
 '/',
 "select object_name,object_type,status from all_objects where owner='PAYROLL_APP' and object_name in ($objects) order by object_name,object_type;",
 'exit success'
)
($commands -join "`n") | & docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 $Container sqlplus -s / as sysdba
if($LASTEXITCODE -ne 0){throw 'Database upgrade failed; original data has not been reset.'}
Write-Output 'Database packages updated successfully. No demo data or schema reset was executed.'
