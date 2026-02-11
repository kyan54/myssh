# MySsh - Windows PowerShell SSH server quick connect tool
# Features: search (fzf if available), ssh/plink connect, WinSCP launch

Set-StrictMode -Version Latest

$utf8 = [System.Text.UTF8Encoding]::new()
$OutputEncoding = $utf8
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
try { chcp 65001 | Out-Null } catch { }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServersFile = if ($env:MYSSH_SERVERS_FILE) { $env:MYSSH_SERVERS_FILE } else { Join-Path $ScriptDir "servers.txt" }
$WinSCPExe = if ($env:MYSSH_WINSCP_PATH) { $env:MYSSH_WINSCP_PATH } else { "C:\\Users\\THINKBOOK\\AppData\\Local\\Programs\\WinSCP\\WinSCP.exe" }
$FzfExe = if ($env:MYSSH_FZF_PATH) { $env:MYSSH_FZF_PATH } else { $null }
$PlinkExe = if ($env:MYSSH_PLINK_PATH) { $env:MYSSH_PLINK_PATH } else { $null }

$LabelWidth = 20
$HostWidth = 17
$PortWidth = 7
$UserWidth = 17

$WideCharRegex = [regex]'[\u1100-\u115F\u2329\u232A\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE10-\uFE19\uFE30-\uFE6F\uFF01-\uFF60\uFFE0-\uFFE6\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]'

function Write-ErrorMsg([string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-WarnMsg([string]$Message) {
    Write-Host "[WARN ] $Message" -ForegroundColor Yellow
}

function Write-InfoMsg([string]$Message) {
    Write-Host "[INFO ] $Message" -ForegroundColor Cyan
}

function Pad([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = "" }
    $truncated = Truncate-DisplayWidth $Text $Width
    $currentWidth = Get-DisplayWidth $truncated
    if ($currentWidth -lt $Width) {
        return $truncated + (" " * ($Width - $currentWidth))
    }
    return $truncated
}

function Get-DisplayWidth([string]$Text) {
    if ($null -eq $Text) { return 0 }
    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ($WideCharRegex.IsMatch([string]$ch)) { $width += 2 } else { $width += 1 }
    }
    return $width
}

function Truncate-DisplayWidth([string]$Text, [int]$MaxWidth) {
    if ($null -eq $Text) { return "" }
    $width = 0
    $out = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $w = if ($WideCharRegex.IsMatch([string]$ch)) { 2 } else { 1 }
        if ($width + $w -gt $MaxWidth) { break }
        $null = $out.Append($ch)
        $width += $w
    }
    return $out.ToString()
}

function Resolve-FzfPath {
    if ($FzfExe -and (Test-Path -LiteralPath $FzfExe)) {
        return $FzfExe
    }

    $cmd = Get-Command fzf -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Path) { return $cmd.Path }
        if ($cmd.Source) { return $cmd.Source }
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE "scoop\\shims\\fzf.exe"),
        "C:\\ProgramData\\chocolatey\\bin\\fzf.exe",
        "C:\\Program Files\\fzf\\fzf.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    return $null
}

function Resolve-PlinkPath {
    if ($PlinkExe -and (Test-Path -LiteralPath $PlinkExe)) {
        return $PlinkExe
    }

    $cmd = Get-Command plink -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Path) { return $cmd.Path }
        if ($cmd.Source) { return $cmd.Source }
    }

    $candidates = @(
        "C:\\Program Files\\PuTTY\\plink.exe",
        "C:\\Program Files (x86)\\PuTTY\\plink.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    return $null
}

function Check-OptionalTools {
    $fzfPath = Resolve-FzfPath
    if (-not $fzfPath) {
        Write-WarnMsg "fzf not found. Search will be unavailable."
        Write-Host "Install: winget install --id=junegunn.fzf -e"
        Write-Host "Or:      scoop install fzf"
        Write-Host "Or:      choco install fzf -y"
    }

    $plinkPath = Resolve-PlinkPath
    if (-not $plinkPath) {
        Write-WarnMsg "plink (PuTTY) not found. Auto password login will be unavailable."
        Write-Host "Install: winget install --id=PuTTY.PuTTY -e"
        Write-Host "Or:      choco install putty.install -y"
    }
}

function Ensure-ServersFile {
    if (-not (Test-Path -LiteralPath $ServersFile)) {
        Write-ErrorMsg "Servers file not found: $ServersFile"
        Write-Host "Create it with tab or space separators (label host port user pass)."
        exit 1
    }
}

function Load-Servers {
    Ensure-ServersFile
    $servers = @()

    Get-Content -LiteralPath $ServersFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0) { return }
        if ($line -match "^\s*#") { return }

        $line = $line -replace "`t", " "
        $parts = $line -split "\s+", 5
        if ($parts.Count -lt 4) {
            Write-WarnMsg "Skip invalid line: $line"
            return
        }

        $label = $parts[0]
        $serverHost = $parts[1]
        $port = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { "22" }
        $user = $parts[3]
        $pass = if ($parts.Count -ge 5) { $parts[4] } else { "" }

        $servers += [pscustomobject]@{
            Label = $label
            Host  = $serverHost
            Port  = $port
            User  = $user
            Pass  = $pass
        }
    }

    return $servers
}

function Show-Help {
    Write-Host ""
    Write-Host "MySsh - Windows SSH server quick connect tool"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  myssh.ps1            Interactive select and SSH connect"
    Write-Host "  myssh.ps1 -w         Interactive select and open WinSCP"
    Write-Host "  myssh.ps1 -l         List servers"
    Write-Host "  myssh.ps1 -e         Edit servers file"
    Write-Host "  myssh.ps1 -h         Show help"
    Write-Host ""
    Write-Host "Environment:"
    Write-Host "  MYSSH_SERVERS_FILE   Servers file path (default: <script_dir>\\servers.txt)"
    Write-Host "  MYSSH_WINSCP_PATH    WinSCP executable path"
    Write-Host ""
}

function List-Servers([object[]]$Servers) {
    Write-Host ""
    Write-Host "Servers list ($ServersFile)"
    Write-Host "-------------------------------------------------------------"
    $header = "{0} | {1} | {2} | {3} | {4}" -f "#".PadRight(3), (Pad "Label" $LabelWidth), (Pad "Host" $HostWidth), (Pad "Port" $PortWidth), (Pad "User" $UserWidth)
    Write-Host $header
    Write-Host "---+" + ("-" * $LabelWidth) + "+" + ("-" * $HostWidth) + "+" + ("-" * $PortWidth) + "+" + ("-" * $UserWidth)

    for ($i = 0; $i -lt $Servers.Count; $i++) {
        $s = $Servers[$i]
        $line = "{0} | {1} | {2} | {3} | {4}" -f (($i + 1).ToString().PadRight(3)), (Pad $s.Label $LabelWidth), (Pad $s.Host $HostWidth), (Pad $s.Port $PortWidth), (Pad $s.User $UserWidth)
        Write-Host $line
    }

    Write-Host "-------------------------------------------------------------"
    Write-Host ""
}

function Select-ServerWithFzf([object[]]$Servers) {
    $fzfPath = Resolve-FzfPath
    if (-not $fzfPath) {
        Write-WarnMsg "fzf not found. Falling back to manual selection. Install fzf or set MYSSH_FZF_PATH."
        return $null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Servers.Count; $i++) {
        $s = $Servers[$i]
        $display = "{0} | {1} | {2} | {3}" -f (Pad $s.Label $LabelWidth), (Pad $s.Host $HostWidth), (Pad $s.Port $PortWidth), (Pad $s.User $UserWidth)
        $lines.Add("$display`t$($i + 1)")
    }

    $header = @(
        "MySsh - Server search (type to filter, Enter to select)",
        ("{0} | {1} | {2} | {3}" -f (Pad "Label" $LabelWidth), (Pad "Host" $HostWidth), (Pad "Port" $PortWidth), (Pad "User" $UserWidth)),
        ("{0}-+-{1}-+-{2}-+-{3}" -f ("-" * $LabelWidth), ("-" * $HostWidth), ("-" * $PortWidth), ("-" * $UserWidth))
    ) -join "`n"

    $selected = $lines | & $fzfPath --header="$header" --height=60% --layout=reverse --border=rounded --prompt=" search: " --delimiter="`t" --with-nth=1 --nth=1 --no-info
    if (-not $selected) { return $null }

    $idxText = ($selected -split "`t")[-1]
    $idx = 0
    if (-not [int]::TryParse($idxText, [ref]$idx)) { return $null }
    if ($idx -lt 1 -or $idx -gt $Servers.Count) { return $null }

    return $Servers[$idx - 1]
}

function Select-ServerManual([object[]]$Servers) {
    List-Servers $Servers
    $input = Read-Host "Select server number"
    $idx = 0
    if (-not [int]::TryParse($input, [ref]$idx)) { return $null }
    if ($idx -lt 1 -or $idx -gt $Servers.Count) { return $null }
    return $Servers[$idx - 1]
}

function Connect-Ssh([pscustomobject]$Server) {
    $serverHost = $Server.Host
    $port = if ($Server.Port) { $Server.Port } else { "22" }
    $user = $Server.User
    $pass = $Server.Pass

    Write-InfoMsg "Connecting to ${user}@${serverHost}:${port} ..."

    if ($pass) {
        $plinkPath = Resolve-PlinkPath
        if ($plinkPath) {
            & $plinkPath -ssh -P $port -l $user -pw $pass $serverHost
            return
        }
        Write-WarnMsg "Password provided but plink not found. Falling back to ssh (will prompt)."
        Write-WarnMsg "Install PuTTY/plink or set MYSSH_PLINK_PATH to enable auto login."
    }

    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) {
        Write-ErrorMsg "OpenSSH client not found. Install it or provide plink.exe."
        exit 1
    }

    & $ssh.Source -p $port "$user@$serverHost"
}

function Open-WinSCP([pscustomobject]$Server) {
    if (-not (Test-Path -LiteralPath $WinSCPExe)) {
        Write-ErrorMsg "WinSCP not found: $WinSCPExe"
        Write-Host "Set MYSSH_WINSCP_PATH to your WinSCP.exe path."
        exit 1
    }

    $serverHost = $Server.Host
    $port = if ($Server.Port) { $Server.Port } else { "22" }
    $user = $Server.User
    $pass = $Server.Pass

    if ($pass) {
        $encodedPass = [uri]::EscapeDataString($pass)
        $url = "sftp://${user}:${encodedPass}@${serverHost}:${port}/"
    } else {
        $url = "sftp://${user}@${serverHost}:${port}/"
    }

    Write-InfoMsg "Launching WinSCP for $serverHost ..."
    Start-Process -FilePath $WinSCPExe -ArgumentList $url | Out-Null
}

function Edit-ServersFile {
    if (-not (Test-Path -LiteralPath $ServersFile)) {
        $template = @(
            "# MySsh servers file",
            "# Format: label<TAB>host<TAB>port<TAB>user<TAB>password",
            "# Example:",
            "#prod-server`t192.168.1.100`t22`troot`tpassword123"
        )
        $dir = Split-Path -Parent $ServersFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
        $template | Set-Content -LiteralPath $ServersFile -Encoding UTF8
        Write-InfoMsg "Created template: $ServersFile"
    }

    $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad.exe" }
    Start-Process -FilePath $editor -ArgumentList $ServersFile | Out-Null
}

# -----------------------------
# Main
# -----------------------------
$mode = "ssh"
$action = "connect"

foreach ($arg in $args) {
    switch -Regex ($arg) {
        '^(-w|--winscp)$' { $mode = "winscp"; continue }
        '^(-l|--list)$'   { $action = "list"; continue }
        '^(-e|--edit)$'   { $action = "edit"; continue }
        '^(-h|--help)$'   { $action = "help"; continue }
        default {
            Write-ErrorMsg "Unknown argument: $arg"
            Show-Help
            exit 1
        }
    }
}

if ($action -eq "help") {
    Show-Help
    exit 0
}

if ($action -eq "edit") {
    Edit-ServersFile
    exit 0
}

$null = Check-OptionalTools

$servers = Load-Servers
if (-not $servers -or $servers.Count -eq 0) {
    Write-ErrorMsg "Servers list is empty."
    exit 1
}

if ($action -eq "list") {
    List-Servers $servers
    exit 0
}

$selected = Select-ServerWithFzf $servers
if (-not $selected) {
    $selected = Select-ServerManual $servers
}

if (-not $selected) {
    Write-InfoMsg "Canceled."
    exit 0
}

Write-Host "Selected: $($selected.Label) ($($selected.Host))"

if ($mode -eq "winscp") {
    Open-WinSCP $selected
} else {
    Connect-Ssh $selected
}
