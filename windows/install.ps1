# Installs, upgrades or repairs DEASys on Windows (64-bit). Run from the extracted release folder, or let the installer run it.
#
#   Fresh install (elevated PowerShell, bundled PostgreSQL 16 from the package):
#       .\install.ps1
#   Fresh install against an existing PostgreSQL server (prompts for the connection; the password is typed hidden):
#       .\install.ps1 -DbMode existing
#   Network access for other computers (opens a private-network firewall rule, listens on all addresses):
#       .\install.ps1 -AllowNetwork
#   Upgrade: run the same script from a newer package. The database is backed up first; on a failed health check the
#   previous program files and database are put back.
#   Test mode without administrator rights (no service, no firewall, no shortcuts; ports and folders are yours):
#       .\install.ps1 -Portable -InstallDir <folder> -DataDir <folder> -PgBin C:\PostgreSQL\13\bin -PgPort 5439 -AppPort 8089
#
# Terms and conditions: TERMS.txt next to this script is shown first. The operator types ACCEPT, or a script passes
# -AcceptTerms (the Inno Setup wizard does, after its I accept button). -Unattended needs -AcceptTerms. The acceptance is
# recorded in DataDir\terms-accepted.json. The terms are asked again only when the package's terms version is newer.
#
# Before anything is changed: pre-flight checks (administrator rights, free disk space, free ports, conflicting services,
# the PostgreSQL download address when it is needed), then a summary of what will be changed, then "Continue? (Y)".
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
$DbUser = 'DEASysDb'          # local account that runs the bundled PostgreSQL service (not an administrator)
$AppDb = 'deasys'             # application role and database
$exeName = 'deasys-server.exe'

# Unpacks only the parts of the PostgreSQL zip that DEASys needs (bin, lib, share). The official zip also holds pgAdmin, the documentation,
# the headers and debug symbols (over 1 GB in all), which the product does not use. Entries outside the destination are refused.
function Expand-PgSubset {
    param([string]$Zip, [string]$Dest, [string]$Top, [string[]]$Keep)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $destFull = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.EndsWith('/')) { continue }
            $wanted = $false
            foreach ($k in $Keep) { if ($name.StartsWith("$Top/$k/", [StringComparison]::OrdinalIgnoreCase)) { $wanted = $true; break } }
            if (-not $wanted) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Dest ($name.Replace('/', '\'))))
            if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "unsafe path in the zip: $name" }
            New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally { $archive.Dispose() }
}

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
    try {
        if ($DbMode -eq 'bundled' -or (Get-DEASysServiceState -Name $ServiceDb) -ne 'absent') { Start-BundledDb -paths $paths }
        $r = Invoke-DEASysProcess -FilePath $paths.Exe -ArgumentList @('backup', $backup)
    } finally { Remove-Item Env:\DEASYS_CONFIG -ErrorAction SilentlyContinue }
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
    foreach ($f in 'install.ps1', 'uninstall.ps1', 'deasys-common.ps1', 'LICENSE.txt', 'README-FIRST.txt', 'VERSION.txt', 'TERMS.txt', 'postgres-pin.psd1') {
        $src = Join-Path $pkg $f
        if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination $InstallDir -Force }
    }
    $pgSrc = Join-Path $pkg 'postgresql'
    if ((-not $Portable) -and (Test-Path $pgSrc) -and -not (Test-Path (Join-Path $InstallDir 'postgresql\bin\initdb.exe'))) {
        Write-DEASysLog 'copying the bundled PostgreSQL programs (a one-time copy; later upgrades keep them)'
        Copy-Item -LiteralPath $pgSrc -Destination $InstallDir -Recurse -Force
    }
}

function Resolve-PgBin {
    if ($PgBin) { return $PgBin }
    if (Test-Path (Join-Path $InstallDir 'postgresql\bin\initdb.exe')) { return (Join-Path $InstallDir 'postgresql\bin') }
    if (Test-Path (Join-Path $pkg 'postgresql\bin\initdb.exe')) { return (Join-Path $pkg 'postgresql\bin') }
    if ($env:DEASYS_PG_BIN -and (Test-Path (Join-Path $env:DEASYS_PG_BIN 'initdb.exe'))) { return $env:DEASYS_PG_BIN }
    return $null
}

# When the package has no postgresql folder (the small package), download the pinned PostgreSQL binaries from the official
# source named in postgres-pin.psd1, check their SHA-256, and unpack them into InstallDir\postgresql. Needs internet access once.
function Get-PgOnline {
    $pinFile = Join-Path $pkg 'postgres-pin.psd1'
    if (-not (Test-Path $pinFile)) { return $null }
    $pin = Import-PowerShellDataFile -Path $pinFile
    if ($pin.Sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $null }
    $dl = Join-Path $DataDir 'downloads'
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $zip = Join-Path $dl $pin.FileName
    $ok = $false
    if (Test-Path $zip) { $ok = ((Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash -eq $pin.Sha256.ToUpper()) }
    if (-not $ok) {
        Write-DEASysLog -Level STEP -Message "downloading PostgreSQL $($pin.Version) (about 330 MB, one time) from $($pin.Url)"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -Uri $pin.Url -OutFile $zip -UseBasicParsing } finally { $ProgressPreference = $old }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
        if ($actual -ne $pin.Sha256.ToUpper()) {
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            Fail "the downloaded PostgreSQL does not match the expected SHA-256 (expected $($pin.Sha256), got $actual). It was deleted and not used."
        }
        Write-DEASysLog 'PostgreSQL download verified (SHA-256)'
    }
    $target = Join-Path $InstallDir 'postgresql'
    $tmp = Join-Path $dl ('extract-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Write-DEASysLog -Level STEP -Message 'unpacking PostgreSQL'
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try {
            # the .NET unzip is many times faster than Expand-Archive on a package with thousands of files
            Expand-PgSubset -Zip $zip -Dest $tmp -Top $pin.TopFolder -Keep @('bin', 'lib', 'share')
        } finally { $ProgressPreference = $old }
        if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Move-FolderWithRetry -From (Join-Path $tmp $pin.TopFolder) -To $target
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path (Join-Path $target 'bin\initdb.exe'))) { Fail 'the downloaded PostgreSQL package has no bin\initdb.exe' }
    return (Join-Path $target 'bin')
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

# Bundled PostgreSQL: initdb (once), settings for loopback only, service registration, application role and database.
function Initialize-BundledDb {
    param($paths, [string]$AppPassword, [string]$SuperPassword)
    $pgBinDir = $script:PgBinDir
    $initdb = Join-Path $pgBinDir 'initdb.exe'
    $isNew = -not (Test-Path (Join-Path $paths.PgData 'PG_VERSION'))
    New-Item -ItemType Directory -Force -Path $paths.PgData | Out-Null
    New-Item -ItemType Directory -Force -Path $paths.Logs | Out-Null
    $runAs = $null
    if (-not $Portable -and -not $NoService) {
        # PostgreSQL refuses to run as Administrator: the service and initdb run as a dedicated local account
        $secure = ConvertTo-SecureString -String (New-DEASysSecret -Length 40) -AsPlainText -Force
        if (-not (Get-LocalUser -Name $DbUser -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $DbUser -Password $secure -PasswordNeverExpires -UserMayNotChangePassword `
                -Description 'Runs the DEASys bundled database service. Created by the DEASys installer.' | Out-Null
            Write-DEASysLog "local account $DbUser created (no sign-in rights are granted beyond the service)"
        }
        $script:DbUserSecret = $secure
        $runAs = $DbUser
    }
    if ($isNew) {
        Write-DEASysLog -Level STEP -Message 'creating the bundled database cluster (initdb)'
        New-Item -ItemType Directory -Force -Path $paths.Tmp | Out-Null
        $pwFile = Join-Path $paths.Tmp ('pw-' + [guid]::NewGuid().ToString('N') + '.txt')
        [System.IO.File]::WriteAllText($pwFile, $SuperPassword, (New-Object System.Text.UTF8Encoding($false)))
        try {
            if ($runAs) {
                Set-DEASysRestrictedAcl -Path $pwFile -ReadSids @() -FullSids @()
                & icacls.exe $pwFile /grant "${DbUser}:R" | Out-Null
                & icacls.exe $paths.PgData /grant "${DbUser}:(OI)(CI)F" | Out-Null
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $DbUser, $script:DbUserSecret
                $code = Invoke-DEASysProcessAsUser -FilePath $initdb -Credential $cred -LogFile (Join-Path $paths.Logs 'initdb.log') `
                    -ArgumentList @('-D', $paths.PgData, '-U', 'postgres', '--pwfile', $pwFile, '-E', 'UTF8', '--locale=C', '-A', 'scram-sha-256')
                $cred = $null
            } else {
                $r = Invoke-DEASysProcess -FilePath $initdb -ArgumentList @('-D', $paths.PgData, '-U', 'postgres', '--pwfile', $pwFile, '-E', 'UTF8', '--locale=C', '-A', 'scram-sha-256')
                $code = $r.ExitCode
                Set-Content -LiteralPath (Join-Path $paths.Logs 'initdb.log') -Value $r.Output -Encoding UTF8
            }
        } finally { Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue }
        if ($code -ne 0) { throw 'initdb failed (see logs\initdb.log)' }
        # listen on loopback only, on the chosen port (appended: the last setting wins)
        Add-Content -LiteralPath (Join-Path $paths.PgData 'postgresql.conf') -Value @(
            '',
            '# DEASys: loopback only, dedicated port',
            "listen_addresses = '127.0.0.1'",
            "port = $PgPort"
        ) -Encoding ASCII
    }
    if ($runAs) {
        & icacls.exe $paths.PgData /grant "${DbUser}:(OI)(CI)F" | Out-Null
    }
    if (-not $Portable -and -not $NoService) {
        if ((Get-DEASysServiceState -Name $ServiceDb) -eq 'absent') {
            Write-DEASysLog -Level STEP -Message "registering the database service $ServiceDb"
            $plain = $null
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:DbUserSecret)
            try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $r = Invoke-DEASysProcess -FilePath (Join-Path $pgBinDir 'pg_ctl.exe') -ArgumentList @('register', '-N', $ServiceDb, '-D', $paths.PgData, '-S', 'auto', '-U', ".\$DbUser", '-P', $plain, '-w')
            $plain = $null
            if ($r.ExitCode -ne 0) { throw 'pg_ctl could not register the database service' }
        }
        Start-BundledDb -paths $paths
    } else {
        Start-BundledDb -paths $paths
    }

    # application role and database (idempotent; the SQL is sent on standard input, never on the command line)
    $sql = @"
do `$`$ begin
  if not exists (select 1 from pg_roles where rolname = '$AppDb') then
    create role $AppDb login password '$AppPassword';
  else
    alter role $AppDb with login password '$AppPassword';
  end if;
end `$`$;
select 'create database $AppDb owner $AppDb encoding ''UTF8'' template template0'
  where not exists (select 1 from pg_database where datname = '$AppDb') \gexec
"@
    $env:PGPASSWORD = $SuperPassword
    try {
        $r = Invoke-DEASysProcessWithInput -FilePath (Join-Path $pgBinDir 'psql.exe') -InputText $sql `
            -ArgumentList @('-X', '-q', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', "$PgPort", '-U', 'postgres', '-d', 'postgres')
    } finally { Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue }
    if ($r.ExitCode -ne 0) { throw 'could not create the application role and database' }
    Write-DEASysLog "application role $AppDb and database $AppDb are in place"
}

function Get-ConfText {
    param([string]$Key, [hashtable]$Conf)
    if ($Conf.ContainsKey($Key)) { return [string]$Conf[$Key] }
    return ''
}

# Database connection for a bundled install (loopback only).
function New-BundledUrl {
    param([string]$Password)
    return "postgres://${AppDb}:$Password@127.0.0.1:${PgPort}/${AppDb}?sslmode=disable"
}

function Read-ExistingDbConnection {
    if ($Unattended -or $env:DEASYS_DB_PASSWORD) {
        $h = $env:DEASYS_DB_HOST; if (-not $h) { $h = 'localhost' }
        $p = $env:DEASYS_DB_PORT; if (-not $p) { $p = '5432' }
        $d = $env:DEASYS_DB_NAME; if (-not $d) { $d = 'deasys' }
        $u = $env:DEASYS_DB_USER; if (-not $u) { $u = 'deasys' }
        $s = $env:DEASYS_DB_SSLMODE; if (-not $s) { $s = 'prefer' }
        $pw = $env:DEASYS_DB_PASSWORD
        if (-not $pw) { throw 'DEASYS_DB_PASSWORD must be set for an unattended existing-server install' }
    } else {
        Write-Host 'Connection to the existing PostgreSQL server (the database must exist; DEASys creates its tables).'
        $h = Read-Host 'Host (default localhost)'; if (-not $h) { $h = 'localhost' }
        $p = Read-Host 'Port (default 5432)'; if (-not $p) { $p = '5432' }
        $d = Read-Host 'Database name'
        $u = Read-Host 'User name'
        $sec = Read-Host 'Password (hidden)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $s = Read-Host 'SSL mode: prefer, require or disable (default prefer)'; if (-not $s) { $s = 'prefer' }
    }
    if (-not $d -or -not $u) { throw 'database name and user name are required' }
    if ($s -notin @('disable', 'allow', 'prefer', 'require', 'verify-ca', 'verify-full')) { throw 'the SSL mode is not one of the allowed values' }
    $url = 'postgres://' + [Uri]::EscapeDataString($u) + ':' + [Uri]::EscapeDataString($pw) + '@' + $h + ':' + $p + '/' + $d + '?sslmode=' + $s
    Write-DEASysLog "existing database: $h`:$p/$d as $u (sslmode $s); the password is not logged"
    return $url
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
# newer than the recorded one (an unparseable version counts as newer). Equal or older package versions do not ask again.
function Test-TermsNeedAccept {
    param([string]$PackageVersion, $Record)
    if ($null -eq $Record -or -not $Record.version) { return $true }
    $recorded = [string]$Record.version
    if ($recorded -eq $PackageVersion) { return $false }
    $pd = Get-TermsDate -Version $PackageVersion
    $rd = Get-TermsDate -Version $recorded
    if ($null -eq $pd -or $null -eq $rd) { return $true }
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
    $answer = [string](Read-Host 'Type ACCEPT to accept')
    return ($answer.Trim() -ieq 'ACCEPT')
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

# Whether the PostgreSQL download address answers a HEAD request (10 seconds, TLS 1.2).
function Test-PgDownloadReachable {
    param([Parameter(Mandatory = $true)]$Pin)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-WebRequest -Uri $Pin.Url -Method Head -UseBasicParsing -TimeoutSec 10
        return ([int]$r.StatusCode -ge 200 -and [int]$r.StatusCode -lt 400)
    } catch {
        $script:PgHeadError = $_.Exception.Message
        return $false
    }
}

# The PostgreSQL download: the pinned zip goes to DataDir\downloads (once), its SHA-256 is checked, and it is extracted to
# InstallDir\postgresql. Runs in the change phase, after the summary was accepted. Does nothing when the programs are there.
function Install-BundledPostgresFiles {
    if ($DbMode -ne 'bundled') { return }
    if (Resolve-PgBin) { return }
    $pin = $script:Pin
    if (-not $pin) { throw 'postgres-pin.psd1 is missing from the package; the PostgreSQL programs cannot be fetched' }
    $sha = [string]$pin.Sha256
    if ($sha -notmatch '^[0-9a-fA-F]{64}$') { throw 'postgres-pin.psd1 has no valid SHA-256 (a placeholder); the PostgreSQL download is refused' }
    $dlDir = Join-Path $DataDir 'downloads'
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
    $zip = Join-Path $dlDir $pin.FileName
    if (Test-Path -LiteralPath $zip) {
        Write-DEASysLog "PostgreSQL zip already in $dlDir; it is not downloaded again"
    } else {
        Write-DEASysLog -Level STEP -Message "downloading PostgreSQL $($pin.Version) from the pinned address (one time)"
        $part = $zip + '.part'
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $pin.Url -OutFile $part -UseBasicParsing -TimeoutSec 1800
        } catch {
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            throw ('the PostgreSQL download failed: ' + $_.Exception.Message)
        } finally { $ProgressPreference = $oldProgress }
        Move-Item -LiteralPath $part -Destination $zip -Force
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
    if ($actual -ne $sha) {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $($pin.FileName): expected $sha, got $actual. The file was deleted; nothing was installed."
    }
    Write-DEASysLog 'PostgreSQL zip: SHA-256 verified'
    $tmp = Join-Path $DataDir ('tmp\pgx-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        # the .NET unzip is many times faster than Expand-Archive on a package with thousands of files
        Expand-PgSubset -Zip $zip -Dest $tmp -Top $pin.TopFolder -Keep @('bin', 'lib', 'share')
        $src = Join-Path $tmp $pin.TopFolder
        if (-not (Test-Path (Join-Path $src 'bin\initdb.exe'))) { throw "the zip has no $($pin.TopFolder)\bin\initdb.exe: wrong package" }
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        $target = Join-Path $InstallDir 'postgresql'
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Move-FolderWithRetry -From $src -To $target
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    if (-not (Test-Path (Join-Path $InstallDir 'postgresql\bin\initdb.exe'))) { throw 'the PostgreSQL programs did not reach InstallDir\postgresql' }
    Write-DEASysLog "PostgreSQL programs installed in $(Join-Path $InstallDir 'postgresql')"
}

# ---------------------------------------------------------------- pre-flight and summary
# Runs every check that does not change anything. Each result is logged; any failure stops the install before a change.
function Invoke-Preflight {
    param([hashtable]$Paths, [bool]$PgNeedsFiles, [bool]$PgZipPresent)
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
    if ($DbMode -eq 'bundled') {
        $p2 = Test-PortForPreflight -Port $PgPort -Label 'database' -Kind 'db' -Paths $Paths
        if ($p2) { $problems.Add($p2) }
    }

    # conflicting service names: ours on an upgrade is fine, anything else stops the install
    foreach ($svc in @($ServiceApp, $ServiceDb)) {
        $st = Get-DEASysServiceState -Name $svc
        if ($st -eq 'absent') { continue }
        if ($script:IsUpgrade) { Write-DEASysLog "service $svc exists ($st): part of this installation (upgrade)"; continue }
        $problems.Add("a Windows service named $svc already exists ($st), and $InstallDir has no DEASys installation to upgrade. Remove that service or choose other folders.")
    }

    # PostgreSQL programs: a valid pin is needed to fetch or verify them; the download address is checked only when no zip is in place
    if ($PgNeedsFiles) {
        $pin = $script:Pin
        $sha = ''
        if ($pin) { $sha = [string]$pin.Sha256 }
        if (-not $pin) { $problems.Add('postgres-pin.psd1 is missing from the package, so the PostgreSQL programs cannot be fetched or verified') }
        elseif ($sha -notmatch '^[0-9a-fA-F]{64}$') { $problems.Add('postgres-pin.psd1 has a placeholder SHA-256 (this is not a release build), so the PostgreSQL programs cannot be verified. Use a release package, -PgBin, or -DbMode existing.') }
        if ($PgZipPresent) {
            Write-DEASysLog "the PostgreSQL zip is already in $(Join-Path $DataDir 'downloads'): the download address is not checked and the download is skipped"
        } elseif ($pin -and $sha -match '^[0-9a-fA-F]{64}$') {
            if (Test-PgDownloadReachable -Pin $pin) { Write-DEASysLog "the PostgreSQL download address answers: $($pin.Url)" }
            else {
                $problems.Add("the PostgreSQL download address cannot be reached ($($script:PgHeadError)). Do one of these: (1) put $($pin.FileName) in $(Join-Path $DataDir 'downloads') (download it on a computer that has internet access); (2) pass -PgBin <folder with bin\initdb.exe> or set DEASYS_PG_BIN; (3) use an existing PostgreSQL server with -DbMode existing.")
            }
        }
    } elseif ($DbMode -eq 'bundled') {
        Write-DEASysLog "PostgreSQL programs: found ($(Resolve-PgBin)); no download needed"
    }

    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-DEASysLog -Level ERROR -Message ('pre-flight: ' + $p) }
        Fail 'the pre-flight checks failed. Nothing was changed.'
    }
    Write-DEASysLog 'pre-flight checks passed'
}

# Plain-English list of what the install will change. Printed and logged; the operator confirms it unless -Unattended.
function Show-ChangeSummary {
    param([hashtable]$Paths, [bool]$PgNeedsFiles, [bool]$PgZipPresent, [bool]$TermsWillBeRecorded)
    Write-DEASysLog -Level STEP -Message 'what will be changed'
    Write-DEASysLog "  Program folder: $InstallDir - the web server program, the web interface (ui), the scripts, TERMS.txt, the licence and the readme."
    if ($script:IsUpgrade) { Write-DEASysLog "    upgrade: the database is backed up first; the previous program files are kept in $($Paths.Previous)" }
    if ($DbMode -eq 'bundled') {
        if ($PgNeedsFiles) {
            if ($PgZipPresent) { Write-DEASysLog "    PostgreSQL programs: from the zip in $(Join-Path $DataDir 'downloads') (SHA-256 checked), into $(Join-Path $InstallDir 'postgresql')" }
            else { Write-DEASysLog "    PostgreSQL programs: ONE-TIME DOWNLOAD from $($script:Pin.Url) into $(Join-Path $DataDir 'downloads') (SHA-256 checked), then into $(Join-Path $InstallDir 'postgresql')" }
        } else { Write-DEASysLog "    PostgreSQL programs: already there ($(Resolve-PgBin)); not downloaded" }
    }
    Write-DEASysLog "  Data folder: $DataDir - kept on upgrades and never deleted by the install:"
    Write-DEASysLog '    deasys.conf (settings and secrets), logs, backups, run, tmp, downloads, terms-accepted.json'
    if ($DbMode -eq 'bundled') { Write-DEASysLog '    pgdata (the database) and pgsuper.secret (the database superuser password, administrators only)' }
    if ($TermsWillBeRecorded) { Write-DEASysLog "  Terms record: $(Join-Path $DataDir 'terms-accepted.json') is written (version and time of your acceptance)" }
    if ($Portable) {
        Write-DEASysLog '  Test mode (-Portable): no Windows services, no firewall rule, no shortcuts, no local account.'
    } else {
        Write-DEASysLog "  Service 'DEASys': the web server; runs as LocalService; starts automatically with Windows."
        if ($DbMode -eq 'bundled') {
            Write-DEASysLog "  Service 'DEASysDB': the bundled database; starts automatically; runs as the local account $DbUser (not an administrator)."
            Write-DEASysLog "  Local account ${DbUser}: created if it does not exist (used only to run the database service)."
        }
        if ($AllowNetwork) { Write-DEASysLog "  Firewall rule 'DEASys web interface (TCP)': allows TCP $AppPort on private and domain networks." }
        else { Write-DEASysLog "  Firewall: no rule is added (an existing rule of that name is removed); only this computer can open DEASys." }
        if ($NoShortcuts) { Write-DEASysLog '  Shortcuts: none (-NoShortcuts).' }
        else {
            Write-DEASysLog "  Start Menu shortcut 'DEASys' (folder DEASys)$(if ($NoDesktopShortcut) { '' } else { ' and a desktop shortcut' }): open http://localhost:$AppPort/"
        }
    }
    Write-DEASysLog "  Web address: http://localhost:$AppPort/ $(if ($AllowNetwork -and -not $Portable) { '(all network addresses)' } else { '(this computer only)' })"
    if ($DbMode -eq 'bundled') { Write-DEASysLog "  Database address: 127.0.0.1:$PgPort (this computer only)" }
    else { Write-DEASysLog '  Database: the existing PostgreSQL server you name (its connection is asked for during the install).' }
}

# ---------------------------------------------------------------- main
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
$script:Pin = $null
$script:PgHeadError = ''
$pinPath = Join-Path $pkg 'postgres-pin.psd1'
if (Test-Path -LiteralPath $pinPath) { $script:Pin = Import-PowerShellDataFile -Path $pinPath }
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
    if (-not $DbMode) {
        if (Test-Path $paths.Conf) {
            $existingConf = Read-DEASysConf -Path $paths.Conf
            if ((Get-ConfText 'database_url' $existingConf) -match '127\.0\.0\.1:' -or (Test-Path $paths.PgData)) { $DbMode = 'bundled' } else { $DbMode = 'existing' }
        } elseif ($Unattended) { $DbMode = 'bundled' }
        else {
            $answer = Read-Host 'Database: [B] bundled PostgreSQL (recommended) or [E] existing server? (B/E, default B)'
            if ($answer -match '^[Ee]') { $DbMode = 'existing' } else { $DbMode = 'bundled' }
        }
    }
    if ($DbMode -eq 'bundled' -and -not $Unattended -and -not $Portable -and -not $PSBoundParameters.ContainsKey('AllowNetwork')) {
        # the network question is asked only in an interactive fresh install
        if (-not $isUpgrade) {
            $net = Read-Host 'Allow other computers on your network to open DEASys? (y/N)'
            if ($net -match '^[Yy]') { $AllowNetwork = $true }
        }
    }
    Write-DEASysLog "database mode: $DbMode; web address: http://localhost:$AppPort/ ; network: $([bool]$AllowNetwork)"

    # the PostgreSQL programs: needed for the bundled database unless they are already there or a zip is in DataDir\downloads
    $pgNeedsFiles = ($DbMode -eq 'bundled') -and -not (Resolve-PgBin)
    $pgZipPresent = $false
    if ($pgNeedsFiles -and $script:Pin) {
        $pgZipPresent = Test-Path -LiteralPath (Join-Path (Join-Path $DataDir 'downloads') $script:Pin.FileName)
    }

    # ---- pre-flight (nothing is changed yet), then the summary and the confirmation
    Invoke-Preflight -Paths $paths -PgNeedsFiles $pgNeedsFiles -PgZipPresent $pgZipPresent
    Show-ChangeSummary -Paths $paths -PgNeedsFiles $pgNeedsFiles -PgZipPresent $pgZipPresent -TermsWillBeRecorded $termsNeedAccept
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
    if ($Phase -eq 'All' -or $Phase -eq 'Prepare' -or $Phase -eq 'Install') { Install-BundledPostgresFiles }

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
        $script:PgBinDir = Resolve-PgBin
        if (-not $script:PgBinDir) { $script:PgBinDir = Get-PgOnline }
        if (-not $script:PgBinDir) {
            Fail 'no PostgreSQL programs found. The package has no postgresql folder and the download is not available: pass -PgBin <folder with initdb.exe>, set DEASYS_PG_BIN, or use -DbMode existing.'
        }
        $appPw = ''
        $existingUrl = Get-ConfText 'database_url' $existingConf
        if ($existingUrl -match '^postgres://[^:]+:([^@]+)@127\.0\.0\.1:') { $appPw = $Matches[1] }
        if (-not $appPw) { $appPw = New-DEASysSecret -Length 32 }
        $superFile = Join-Path $DataDir 'pgsuper.secret'
        $superPw = $null
        if (Test-Path $superFile) { $superPw = (Get-Content -LiteralPath $superFile -Raw).Trim() }
        if (-not $superPw) { $superPw = New-DEASysSecret -Length 32 }
        if (-not (Test-Path (Join-Path $paths.PgData 'PG_VERSION'))) {
            # the superuser password is kept only in a file that administrators (and the database account) can read
            Set-Content -LiteralPath $superFile -Value $superPw -Encoding ASCII -NoNewline
            # service mode: administrators only; test mode: the current user (the test folder is already private to it)
            $fullSids = @()
            if ($Portable) { $fullSids = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) }
            Set-DEASysRestrictedAcl -Path $superFile -ReadSids @() -FullSids $fullSids
        }
        Initialize-BundledDb -paths $paths -AppPassword $appPw -SuperPassword $superPw
        $dbUrl = New-BundledUrl -Password $appPw
        $confValues['database_url'] = $dbUrl
        $confValues['pg_bin'] = $script:PgBinDir
    } else {
        $confValues['database_url'] = Read-ExistingDbConnection
        if ($PgBin) { $confValues['pg_bin'] = $PgBin }
    }

    $listen = if ($AllowNetwork -and -not $Portable) { "0.0.0.0:$AppPort" } else { "127.0.0.1:$AppPort" }
    $confValues['listen_addr'] = $listen
    $confValues['jwt_key'] = $jwt
    $confValues['log_dir'] = $paths.Logs
    $confValues['ui_dir'] = $paths.Ui
    $confValues['auto_migrate'] = 'on'
    $confValues['public_url'] = "http://localhost:$AppPort"
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
