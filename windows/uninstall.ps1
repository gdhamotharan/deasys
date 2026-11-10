# Removes DEASys's services, shortcuts, firewall rule and program files. Keeps the data and the backups unless -RemoveData
# is given and the confirmation is typed.
#
#   .\uninstall.ps1                       stop and remove services and program files; keep DataDir (database, backups, config)
#   .\uninstall.ps1 -RemoveData           also delete DataDir, after typing the confirmation phrase
#   .\uninstall.ps1 -Portable -InstallDir <folder> -DataDir <folder> [-RemoveData]    test-mode teardown (no administrator rights)
#
# Before anything is removed, the script prints what it removes and what it keeps.
# Logged to DataDir\logs\install.log while that folder exists. No secrets are printed.
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'DEASys'),
    [string]$DataDir = (Join-Path $env:ProgramData 'DEASys'),
    [switch]$RemoveData,
    [string]$ConfirmRemoveData = '',
    [switch]$Portable,
    [switch]$Unattended
)

$ErrorActionPreference = 'Stop'
$pkg = $PSScriptRoot
. (Join-Path $pkg 'deasys-common.ps1')

$ServiceApp = 'DEASys'
$ServiceDb = 'DEASysDB'
$DbUser = 'DEASysDb'
$phrase = 'DELETE DEASYS DATA'

if (-not $Portable -and -not (Test-IsAdministrator)) {
    Write-Host 'DEASys uninstall: run this from an elevated PowerShell (Run as administrator).' -ForegroundColor Red
    exit 1
}
# What is removed and what is kept, in plain words, before anything is changed.
function Show-UninstallPlan {
    Write-Host ''
    Write-Host 'DEASys uninstall. This is what happens:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'REMOVED:'
    if ($Portable) {
        Write-Host '  - the test-mode web server and database processes started from this test folder (if they run)'
    } else {
        Write-Host "  - the Windows service 'DEASys' (web server), if it is installed"
        Write-Host "  - the Windows service 'DEASysDB' (bundled database), if it is installed; its data folder is kept"
        Write-Host "  - the local account $DbUser (used only to run the database service), if it exists"
        Write-Host "  - the firewall rule 'DEASys web interface (TCP)', if it exists"
        Write-Host '  - the Start Menu folder DEASys and the desktop shortcut DEASys.url'
    }
    Write-Host "  - the program files in $InstallDir : deasys-server.exe, ui, previous, postgresql (the bundled PostgreSQL"
    Write-Host '    programs; a reinstall brings them back from the downloads folder or the package), the scripts,'
    Write-Host '    TERMS.txt, postgres-pin.psd1, LICENSE.txt, README-FIRST.txt, VERSION.txt and deasys.iss'
    Write-Host ''
    Write-Host 'KEPT:'
    Write-Host "  - the data folder $DataDir : the database (pgdata), backups, deasys.conf (settings and secrets),"
    Write-Host '    pgsuper.secret, logs, terms-accepted.json, the downloads folder and the run and tmp folders'
    Write-Host '  - nothing in the data folder is deleted unless you give -RemoveData and type the confirmation phrase'
    Write-Host ''
}
Show-UninstallPlan

if (Test-Path $DataDir) { Initialize-DEASysLog -DataDir $DataDir }
Write-DEASysLog "uninstall: installdir=$InstallDir datadir=$DataDir remove-data=$([bool]$RemoveData) portable=$([bool]$Portable)"

$failed = $false
$exe = Join-Path $InstallDir 'deasys-server.exe'

# 1. the application service, or the test-mode process it started
if ((Get-DEASysServiceState -Name $ServiceApp) -ne 'absent') {
    if (Test-Path $exe) { & $exe service stop | Out-Null } else { Stop-Service -Name $ServiceApp -Force -ErrorAction SilentlyContinue }
    if (Test-Path $exe) { & $exe service uninstall | Out-Null } else { & sc.exe delete $ServiceApp | Out-Null }
    Write-DEASysLog "service $ServiceApp removed"
}
$pidFile = Join-Path $DataDir 'run\deasys.pid'
if (Test-Path $pidFile) {
    $procId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq 'deasys-server' -and $proc.Path -and ([IO.Path]::GetFullPath($proc.Path) -eq [IO.Path]::GetFullPath($exe))) {
        Stop-Process -Id $procId -Force
        Write-DEASysLog "test-mode server process $procId stopped"
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# 2. the bundled database service (the data folder stays; a reinstall registers the same cluster again)
$pgBin = $null
# the configuration names the PostgreSQL programs the install used (pg_bin); then the usual places
$confFile = Join-Path $DataDir 'deasys.conf'
$confPgBin = (Read-DEASysConf -Path $confFile)['pg_bin']
foreach ($candidate in @($confPgBin, (Join-Path $InstallDir 'postgresql\bin'), $env:DEASYS_PG_BIN)) {
    if ($candidate -and (Test-Path (Join-Path $candidate 'pg_ctl.exe'))) { $pgBin = $candidate; break }
}
$pgData = Join-Path $DataDir 'pgdata'
if ($Portable) {
    if (Test-Path (Join-Path $pgData 'postmaster.pid')) {
        if (-not $pgBin) {
            Write-DEASysLog -Level WARN -Message 'the test-mode database is running but its pg_ctl location is unknown; stop it by hand (pg_ctl stop -D <pgdata>)'
            $failed = $true
        } else {
            $r = Invoke-DEASysProcess -NoCapture -FilePath (Join-Path $pgBin 'pg_ctl.exe') -ArgumentList @('stop', '-D', $pgData, '-m', 'fast', '-w')
            if ($r.ExitCode -eq 0) { Write-DEASysLog 'test-mode database stopped' } else { Write-DEASysLog -Level WARN -Message 'test-mode database did not stop cleanly'; $failed = $true }
        }
    }
} elseif ((Get-DEASysServiceState -Name $ServiceDb) -ne 'absent') {
    Stop-Service -Name $ServiceDb -Force -ErrorAction SilentlyContinue
    if ($pgBin) {
        $r = Invoke-DEASysProcess -FilePath (Join-Path $pgBin 'pg_ctl.exe') -ArgumentList @('unregister', '-N', $ServiceDb)
    }
    if (-not $pgBin -or (Get-DEASysServiceState -Name $ServiceDb) -ne 'absent') {
        & sc.exe delete $ServiceDb | Out-Null
    }
    Write-DEASysLog "service $ServiceDb removed (its data folder is kept)"
}
if (-not $Portable -and (Get-LocalUser -Name $DbUser -ErrorAction SilentlyContinue)) {
    Remove-LocalUser -Name $DbUser -ErrorAction SilentlyContinue
    Write-DEASysLog "local account $DbUser removed"
}

# 3. firewall rule, shortcuts
if (-not $Portable) {
    Set-DEASysFirewallRule -Port 0 -Remove
    $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\DEASys'
    if (Test-Path $startMenu) { Remove-Item -LiteralPath $startMenu -Recurse -Force -ErrorAction SilentlyContinue }
    $desk = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'DEASys.url'
    if (Test-Path $desk) { Remove-Item -LiteralPath $desk -Force -ErrorAction SilentlyContinue }
    Write-DEASysLog 'firewall rule and shortcuts removed'
}

# 4. program files (never the data folder)
if (Test-Path $InstallDir) {
    foreach ($item in @('deasys-server.exe', 'ui', 'previous', 'postgresql', 'install.ps1', 'uninstall.ps1', 'deasys-common.ps1', 'LICENSE.txt', 'README-FIRST.txt', 'VERSION.txt', 'TERMS.txt', 'postgres-pin.psd1', 'deasys.iss')) {
        $p = Join-Path $InstallDir $item
        if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Continue }
    }
    if (-not (Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
    }
    Write-DEASysLog "program files removed from $InstallDir"
}

# 5. data: kept unless asked, and then only after the typed confirmation
if ($RemoveData) {
    $typed = $ConfirmRemoveData
    if (-not $typed -and -not $Unattended) {
        Write-Host ''
        Write-Host "This deletes the database, every backup and the configuration in $DataDir." -ForegroundColor Yellow
        Write-Host "Type exactly: $phrase"
        $typed = Read-Host 'Confirmation'
    }
    if ($typed -ceq $phrase) {
        Write-DEASysLog -Level WARN -Message "deleting the data folder $DataDir (database, backups, configuration)"
        if (Test-Path $pgData) { Remove-Item -LiteralPath $pgData -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $DataDir) { Write-DEASysLog -Level WARN -Message 'some files in the data folder could not be deleted; remove them by hand'; $failed = $true }
        else { Write-Host 'Data deleted.' }
    } else {
        Write-DEASysLog 'data not deleted: the confirmation did not match'
    }
} else {
    Write-DEASysLog "data kept: $DataDir (database, backups, configuration). Use -RemoveData to delete it."
}

if ($failed) { Write-Host 'Uninstall finished with warnings (see the log).' -ForegroundColor Yellow; exit 1 }
Write-Host 'DEASys is uninstalled.' -ForegroundColor Green
exit 0
