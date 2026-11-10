param([string]$Container='oracle23ai')
$ErrorActionPreference='Stop'
if($Container -notmatch '^[A-Za-z0-9_.-]+$'){throw 'Invalid container name'}
$projectRoot=Split-Path $PSScriptRoot -Parent
$source=Get-Content -LiteralPath (Join-Path $projectRoot 'Database_Nhan_su_Tinh_luong_v2\sql\09_oracle_tests.sql') -Raw
$source=$source.Replace('FROM USER_ERRORS','FROM ALL_ERRORS WHERE owner=''PAYROLL_APP'' AND attribute=''ERROR''')
$testFolder=Join-Path $projectRoot '.work';New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
$path=Join-Path $testFolder 'core-tests.sql'
[IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($false))
& docker cp $path "${Container}:/tmp/payroll-core-tests.sql"
if($LASTEXITCODE -ne 0){throw 'Cannot copy rollback test suite'}
$commands="whenever sqlerror exit failure rollback`nalter session set container=FREEPDB1;`nalter session set current_schema=PAYROLL_APP;`n@/tmp/payroll-core-tests.sql`nrollback;`nexit"
$commands | & docker exec -i $Container sqlplus -s / as sysdba
if($LASTEXITCODE -ne 0){throw 'Oracle core test failed. All test writes rolled back.'}
