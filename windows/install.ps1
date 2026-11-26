# Installs, upgrades or repairs DEASys on Windows (64-bit). Run from the extracted release folder, or let the installer run it.
#
#   Fresh install (elevated PowerShell). PostgreSQL 13 or later must already run; the installer asks for its connection
#   (host, port, database, login, hidden password) and tests it before it writes anything:
#       .\install.ps1
#   Unattended (the connection from DEASYS_DB_HOST, _PORT, _NAME, _USER, _SSLMODE; the password from DEASYS_DB_PASSWORD or
#   the file named in DEASYS_DB_PASSWORD_FILE):
#       .\install.ps1 -Portable -DbMode existing -Unattended -AcceptTerms
#   Network access for other computers (opens a private-network firewall rule, listens on all addresses):
#       .\install.ps1 -AllowNetwork
#   Upgrade: run the same script from a newer package. The database is backed up first; on a failed health check the
#   previous program files and database are put back.
#   Test mode without administrator rights (no service, no firewall, no shortcuts; ports and folders are yours):
#       .\install.ps1 -Portable -InstallDir <folder> -DataDir <folder> -AppPort 8089
#
# Terms and conditions: TERMS.txt next to this script is shown first. The operator types ACCEPT, or a script passes
# -AcceptTerms (the Inno Setup wizard does, after its I accept button). -Unattended needs -AcceptTerms. The acceptance is
# recorded in DataDir\terms-accepted.json. The terms are asked again only when the package's terms version is newer.
#
# Before anything is changed: the PostgreSQL connection is tested (check-db), then pre-flight checks (administrator rights,
# free ports, conflicting services), then a summary of what will be changed, then "Continue? (Y)".
#
# Phases (used by the Inno Setup installer, which copies its files before it runs the last phase):
#   Prepare  upgrade only: stop the service, back up the database, keep the previous program files in InstallDir\previous
#   Install  everything after the files are in place: database, configuration, migrations, service, health check
#   All      (default) copies the package into InstallDir, then Prepare and Install
#
# Everything is logged to DataDir\logs\install.log. Passwords and keys are never logged or printed.
[CmdletBinding()]
param(
    [ValidateSet('bundled', 'existing')][string]$DbMode,
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'DEASys'),
    [string]$DataDir = (Join-Path $env:ProgramData 'DEASys'),
    [int]$AppPort = 8080,
    [int]$PgPort = 5433,
    [switch]$AllowNetwork,
    [switch]$NoService,
    [switch]$Portable,
    [string]$PgBin,
    [switch]$NoShortcuts,
    [switch]$NoDesktopShortcut,
    [switch]$NoBrowser,
    [switch]$Unattended,
    [switch]$AcceptTerms,
    [ValidateSet('install.ps1', 'installer')][string]$AcceptSource = 'install.ps1',
    [ValidateSet('All', 'Prepare', 'Install')][string]$Phase = 'All'
)

$ErrorActionPreference = 'Stop'
$pkg = $PSScriptRoot
. (Join-Path $pkg 'deasys-common.ps1')

$ServiceApp = 'DEASys'
$ServiceDb = 'DEASysDB'
$exeName = 'deasys-server.exe'


# Moves a folder, retrying when antivirus or the indexer still holds files in it (a freshly unpacked tree is often scanned for a few
# seconds); falls back to copying. Used for the PostgreSQL programs.
function Move-FolderWithRetry {
    param([string]$From, [string]$To)
    for ($i = 1; $i -le 8; $i++) {
        try { Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop; return } catch { Start-Sleep -Seconds (2 * $i) }
    }
    Copy-Item -LiteralPath $From -Destination $To -Recurse -Force -ErrorAction Stop
    Remove-Item -LiteralPath $From -Recurse -Force -ErrorAction SilentlyContinue
}

function Fail([string]$message) {
    Write-DEASysLog -Level ERROR -Message $message
    Write-DEASysLog -Level ERROR -Message ('install stopped. The log is at ' + $script:DEASysLogFile)
    exit 1
}

function Get-PackageVersion {
    param([string]$Folder)
    $file = Join-Path $Folder 'VERSION.txt'
    if (-not (Test-Path $file)) { return 'unknown' }
    $line = Get-Content -LiteralPath $file | Where-Object { $_ -match '^version=' } | Select-Object -First 1
    if ($line) { return $line.Substring(8).Trim() }
    return 'unknown'
}

function Get-AppPaths {
    return @{
        Exe      = Join-Path $InstallDir $exeName
        Ui       = Join-Path $InstallDir 'ui'
        Previous = Join-Path $InstallDir 'previous'
        Conf     = Join-Path $DataDir 'deasys.conf'
        PgData   = Join-Path $DataDir 'pgdata'
        Backups  = Join-Path $DataDir 'backups'
        Run      = Join-Path $DataDir 'run'
        Logs     = Join-Path $DataDir 'logs'
        Tmp      = Join-Path $DataDir 'tmp'
    }
}

function Stop-AppServer {
    param($paths)
    $state = Get-DEASysServiceState -Name $ServiceApp
    if ($state -eq 'Running' -or $state -eq 'StartPending') {
        Write-DEASysLog 'stopping the DEASys service'
        & $paths.Exe service stop | Out-Null
    }
    $pidFile = Join-Path $paths.Run 'deasys.pid'
    if (Test-Path $pidFile) {
        $procId = [int](Get-Content -LiteralPath $pidFile -Raw)
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'deasys-server') {
            Write-DEASysLog "stopping the test server process (pid $procId)"
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
}

function Start-AppServer {
    param($paths, [string]$ConfPath)
    if ($Portable -or $NoService) {
        New-Item -ItemType Directory -Force -Path $paths.Run | Out-Null
        $env:DEASYS_CONFIG = $ConfPath
        try {
            $proc = Start-Process -FilePath $paths.Exe -ArgumentList 'run' -WindowStyle Hidden -PassThru `
                -RedirectStandardOutput (Join-Path $paths.Logs 'server-console.log') `
                -RedirectStandardError (Join-Path $paths.Logs 'server-console.err.log')
        } finally { Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue }
        Set-Content -LiteralPath (Join-Path $paths.Run 'deasys.pid') -Value $proc.Id -Encoding ASCII
        Write-DEASysLog "server started as a process (pid $($proc.Id))"
    } else {
        $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('service', 'start')
        if ($r.ExitCode -ne 0) { throw ('the service did not start: ' + ($r.Output -join ' ')) }
        Write-DEASysLog 'service started'
    }
}

function Test-AppHealth {
    param([int]$Port)
    return (Wait-DEASysHealth -Url "http://127.0.0.1:$Port/health" -TimeoutSeconds 45)
}

function Invoke-Migrate {
    param($paths, [string]$ConfPath)
    $env:DEASYS_CONFIG = $ConfPath
    try {
        $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('migrate')
    } finally { Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue }
    foreach ($l in $r.Output) { Write-DEASysLog "migrate: $l" }
    if ($r.ExitCode -ne 0) { throw 'the database migration failed (see the lines above; the connection details are in deasys.conf)' }
}

# Upgrade: stop, back up the database, keep the previous program files.
function Invoke-PrepareUpgrade {
    param($paths)
    Write-DEASysLog -Level STEP -Message 'upgrade: preparing (stop, backup, keep previous files)'
    Stop-AppServer -paths $paths
    New-Item -ItemType Directory -Force -Path $paths.Backups, $paths.Run | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $paths.Backups "deasys-$stamp.dump"
    $env:DEASYS_CONFIG = $paths.Conf
    # -PgBin reaches the backup now (the configuration is written later in the install): the same PostgreSQL bin folder as the server
    if ($PgBin) { $env:DEASYS_PG_BIN = $PgBin }
    try {
        if ($DbMode -eq 'bundled' -or (Get-DEASysServiceState -Name $ServiceDb) -ne 'absent') { Start-BundledDb -paths $paths }
        $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('backup', $backup)
    } finally {
        Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue
        Remove-Item Env:\DEASYS_PG_BIN -ErrorAction SilentlyContinue
    }
    if ($r.ExitCode -ne 0) { throw ('the database backup failed; the upgrade is not applied: ' + ($r.Output -join ' ')) }
    Write-DEASysLog "database backed up to $backup"
    $script:BackupFile = $backup
    # the Install phase may run in another process (Inno Setup): it reads the backup name from here
    Set-Content -LiteralPath (Join-Path $paths.Run 'last-backup.txt') -Value $backup -Encoding UTF8

    if (Test-Path $paths.Exe) {
        if (Test-Path $paths.Previous) { Remove-Item -LiteralPath $paths.Previous -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $paths.Previous | Out-Null
        Copy-Item -LiteralPath $paths.Exe -Destination $paths.Previous -Force
        if (Test-Path $paths.Ui) { Copy-Item -LiteralPath $paths.Ui -Destination $paths.Previous -Recurse -Force }
        Write-DEASysLog 'previous program files kept for rollback'
    }
}

# Copies the package (program files only; the data folder is never touched) into InstallDir.
function Copy-PackageFiles {
    param($paths)
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $fromDir = [IO.Path]::GetFullPath($pkg).TrimEnd('\')
    $toDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    if ([string]::Equals($fromDir, $toDir, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    Write-DEASysLog -Level STEP -Message "copying program files to $InstallDir"
    Copy-Item -LiteralPath (Join-Path $pkg $exeName) -Destination $InstallDir -Force
    if (Test-Path (Join-Path $pkg 'ui')) {
        if (Test-Path $paths.Ui) { Remove-Item -LiteralPath $paths.Ui -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $pkg 'ui') -Destination $InstallDir -Recurse -Force
    }
    foreach ($f in 'install.ps1', 'uninstall.ps1', 'deasys-common.ps1', 'LICENSE.txt', 'README-FIRST.txt', 'VERSION.txt', 'TERMS.txt') {
        $src = Join-Path $pkg $f
        if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination $InstallDir -Force }
    }
}

function Resolve-PgBin {
    if ($PgBin) { return $PgBin }
    if (Test-Path (Join-Path $InstallDir 'postgresql\bin\initdb.exe')) { return (Join-Path $InstallDir 'postgresql\bin') }
    if (Test-Path (Join-Path $pkg 'postgresql\bin\initdb.exe')) { return (Join-Path $pkg 'postgresql\bin') }
    if ($env:DEASYS_PG_BIN -and (Test-Path (Join-Path $env:DEASYS_PG_BIN 'initdb.exe'))) { return $env:DEASYS_PG_BIN }
    return $null
}


# Starts the bundled database (service DEASysDB, or pg_ctl for test mode) if it is not running.
function Start-BundledDb {
    param($paths)
    if (-not $script:PgBinDir) { $script:PgBinDir = Resolve-PgBin }
    $pgBinDir = $script:PgBinDir
    if (-not $pgBinDir) { throw 'no PostgreSQL programs found for the bundled database' }
    $probe = Invoke-DEASysProcess -FilePath (Join-Path $pgBinDir 'pg_isready.exe') -ArgumentList @('-h', '127.0.0.1', '-p', "$PgPort")
    if ($probe.ExitCode -eq 0) { return }
    if ($Portable -or $NoService) {
        # postgres.exe itself, not pg_ctl start: the output goes to the log and the process is not waited for
        New-Item -ItemType Directory -Force -Path $paths.Run | Out-Null
        $pgLog = Join-Path $paths.Logs 'postgres.log'
        $pgProc = Start-Process -FilePath (Join-Path $pgBinDir 'postgres.exe') -ArgumentList @('-D', $paths.PgData) -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $pgLog -RedirectStandardError ($pgLog + '.err')
        Set-Content -LiteralPath (Join-Path $paths.Run 'postgres.pid') -Value $pgProc.Id -Encoding ASCII
        $ready = $false
        $deadline = (Get-Date).AddSeconds(60)
        while (-not $ready -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $probe = Invoke-DEASysProcess -FilePath (Join-Path $pgBinDir 'pg_isready.exe') -ArgumentList @('-h', '127.0.0.1', '-p', "$PgPort")
            $ready = ($probe.ExitCode -eq 0)
        }
        if (-not $ready) { throw 'the bundled database did not start (see logs\postgres.log)' }
    } else {
        Start-Service -Name $ServiceDb
    }
    Write-DEASysLog 'bundled database started'
}


function Get-ConfText {
    param([string]$Key, [hashtable]$Conf)
    if ($Conf.ContainsKey($Key)) { return [string]$Conf[$Key] }
    return ''
}


# The connection values of the existing PostgreSQL server. Unattended: from DEASYS_DB_* environment variables; the password comes
# from DEASYS_DB_PASSWORD or from the file named in DEASYS_DB_PASSWORD_FILE (never from the command line). Interactive: prompts,
# the password typed hidden. The SSL mode defaults to prefer for this computer and to require for any other host.
function Read-DbConnectionValues {
    if ($Unattended) {
        $v = @{ Host = $env:DEASYS_DB_HOST; Port = $env:DEASYS_DB_PORT; Name = $env:DEASYS_DB_NAME; User = $env:DEASYS_DB_USER; SslMode = $env:DEASYS_DB_SSLMODE; Password = $env:DEASYS_DB_PASSWORD }
        if (-not $v.Password -and $env:DEASYS_DB_PASSWORD_FILE) {
            if (-not (Test-Path -LiteralPath $env:DEASYS_DB_PASSWORD_FILE)) { throw 'DEASYS_DB_PASSWORD_FILE names a file that does not exist' }
            $v.Password = (Get-Content -LiteralPath $env:DEASYS_DB_PASSWORD_FILE -Raw).TrimEnd("`r", "`n")
        }
        if (-not $v.Password) { throw 'an unattended install needs the database password: set DEASYS_DB_PASSWORD or DEASYS_DB_PASSWORD_FILE' }
        if (-not $v.Name -or -not $v.User) { throw 'an unattended install needs DEASYS_DB_NAME and DEASYS_DB_USER' }
    } else {
        Write-Host ''
        Write-Host 'PostgreSQL connection. The database and the login must already exist (DEASys creates only its tables).' -ForegroundColor Cyan
        $h = Read-Host 'Host (default localhost)'
        $p = Read-Host 'Port (default 5432)'
        $d = Read-Host 'Database name'
        $u = Read-Host 'User name (login)'
        $sec = Read-Host 'Password (hidden)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $s = Read-Host 'SSL mode: prefer, require or disable (default: prefer here, require for another host)'
        $v = @{ Host = $h; Port = $p; Name = $d; User = $u; SslMode = $s; Password = $pw }
    }
    if (-not $v.Host) { $v.Host = 'localhost' }
    if (-not $v.Port) { $v.Port = '5432' }
    if ($v.Port -notmatch '^\d+$' -or [int]$v.Port -lt 1 -or [int]$v.Port -gt 65535) { throw 'the port must be a number from 1 to 65535' }
    if (-not $v.Name -or -not $v.User) { throw 'the database name and the user name are required' }
    if (-not $v.SslMode) { $v.SslMode = $(if ($v.Host -in @('localhost', '127.0.0.1', '::1')) { 'prefer' } else { 'require' }) }
    if ($v.SslMode -notin @('disable', 'allow', 'prefer', 'require', 'verify-ca', 'verify-full')) { throw 'the SSL mode is not one of the allowed values' }
    return $v
}

# The connection string for the values. User, password and database name are percent-encoded, so @ : / # % spaces and quotes in them
# are read as text. An IPv6 host address is written in brackets.
function ConvertTo-DbUrl {
    param([hashtable]$Values)
    $hostName = if ($Values.Host -match ':') { '[' + $Values.Host + ']' } else { $Values.Host }
    return 'postgres://' + [Uri]::EscapeDataString($Values.User) + ':' + [Uri]::EscapeDataString($Values.Password) + '@' + $hostName + ':' + $Values.Port +
        '/' + [Uri]::EscapeDataString($Values.Name) + '?sslmode=' + $Values.SslMode
}

# The prerequisite check: the server answers, the password is accepted, the database exists, the version is supported and the
# role can create the tables. It runs the server's check-db command with the connection in the environment (nothing is written,
# the password is never logged). Returns @{ Ok; Text } where Text is the server's plain answer.
function Test-DbUrl {
    param([string]$Url)
    $exe = if (Test-Path (Join-Path $pkg $exeName)) { Join-Path $pkg $exeName } else { Join-Path $InstallDir $exeName }
    # the connection goes to the check in the environment; a value the operator set is put back afterwards
    $saved = $env:DEASYS_DATABASE_URL
    $env:DEASYS_DATABASE_URL = $Url
    try { $r = Invoke-DEASysProcess -FilePath $exe -ArgumentList @('check-db') }
    finally { if ($null -eq $saved) { Remove-Item Env:\DEASYS_DATABASE_URL -ErrorAction SilentlyContinue } else { $env:DEASYS_DATABASE_URL = $saved } }
    $text = (@($r.Output) -join "`n").Trim()
    return @{ Ok = ($r.ExitCode -eq 0); Text = $text }
}

# The backup of an upgrade runs pg_dump, which must be of the same PostgreSQL major version as the server. Returns "" when it
# matches, otherwise the plain reason. pg_dump is found from the pg_bin setting (or -PgBin), then from PATH.
function Test-PgDumpVersion {
    param([string]$ServerText, [string]$PgBinSetting)
    $serverMajor = if ($ServerText -match 'PostgreSQL (\d+)') { $Matches[1] } else { '' }
    $dir = if ($PgBin) { $PgBin } else { $PgBinSetting }
    $dump = if ($dir -and (Test-Path (Join-Path $dir 'pg_dump.exe'))) { Join-Path $dir 'pg_dump.exe' } else { $cmd = Get-Command pg_dump.exe -ErrorAction SilentlyContinue; if ($cmd) { $cmd.Source } }
    if (-not $dump) { return 'pg_dump (the PostgreSQL client tools) was not found. Add the PostgreSQL bin folder to PATH, or pass -PgBin <that folder>. The upgrade backup needs it.' }
    $v = (& $dump --version 2>&1) -join ' '
    $dumpMajor = if ($v -match '(\d+)(\.\d+)?') { $Matches[1] } else { '' }
    if ($serverMajor -and $dumpMajor -and $serverMajor -ne $dumpMajor) {
        return "pg_dump is version $dumpMajor but the server is $serverMajor. They must match: use the PostgreSQL $serverMajor bin folder (-PgBin) for the backup."
    }
    return ''
}

# Establishes the PostgreSQL connection before anything is written. An upgrade keeps the connection it already has and asks
# again only when that connection fails. Interactive: a failure is explained and the values are asked again. Unattended: a failure stops.
function Get-VerifiedDbUrl {
    param($existingConf)
    # advanced: a complete connection string in DEASYS_DATABASE_URL is used as it is (checked the same way)
    if ($env:DEASYS_DATABASE_URL) {
        $given = $env:DEASYS_DATABASE_URL
        $check = Test-DbUrl -Url $given
        if (-not $check.Ok) { Fail "the connection string in DEASYS_DATABASE_URL does not work: $($check.Text). Nothing was changed." }
        Write-DEASysLog "PostgreSQL: the connection string from DEASYS_DATABASE_URL answers ($($check.Text)); it is not logged"
        $script:DbCheckText = $check.Text
        return $given
    }
    $existing = Get-ConfText 'database_url' $existingConf
    if ($script:IsUpgrade -and $existing) {
        $check = Test-DbUrl -Url $existing
        if ($check.Ok) {
            Write-DEASysLog "PostgreSQL: the connection of the existing installation answers ($($check.Text))"
            $dumpProblem = Test-PgDumpVersion -ServerText $check.Text -PgBinSetting (Get-ConfText 'pg_bin' $existingConf)
            if ($dumpProblem) { Fail "the upgrade is not started: $dumpProblem Nothing was changed." }
            $script:DbCheckText = $check.Text
            return $existing
        }
        Write-DEASysLog -Level WARN -Message "the existing connection does not answer: $($check.Text)"
        if ($Unattended) { Fail 'the existing database connection in deasys.conf does not work (see above). Fix the database or the settings, then run the installer again.' }
        Write-Host 'The connection in deasys.conf does not work. Enter the connection again.' -ForegroundColor Yellow
    }
    while ($true) {
        $values = Read-DbConnectionValues
        $url = ConvertTo-DbUrl -Values $values
        $check = Test-DbUrl -Url $url
        if ($check.Ok) {
            Write-DEASysLog "PostgreSQL: $($values.Host):$($values.Port)/$($values.Name) as $($values.User) (sslmode $($values.SslMode)) answers; the password is not logged"
            $dumpProblem = Test-PgDumpVersion -ServerText $check.Text -PgBinSetting ''
            if ($dumpProblem) { Write-DEASysLog -Level WARN -Message "$dumpProblem (an upgrade of this installation will need it)" }
            $script:DbCheckText = $check.Text
            return $url
        }
        Write-DEASysLog -Level ERROR -Message "PostgreSQL check failed: $($check.Text)"
        Write-Host $check.Text -ForegroundColor Red
        if ($Unattended) { Fail 'the PostgreSQL prerequisite is not met (see the reason above). Nothing was changed.' }
        $again = [string](Read-Host 'Press Enter to enter the connection again, or type Q to stop')
        if ($again.Trim() -match '^[Qq]') { Fail 'stopped at the PostgreSQL check. Nothing was changed.' }
    }
}

function Invoke-Rollback {
    param($paths, [string]$Reason, [switch]$RestoreDb)
    Write-DEASysLog -Level WARN -Message "rolling back: $Reason"
    try { Stop-AppServer -paths $paths } catch { }
    if (-not (Test-Path (Join-Path $paths.Previous $exeName))) {
        Write-DEASysLog -Level ERROR -Message 'no previous files are kept; the rollback cannot be completed. Restore the backup by hand.'
        return
    }
    Copy-Item -LiteralPath (Join-Path $paths.Previous $exeName) -Destination $paths.Exe -Force
    if (Test-Path (Join-Path $paths.Previous 'ui')) {
        if (Test-Path $paths.Ui) { Remove-Item -LiteralPath $paths.Ui -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $paths.Previous 'ui') -Destination $InstallDir -Recurse -Force
    }
    Write-DEASysLog 'previous program files restored'
    if ($RestoreDb -and $script:BackupFile -and (Test-Path $script:BackupFile)) {
        $env:DEASYS_CONFIG = $paths.Conf
        try {
            $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('restore', $script:BackupFile, '--force')
        } finally { Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue }
        if ($r.ExitCode -eq 0) { Write-DEASysLog 'database restored from the backup taken before the upgrade' }
        else { Write-DEASysLog -Level ERROR -Message 'the database could not be restored automatically; use the backup file by hand' }
    }
    try { Start-AppServer -paths $paths -ConfPath $paths.Conf } catch { Write-DEASysLog -Level WARN -Message "restart after rollback: $($_.Exception.Message)" }
    if (Test-AppHealth -Port $AppPort) { Write-DEASysLog 'the previous version is running again' }
}

# ---------------------------------------------------------------- terms and conditions
$MinFreeBytes = [int64](1.5 * 1GB)

# The version on the 'Version:' line of TERMS.txt, or $null.
function Get-TermsVersion {
    param([Parameter(Mandatory = $true)][string]$File)
    foreach ($line in @(Get-Content -LiteralPath $File -Encoding UTF8)) {
        if ($line -match '^Version:\s*(\S.*?)\s*$') { return $Matches[1] }
    }
    return $null
}

# The yyyy-MM-dd prefix of a terms version as a date, or $null when it has none.
function Get-TermsDate {
    param([string]$Version)
    if ($Version -and $Version -match '^(\d{4}-\d{2}-\d{2})') {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($Matches[1], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    return $null
}

# The record of an earlier acceptance, or $null (no file, or a file that cannot be read).
function Read-TermsRecord {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch {
        Write-Host "note: the terms record $Path cannot be read; the terms will be shown again" -ForegroundColor Yellow
        return $null
    }
}

# True when the terms must be shown and accepted: no record, an unreadable record, or a package whose terms version is
# newer than the recorded one, or a different version dated the same day (a revision; an unparseable version counts as newer).
# Equal or older package versions do not ask again.
function Test-TermsNeedAccept {
    param([string]$PackageVersion, $Record)
    if ($null -eq $Record -or -not $Record.version) { return $true }
    $recorded = [string]$Record.version
    if ($recorded -eq $PackageVersion) { return $false }
    $pd = Get-TermsDate -Version $PackageVersion
    $rd = Get-TermsDate -Version $recorded
    if ($null -eq $pd -or $null -eq $rd) { return $true }
    if ($pd -eq $rd) { return $true }   # a different version on the same day is a revision of the text: ask again
    return ($pd -gt $rd)
}

# One key for the paged reader: a key press on a console, a typed line when the input is redirected.
function Read-TermsPageKey {
    if (-not [Console]::IsInputRedirected) {
        try {
            $k = [Console]::ReadKey($true)
            return [string]$k.KeyChar
        } catch { }
    }
    return [string](Read-Host)
}

# Shows the whole terms text, 20 lines per page. Q stops the reading (the acceptance is still asked).
function Show-Terms {
    param([Parameter(Mandatory = $true)][string]$File, [Parameter(Mandatory = $true)][string]$Version)
    $lines = @(Get-Content -LiteralPath $File -Encoding UTF8)
    $pageSize = 20
    Write-Host ''
    Write-Host "DEASYS TERMS AND CONDITIONS (version $Version)" -ForegroundColor Cyan
    Write-Host "The whole text is also in the package file: $File"
    Write-Host ''
    $i = 0
    while ($i -lt $lines.Count) {
        $end = [Math]::Min($i + $pageSize, $lines.Count)
        for ($j = $i; $j -lt $end; $j++) { Write-Host $lines[$j] }
        $i = $end
        if ($i -lt $lines.Count) {
            Write-Host ''
            Write-Host '-- press a key for the next page, or Q to stop reading --' -ForegroundColor Yellow
            $key = Read-TermsPageKey
            if ($key -match '^[Qq]$') { break }
        }
    }
    Write-Host ''
}

# Shows the terms and asks for ACCEPT. Returns $true only when the operator typed ACCEPT (any case).
function Confirm-TermsInteractive {
    param([Parameter(Mandatory = $true)][string]$File, [Parameter(Mandatory = $true)][string]$Version)
    Show-Terms -File $File -Version $Version
    Write-Host 'To accept these terms, type ACCEPT and press Enter. Anything else stops the installation; nothing is changed.'
    # Read-Host returns nothing at the end of redirected input: that is a refusal, not an error
    $answer = Read-Host 'Type ACCEPT to accept'
    if ($null -eq $answer) { return $false }
    return (([string]$answer).Trim() -ieq 'ACCEPT')
}

# Writes the acceptance record. No secret is written. The file is replaced in one step.
function Write-TermsRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Method,
        [string]$ProgramVersion
    )
    $rec = [ordered]@{
        version        = $Version
        acceptedUtc    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        windowsUser    = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        machine        = $env:COMPUTERNAME
        source         = $Source
        method         = $Method
        programVersion = $ProgramVersion
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ($rec | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---------------------------------------------------------------- pre-flight helpers
# Free bytes on the drive of a path, or $null when the drive cannot be read (for example a network share).
function Get-FreeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        $di = New-Object System.IO.DriveInfo $root
        return [int64]$di.AvailableFreeSpace
    } catch { return $null }
}

# The processes that listen on a TCP port: Get-NetTCPConnection, or netstat -ano when that cmdlet is missing.
function Get-PortHolders {
    param([Parameter(Mandatory = $true)][int]$Port)
    $ids = @()
    if (Get-Command -Name Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $ids = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.OwningProcess })
    } else {
        foreach ($line in @(& netstat.exe -ano -p TCP)) {
            if ($line -match "^\s*TCP\s+\S+:$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") { $ids += [int]$Matches[1] }
        }
    }
    $holders = @()
    foreach ($id in @($ids | Where-Object { $_ -gt 0 } | Select-Object -Unique)) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        $exePath = $null
        $pname = '(unknown)'
        if ($p) {
            $pname = $p.ProcessName
            try { $exePath = $p.Path } catch { $exePath = $null }
        }
        $cmd = ''
        try {
            $ci = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $id" -ErrorAction Stop
            if ($ci.CommandLine) { $cmd = [string]$ci.CommandLine }
        } catch { }
        $holders += [pscustomobject]@{ Id = $id; Name = $pname; Path = $exePath; CommandLine = $cmd }
    }
    return @($holders)
}

# Returns a problem text when the port is taken by something other than this installation, else $null.
# In an upgrade the DEASys server (its executable under InstallDir) and the bundled database (postgres under DataDir\pgdata)
# are fine: the upgrade stops them.
function Test-PortForPreflight {
    param([int]$Port, [string]$Label, [ValidateSet('web', 'db')][string]$Kind, [hashtable]$Paths)
    $holders = @(Get-PortHolders -Port $Port)
    if ($holders.Count -eq 0) {
        Write-DEASysLog "$Label port ${Port}: free"
        return $null
    }
    $busy = @()
    foreach ($h in $holders) {
        $own = $false
        if ($script:IsUpgrade) {
            if ($Kind -eq 'web' -and $h.Path) {
                $ownExe = [IO.Path]::GetFullPath((Join-Path $InstallDir $exeName))
                if ([string]::Equals([IO.Path]::GetFullPath($h.Path), $ownExe, [StringComparison]::OrdinalIgnoreCase)) { $own = $true }
            }
            if ($Kind -eq 'db' -and $h.Name -eq 'postgres' -and $h.CommandLine -and
                $h.CommandLine.IndexOf($Paths.PgData, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $own = $true }
        }
        if ($own) {
            Write-DEASysLog "$Label port $Port is held by this DEASys installation (pid $($h.Id)); the upgrade stops it"
            continue
        }
        $desc = "process $($h.Name) (pid $($h.Id))"
        if ($h.Path) { $desc += " at $($h.Path)" }
        $busy += $desc
    }
    if ($busy.Count -eq 0) { return $null }
    return ("the $Label port $Port is in use by " + ($busy -join '; ') + '. Stop that program or choose another port (-AppPort or -PgPort).')
}


# ---------------------------------------------------------------- pre-flight and summary
# Runs every check that does not change anything. Each result is logged; any failure stops the install before a change.
function Invoke-Preflight {
    param([hashtable]$Paths)
    $problems = New-Object System.Collections.Generic.List[string]
    Write-DEASysLog -Level STEP -Message 'pre-flight checks (these change nothing)'

    # disk space
    if ($DbMode -eq 'bundled') {
        foreach ($item in @(@('program folder', $InstallDir), @('data folder', $DataDir))) {
            $free = Get-FreeBytes -Path $item[1]
            if ($null -eq $free) {
                Write-DEASysLog -Level WARN -Message "the free space of the drive of the $($item[0]) ($($item[1])) cannot be read; check it by hand"
                continue
            }
            $freeGb = [math]::Round($free / 1GB, 2)
            if ($free -lt $MinFreeBytes) { $problems.Add("the drive of the $($item[0]) ($($item[1])) has $freeGb GB free; at least 1.5 GB is needed") }
            else { Write-DEASysLog "free space on the drive of the $($item[0]): $freeGb GB (at least 1.5 GB needed): ok" }
        }
    }

    # administrator rights were checked before the terms; ports next
    $p1 = Test-PortForPreflight -Port $AppPort -Label 'web' -Kind 'web' -Paths $Paths
    if ($p1) { $problems.Add($p1) }

    # conflicting service names: ours on an upgrade is fine, anything else stops the install
    foreach ($svc in @($ServiceApp, $ServiceDb)) {
        $st = Get-DEASysServiceState -Name $svc
        if ($st -eq 'absent') { continue }
        if ($script:IsUpgrade) { Write-DEASysLog "service $svc exists ($st): part of this installation (upgrade)"; continue }
        $problems.Add("a Windows service named $svc already exists ($st), and $InstallDir has no DEASys installation to upgrade. Remove that service or choose other folders.")
    }

    # PostgreSQL is a prerequisite: its server was checked before anything was written (Get-VerifiedDbUrl). Nothing is downloaded.
    if ($DbMode -eq 'existing') { Write-DEASysLog "PostgreSQL prerequisite: checked before the install ($($script:DbCheckText))" }

    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-DEASysLog -Level ERROR -Message ('pre-flight: ' + $p) }
        Fail 'the pre-flight checks failed. Nothing was changed.'
    }
    Write-DEASysLog 'pre-flight checks passed'
}

# Plain-English list of what the install will change. Printed and logged; the operator confirms it unless -Unattended.
function Show-ChangeSummary {
    param([hashtable]$Paths, [bool]$TermsWillBeRecorded)
    Write-DEASysLog -Level STEP -Message 'what will be changed'
    Write-DEASysLog "  Program folder: $InstallDir - the web server program, the web interface (ui), the scripts, TERMS.txt, the licence and the readme."
    if ($script:IsUpgrade) { Write-DEASysLog "    upgrade: the database is backed up first; the previous program files are kept in $($Paths.Previous)" }
    Write-DEASysLog "  Data folder: $DataDir - kept on upgrades and never deleted by the install:"
    Write-DEASysLog '    deasys.conf (settings and secrets), logs, backups, run, tmp, terms-accepted.json'
    if ($DbMode -eq 'bundled') { Write-DEASysLog '    pgdata (the database of the earlier bundled installation, kept as it is)' }
    if ($TermsWillBeRecorded) { Write-DEASysLog "  Terms record: $(Join-Path $DataDir 'terms-accepted.json') is written (version and time of your acceptance)" }
    if ($Portable) {
        Write-DEASysLog '  Test mode (-Portable): no Windows services, no firewall rule, no shortcuts, no local account.'
    } else {
        Write-DEASysLog "  Service 'DEASys': the web server; runs as LocalService; starts automatically with Windows."
        if ($AllowNetwork) { Write-DEASysLog "  Firewall rule 'DEASys web interface (TCP)': allows TCP $AppPort on private and domain networks." }
        else { Write-DEASysLog "  Firewall: no rule is added (an existing rule of that name is removed); only this computer can open DEASys." }
        if ($NoShortcuts) { Write-DEASysLog '  Shortcuts: none (-NoShortcuts).' }
        else {
            Write-DEASysLog "  Start Menu shortcut 'DEASys' (folder DEASys)$(if ($NoDesktopShortcut) { '' } else { ' and a desktop shortcut' }): open http://localhost:$AppPort/"
        }
    }
    Write-DEASysLog "  Web address: http://localhost:$AppPort/ $(if ($AllowNetwork -and -not $Portable) { '(all network addresses)' } else { '(this computer only)' })"
    if ($DbMode -eq 'bundled') { Write-DEASysLog '  Database: the PostgreSQL of the earlier bundled installation (kept as it is; its service is not changed).' }
    else { Write-DEASysLog '  Database: the PostgreSQL server you name (checked before anything is written; DEASys installs no database server).' }
}

# ---------------------------------------------------------------- main
Write-Host ""
Write-Host "DEASys installer. The installer installs DEASys only; it downloads nothing." -ForegroundColor Cyan
Write-Host "Before you start, these must be in place (the installer checks them and stops with the reason if one is missing):"
Write-Host "  1. Windows 10 or 11, 64-bit, and administrator rights (not needed with -Portable, the test mode)."
Write-Host "  2. PostgreSQL 16 (13 or later works) installed and running, from its official download."
Write-Host "  3. An empty database and a login for DEASys (CREATE ROLE ... LOGIN PASSWORD ...; CREATE DATABASE ... OWNER ...;)."
Write-Host "  The installer asks for the host, port, database, login and password, and tests the connection before it writes anything."
Write-Host "  See README-FIRST.txt for the statements and the complete list."
Write-Host ""
if (-not $Portable -and -not (Test-IsAdministrator)) {
    Write-Host 'DEASys install: run this from an elevated PowerShell (Run as administrator), or add -Portable for a test install.' -ForegroundColor Red
    exit 1
}
if ($Portable) { $NoService = $true; $NoShortcuts = $true; $NoBrowser = $true }
if (-not (Test-Path (Join-Path $pkg $exeName)) -and -not (Test-Path (Join-Path $InstallDir $exeName))) {
    Write-Host "DEASys install: $exeName was not found in $pkg or $InstallDir." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $pkg 'ui\index.html')) -and -not (Test-Path (Join-Path $InstallDir 'ui\index.html'))) {
    # the server still runs with its embedded interface; a folder UI is optional
    Write-Host 'note: no ui folder in the package; the embedded web interface is used.' -ForegroundColor Yellow
}

# ---- terms and conditions (before the pre-flight checks and before anything is changed)
if ($Unattended -and -not $AcceptTerms) {
    Write-Host 'DEASys install: an unattended install needs -AcceptTerms. Read TERMS.txt in the package first; pass -AcceptTerms only if you accept it. Nothing was changed.' -ForegroundColor Red
    exit 1
}
$termsFile = Join-Path $pkg 'TERMS.txt'
if (-not (Test-Path -LiteralPath $termsFile)) {
    Write-Host "DEASys install: TERMS.txt was not found in $pkg. The package is incomplete; nothing was changed." -ForegroundColor Red
    exit 1
}
$termsVersion = Get-TermsVersion -File $termsFile
if (-not $termsVersion) {
    Write-Host "DEASys install: TERMS.txt has no 'Version:' line. The package is incomplete; nothing was changed." -ForegroundColor Red
    exit 1
}
$termsRecordFile = Join-Path $DataDir 'terms-accepted.json'
$termsRecord = Read-TermsRecord -Path $termsRecordFile
$termsNeedAccept = Test-TermsNeedAccept -PackageVersion $termsVersion -Record $termsRecord
$termsSource = 'install.ps1'
$termsMethod = 'typed ACCEPT'
if ($termsNeedAccept) {
    if ($AcceptTerms) {
        $termsMethod = 'switch -AcceptTerms'
        if ($AcceptSource -eq 'installer') { $termsSource = 'installer' }
    } else {
        if (-not (Confirm-TermsInteractive -File $termsFile -Version $termsVersion)) {
            Write-Host 'The terms were not accepted (ACCEPT was not typed). The installation stopped; nothing was changed.' -ForegroundColor Red
            exit 1
        }
    }
}

$paths = Get-AppPaths
$script:BackupFile = $null
$script:ProgramChanged = $false
$script:DbTouched = $false
$script:IsUpgrade = (Test-Path (Join-Path $InstallDir $exeName)) -and (Test-Path (Join-Path $DataDir 'deasys.conf'))
$script:DbUrl = $null
$script:DbCheckText = ''
$lastBackup = Join-Path $paths.Run 'last-backup.txt'
if ($Phase -eq 'Install' -and (Test-Path $lastBackup)) {
    $script:BackupFile = (Get-Content -LiteralPath $lastBackup -Raw).Trim()
}
$script:DbUserSecret = $null
Initialize-DEASysLog -DataDir $DataDir
$version = Get-PackageVersion -Folder $pkg
Write-DEASysLog "install: phase=$Phase package=$version installdir=$InstallDir datadir=$DataDir portable=$([bool]$Portable)"
if ($termsNeedAccept) {
    Write-DEASysLog "terms: version $termsVersion accepted by $termsMethod"
} else {
    Write-DEASysLog "terms: version $termsVersion was accepted earlier ($([string]$termsRecord.acceptedUtc), version $([string]$termsRecord.version)); not asked again"
}

try {
    # an upgrade is an installation that completed: a program folder without a configuration (an interrupted install) is not one
    $isUpgrade = $script:IsUpgrade
    if ($isUpgrade) {
        $ver = (& $paths.Exe version 2>$null) -join ' '
        Write-DEASysLog "installed program: $ver"
    }
    # An installation whose database is the bundled one (an earlier release) keeps it: its database is started, not changed.
    # Every new installation uses an existing PostgreSQL server that the operator provides; DEASys installs no database.
    $existingConf = @{}
    if (Test-Path $paths.Conf) { $existingConf = Read-DEASysConf -Path $paths.Conf }
    $legacyBundled = ((Get-ConfText 'database_url' $existingConf) -match '127\.0\.0\.1:') -and (Test-Path $paths.PgData)
    if ($legacyBundled) { $DbMode = 'bundled' }
    else {
        if ($DbMode -eq 'bundled') { Fail 'DEASys no longer installs a database. Install PostgreSQL 16 (or later) first and run this installer again; README-FIRST.txt lists the prerequisites.' }
        $DbMode = 'existing'
    }
    if (-not $Unattended -and -not $Portable -and -not $isUpgrade -and -not $PSBoundParameters.ContainsKey('AllowNetwork')) {
        # the network question is asked in an interactive fresh install
        $net = Read-Host 'Allow other computers on your network to open DEASys? (y/N)'
        if ($net -match '^[Yy]') { $AllowNetwork = $true }
    }
    Write-DEASysLog "database: $(if ($DbMode -eq 'bundled') { 'the earlier bundled installation (kept)' } else { 'an existing PostgreSQL server (prerequisite)' }); web address: http://localhost:$AppPort/ ; network: $([bool]$AllowNetwork)"

    # the PostgreSQL connection is verified before anything is written (a new install asks for it; an upgrade reuses its own)
    if ($DbMode -eq 'existing') { $script:DbUrl = Get-VerifiedDbUrl -existingConf $existingConf }

    # ---- pre-flight (nothing is changed yet), then the summary and the confirmation
    Invoke-Preflight -Paths $paths
    Show-ChangeSummary -Paths $paths -TermsWillBeRecorded $termsNeedAccept
    if (-not $Unattended) {
        $go = [string](Read-Host 'Continue? (type Y to continue)')
        if ($go.Trim() -notmatch '^[Yy]$') { Fail 'not continued. Nothing was changed.' }
    } else {
        Write-DEASysLog 'unattended: the summary is logged and the install continues'
    }

    # ---- the change phase starts here
    if ($termsNeedAccept) {
        Write-TermsRecord -Path $termsRecordFile -Version $termsVersion -Source $termsSource -Method $termsMethod -ProgramVersion $version
        Write-DEASysLog "terms: version $termsVersion recorded in $termsRecordFile"
    }

    if ($Phase -eq 'All' -or $Phase -eq 'Prepare') {
        if ($isUpgrade) { Invoke-PrepareUpgrade -paths $paths }
    }
    if ($Phase -eq 'Prepare') { Write-DEASysLog 'prepare phase complete'; exit 0 }

    if ($Phase -eq 'All') {
        if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        $script:ProgramChanged = $true
        Copy-PackageFiles -paths $paths
    }
    if ($Phase -eq 'Install') { $script:ProgramChanged = $true }   # the installer copied the files before this phase
    New-Item -ItemType Directory -Force -Path $paths.Logs, $paths.Backups, $paths.Run, $paths.Tmp | Out-Null

    # ---- database
    $existingConf = Read-DEASysConf -Path $paths.Conf
    $jwt = Get-ConfText 'jwt_key' $existingConf
    if (-not $jwt) { $jwt = New-DEASysJwtKey }
    $confValues = [ordered]@{}
    if ($DbMode -eq 'bundled') {
        # the earlier bundled installation: its database and its connection are kept; the cluster is only started
        $existingUrl = Get-ConfText 'database_url' $existingConf
        if ($existingUrl -match ':(\d+)/') { $PgPort = [int]$Matches[1] }
        $script:PgBinDir = Resolve-PgBin
        if (-not $script:PgBinDir) { Fail 'the earlier bundled installation needs its PostgreSQL programs (postgresql\bin in the program folder), and they are missing. Nothing was changed by this run.' }
        Start-BundledDb -paths $paths
        $confValues['database_url'] = $existingUrl
        $confValues['pg_bin'] = $script:PgBinDir
    } else {
        $confValues['database_url'] = $script:DbUrl
        if ($PgBin) { $confValues['pg_bin'] = $PgBin }
    }

    $listen = if ($AllowNetwork -and -not $Portable) { "0.0.0.0:$AppPort" } else { "127.0.0.1:$AppPort" }
    $confValues['listen_addr'] = $listen
    $confValues['jwt_key'] = $jwt
    $confValues['log_dir'] = $paths.Logs
    $confValues['ui_dir'] = $paths.Ui
    # an upgrade keeps the owner's settings: a value the owner set (public_url, auto_migrate) stays, and so does any key this
    # installer does not write. The generated public address follows the web port while it is still the generated one.
    $ownedPublic = Get-ConfText 'public_url' $existingConf
    if (-not $ownedPublic -or $ownedPublic -match '^http://localhost:\d+$') { $confValues['public_url'] = "http://localhost:$AppPort" }
    else { $confValues['public_url'] = $ownedPublic }
    $ownedAutoMigrate = Get-ConfText 'auto_migrate' $existingConf
    $confValues['auto_migrate'] = if ($ownedAutoMigrate) { $ownedAutoMigrate } else { 'on' }
    foreach ($k in $existingConf.Keys) {
        if (-not $confValues.Contains($k)) { $confValues[$k] = [string]$existingConf[$k] }
    }
    Write-DEASysConf -Path $paths.Conf -Values $confValues
    if (-not $Portable) {
        Set-DEASysRestrictedAcl -Path $paths.Conf -ReadSids @('S-1-5-19') -FullSids @()
    }
    Write-DEASysLog "configuration written: $($paths.Conf) (listen $listen)"

    if (-not (Test-Path $paths.Exe)) {
        Fail "the program $($paths.Exe) is missing; run the installer again"
    }

    # ---- migrate, then service
    Write-DEASysLog -Level STEP -Message 'applying the database schema (migrate)'
    try {
        $script:DbTouched = $true
        Invoke-Migrate -paths $paths -ConfPath $paths.Conf
    } catch {
        if ($isUpgrade) { Invoke-Rollback -paths $paths -Reason ('the migration failed: ' + $_.Exception.Message) -RestoreDb; exit 1 }
        throw
    }

    Stop-AppServer -paths $paths
    if (-not $Portable -and -not $NoService) {
        if ((Get-DEASysServiceState -Name $ServiceApp) -eq 'absent') {
            $env:DEASYS_CONFIG = $paths.Conf
            try { $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('service', 'install') } finally { Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue }
            if ($r.ExitCode -ne 0) { throw ('service install failed: ' + ($r.Output -join ' ')) }
            Write-DEASysLog 'service DEASys registered'
        }
    }
    try {
        Start-AppServer -paths $paths -ConfPath $paths.Conf
    } catch {
        Write-DEASysLog -Level ERROR -Message $_.Exception.Message
        if ($isUpgrade) { Invoke-Rollback -paths $paths -Reason 'the server did not start' -RestoreDb; exit 1 }
        Fail 'the server did not start after the install (see logs\server-console.err.log and the Windows event log)'
    }
    if (-not (Test-AppHealth -Port $AppPort)) {
        if ($isUpgrade) { Invoke-Rollback -paths $paths -Reason 'the health check failed' -RestoreDb; exit 1 }
        Fail "the health check http://127.0.0.1:$AppPort/health did not answer; the install is left in place for inspection"
    }
    Write-DEASysLog 'health check passed'

    # ---- network, shortcuts, browser
    if (-not $Portable) {
        if ($AllowNetwork) {
            Set-DEASysFirewallRule -Port $AppPort
            Write-DEASysLog "firewall rule added for TCP $AppPort (private and domain networks)"
        } else {
            Set-DEASysFirewallRule -Port $AppPort -Remove
        }
    }
    if (-not $NoShortcuts) {
        $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\DEASys'
        New-DEASysUrlShortcut -Path (Join-Path $startMenu 'DEASys.url') -Url "http://localhost:$AppPort/"
        if (-not $NoDesktopShortcut) {
            $desk = [Environment]::GetFolderPath('CommonDesktopDirectory')
            New-DEASysUrlShortcut -Path (Join-Path $desk 'DEASys.url') -Url "http://localhost:$AppPort/"
        }
        Write-DEASysLog 'shortcuts created'
    }
    if (-not $NoBrowser) { Start-Process "http://localhost:$AppPort/" }
    Write-DEASysLog -Level STEP -Message "DEASys $version is running at http://localhost:$AppPort/ . Open it to create the company and the administrator (first run)."
    exit 0
} catch {
    Write-DEASysLog -Level ERROR -Message ("install failed: " + $_.Exception.Message)
    # an upgrade that already changed the program files goes back to the previous version
    if ($script:IsUpgrade -and $script:ProgramChanged) {
        Invoke-Rollback -paths $paths -Reason 'the upgrade stopped before it finished' -RestoreDb:([bool]$script:DbTouched)
    }
    Write-DEASysLog -Level ERROR -Message ('The log is at ' + $script:DEASysLogFile + '. Run install.ps1 again after fixing the cause: it is safe to re-run.')
    exit 1
} finally {
    $script:DbUserSecret = $null
}
