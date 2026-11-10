param(
    [ValidateRange(1024,65525)][int]$Port=5049,
    [switch]$SkipBuild,
    [switch]$NoBrowser
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$backend=Join-Path $root 'backend'
$frontend=Join-Path $root 'frontend'
$local=Join-Path $backend '.local'
$webRoot=Join-Path $backend 'wwwroot'
$dll=Join-Path $backend 'bin\Release\net10.0\Payroll.Api.dll'

if(-not $SkipBuild){
    Push-Location $frontend
    try {
        if(-not (Test-Path -LiteralPath (Join-Path $frontend 'node_modules\.bin\vite.cmd'))){
            & npm.cmd ci --no-audit --no-fund
            if($LASTEXITCODE -ne 0){throw 'Frontend dependencies failed to install.'}
        }
        & npm.cmd run build
        if($LASTEXITCODE -ne 0){throw 'Frontend build failed.'}
    } finally { Pop-Location }
    New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $frontend 'dist\*') -Destination $webRoot -Recurse -Force
    & dotnet build (Join-Path $backend 'Payroll.Api.csproj') -c Release -p:RestoreIgnoreFailedSources=true
    if($LASTEXITCODE -ne 0){throw 'Backend build failed.'}
}
if(-not (Test-Path -LiteralPath $dll) -or -not (Test-Path -LiteralPath (Join-Path $webRoot 'index.html'))){
    throw 'The build is missing. Run Start.ps1 without SkipBuild.'
}
New-Item -ItemType Directory -Path $local -Force | Out-Null
for($attempt=0;$attempt -lt 10;$attempt++){
    if(-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)){break}
    $Port++
}
if($attempt -eq 10){throw 'No free local port was found.'}
$url="http://localhost:$Port"
$oldEnvironment=$env:ASPNETCORE_ENVIRONMENT
$env:ASPNETCORE_ENVIRONMENT='Development'
try {
    $process=Start-Process -FilePath (Get-Command dotnet).Source `
        -ArgumentList @(('"'+$dll+'"'),'--urls',$url) -WorkingDirectory $backend `
        -WindowStyle Hidden -RedirectStandardOutput (Join-Path $local "server-$Port.log") `
        -RedirectStandardError (Join-Path $local "server-$Port-errors.log") -PassThru
} finally { $env:ASPNETCORE_ENVIRONMENT=$oldEnvironment }
$ready=$false
$timer=[Diagnostics.Stopwatch]::StartNew()
while($timer.Elapsed.TotalSeconds -lt 25){
    if($process.HasExited){break}
    try {
        $health=Invoke-RestMethod "$url/api/health" -TimeoutSec 2
        if($health.application -eq 'HRFlow'){$ready=$true;break}
    } catch { Start-Sleep -Milliseconds 400 }
}
if(-not $ready){throw "Server did not start. See backend/.local/server-$Port.log"}
@{pid=$process.Id;url=$url} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'running-server.json') -Encoding utf8
Write-Host "HRFlow: $url" -ForegroundColor Green
try {
    $database=Invoke-RestMethod "$url/api/health/database" -TimeoutSec 10
    Write-Host "Oracle: $($database.database)"
} catch { Write-Warning 'Oracle connection check failed. Verify Docker and ConnectionStrings:Oracle.' }
if(-not $NoBrowser){Start-Process $url}
