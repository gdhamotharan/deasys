# Shared helpers for install.ps1 and uninstall.ps1 (DEASys, Windows). Dot-sourced; defines functions only.
# Shipped in the release zip next to the installer scripts. Windows PowerShell 5.1 compatible.
#
# Rules kept by every function here: no secret is ever written to the log or to the console; secrets are generated in
# memory and written only to files that are restricted to administrators (and the service account where it must read).

$script:DEASysLogFile = $null

function Initialize-DEASysLog {
    param([Parameter(Mandatory = $true)][string]$DataDir)
    $logDir = Join-Path $DataDir 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:DEASysLogFile = Join-Path $logDir 'install.log'
}

function Write-DEASysLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    $line = '{0} {1,-5} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:DEASysLogFile) {
        try { Add-Content -LiteralPath $script:DEASysLogFile -Value $line -Encoding UTF8 } catch { }
    }
    switch ($Level) {
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'STEP'  { Write-Host ('== ' + $Message) -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# A random string from letters and digits (no symbols, so it can sit in a URL without escaping).
function New-DEASysSecret {
    param([int]$Length = 32)
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $out = New-Object System.Text.StringBuilder
        $buf = New-Object byte[] 1
        while ($out.Length -lt $Length) {
            $rng.GetBytes($buf)
            # rejection sampling keeps the distribution uniform
            if ($buf[0] -lt (256 - (256 % $alphabet.Length))) {
                [void]$out.Append($alphabet[$buf[0] % $alphabet.Length])
            }
        }
        return $out.ToString()
    } finally { $rng.Dispose() }
}

# The HMAC key for sign-in tokens: 48 random bytes, base64 (64 characters).
function New-DEASysJwtKey {
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $bytes = New-Object byte[] 48
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally { $rng.Dispose() }
}

# Restricts a file or folder to SYSTEM, Administrators and the listed SIDs (read only for the service accounts).
# $ReadSids and $FullSids take SDDL SIDs such as S-1-5-19 (LOCAL SERVICE) or S-1-5-20 (NETWORK SERVICE).
function Set-DEASysRestrictedAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$ReadSids = @(),
        [string[]]$FullSids = @()
    )
    # (OI)(CI) (inherit to children) only on a folder: on a file it leaves an empty ACL that locks everyone out
    $inh = ''
    if (Test-Path -LiteralPath $Path -PathType Container) { $inh = '(OI)(CI)' }
    $args = @($Path, '/inheritance:r', '/grant:r', "*S-1-5-18:${inh}F", "*S-1-5-32-544:${inh}F")
    foreach ($sid in $ReadSids) { $args += @('/grant:r', "*${sid}:${inh}R") }
    foreach ($sid in $FullSids) { $args += @('/grant:r', "*${sid}:${inh}F") }
    & icacls.exe @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls could not restrict $Path" }
}

# Runs a program and returns its exit code and output lines. Arguments are quoted into one string (no shell).
# Output goes to temporary files, not pipes: a server started by pg_ctl inherits the handles, and a pipe would never close.
function Invoke-DEASysProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = $null,
        # for pg_ctl start/stop: the database process keeps the handles it inherits, so nothing is redirected and the output
        # goes to the server's own log (the caller gets the exit code only)
        [switch]$NoCapture
    )
    if ($NoCapture) {
        $quotedNc = (($ArgumentList | ForEach-Object { if ($_ -match '\s|"' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
        $ncParams = @{ FilePath = $FilePath; ArgumentList = $quotedNc; Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
        if ($WorkingDirectory) { $ncParams['WorkingDirectory'] = $WorkingDirectory }
        $ncProc = Start-Process @ncParams
        return @{ ExitCode = $ncProc.ExitCode; Output = @() }
    }
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $quoted = (($ArgumentList | ForEach-Object { if ($_ -match '\s|"' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
        $params = @{
            FilePath = $FilePath
            ArgumentList = $quoted
            Wait = $true
            PassThru = $true
            WindowStyle = 'Hidden'
            RedirectStandardOutput = $outFile
            RedirectStandardError = $errFile
        }
        if ($WorkingDirectory) { $params['WorkingDirectory'] = $WorkingDirectory }
        $proc = Start-Process @params
        $lines = @()
        foreach ($f in @($outFile, $errFile)) {
            $content = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue
            if ($content) { $lines += @($content | Where-Object { $_ -ne '' }) }
        }
        return @{ ExitCode = $proc.ExitCode; Output = $lines }
    } finally {
        foreach ($f in @($outFile, $errFile)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

# Waits until GET <url> answers 200 or the time runs out.
function Wait-DEASysHealth {
    param([Parameter(Mandatory = $true)][string]$Url, [int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 4
            if ([int]$r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# Reads deasys.conf (key = value, # comments, optional quotes) into a hashtable. Missing file gives an empty table.
function Read-DEASysConf {
    param([Parameter(Mandatory = $true)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        if ($val.Length -ge 2 -and (($val[0] -eq '"' -and $val[$val.Length - 1] -eq '"') -or ($val[0] -eq "'" -and $val[$val.Length - 1] -eq "'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $values[$key] = $val
    }
    return $values
}

# Writes deasys.conf. The file is written in full each time; callers keep existing secrets by reading the old file first.
function Write-DEASysConf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# DEASys server configuration. Written by install.ps1. Contains secrets: keep it restricted.')
    foreach ($k in $Values.Keys) {
        $lines.Add(('{0} = "{1}"' -f $k, $Values[$k]))
    }
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllLines($tmp, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-DEASysServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return 'absent' }
    return [string]$svc.Status
}

# Adds or replaces one inbound rule for the app port (private and domain networks only).
function Set-DEASysFirewallRule {
    param([Parameter(Mandatory = $true)][int]$Port, [switch]$Remove)
    $name = 'DEASys web interface (TCP)'
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    if (-not $Remove) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private,Domain | Out-Null
    }
}

# Creates a Windows Internet shortcut (.url) that opens the web interface.
function New-DEASysUrlShortcut {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Url)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $content = "[InternetShortcut]`r`nURL=$Url`r`n"
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.Encoding]::ASCII)
}

# Runs a program with text on its standard input (used to send SQL to psql so that no password is on a command line).
function Invoke-DEASysProcessWithInput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][string]$InputText
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = ($ArgumentList -join ' ')
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $proc.StandardInput.Write($InputText)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $lines = @()
    if ($stdout) { $lines += ($stdout -split "`r?`n" | Where-Object { $_ -ne '' }) }
    if ($stderr) { $lines += ($stderr -split "`r?`n" | Where-Object { $_ -ne '' }) }
    return @{ ExitCode = $proc.ExitCode; Output = $lines }
}

# Runs a program as another local account (used for initdb, which PostgreSQL refuses to run as Administrator).
# Output is written to $LogFile, which is created by this (administrator) process.
function Invoke-DEASysProcessAsUser {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $true)][string]$LogFile
    )
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Credential $Credential -WindowStyle Hidden `
        -RedirectStandardOutput $LogFile -RedirectStandardError ($LogFile + '.err') -Wait -PassThru
    return $proc.ExitCode
}
