param(
  [Parameter(Mandatory = $true)]
  [string]$ServerHost,

  [Parameter(Mandatory = $true)]
  [string]$ServerUser,

  [string]$HostAlias = "ai-server",
  [string]$KeyPath = "$HOME\.ssh\ai_server_ed25519",
  [switch]$SkipPackageInstall
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Command-Exists {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
  param(
    [string]$Id,
    [string]$Name
  )
  if ($SkipPackageInstall) {
    return
  }
  if (-not (Command-Exists winget)) {
    Write-Warning "winget not found; install $Name manually."
    return
  }
  try {
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
  } catch {
    Write-Warning "Could not install $Name through winget. It may already be installed, or winget may need manual confirmation."
  }
}

Ensure-Directory "$HOME\.ssh"

Install-WingetPackage -Id "Git.Git" -Name "Git for Windows"
Install-WingetPackage -Id "Microsoft.PowerShell" -Name "PowerShell 7"
Install-WingetPackage -Id "Microsoft.WindowsTerminal" -Name "Windows Terminal"
Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -Name "Node.js LTS"
Install-WingetPackage -Id "Anysphere.Cursor" -Name "Cursor"
Install-WingetPackage -Id "Microsoft.VisualStudioCode" -Name "Visual Studio Code"

if (Command-Exists npm) {
  try {
    npm install -g @openai/codex
  } catch {
    Write-Warning "Could not install Codex CLI through npm. Install Node.js LTS or rerun after opening a new PowerShell window."
  }
} else {
  Write-Warning "npm not found in this shell. Open a new PowerShell window after Node.js install and run: npm install -g @openai/codex"
}

if (-not (Command-Exists ssh)) {
  try {
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
  } catch {
    Write-Warning "Could not enable OpenSSH Client automatically. Install it in Windows Optional Features, then rerun this script."
  }
}

if (-not (Command-Exists ssh)) {
  throw "ssh.exe is still unavailable. Install OpenSSH Client and rerun."
}

if (-not (Test-Path $KeyPath)) {
  ssh-keygen -t ed25519 -N "" -C "windows-station@$env:COMPUTERNAME" -f $KeyPath
}

$sshConfig = "$HOME\.ssh\config"
$identityFile = $KeyPath.Replace("\", "/")
$hostBlock = @"

Host $HostAlias
  HostName $ServerHost
  User $ServerUser
  IdentityFile $identityFile
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 120
  TCPKeepAlive yes

"@

if (Test-Path $sshConfig) {
  $existing = Get-Content $sshConfig -Raw
  $pattern = "(?ms)^Host\s+$([regex]::Escape($HostAlias))\s+.*?(?=^Host\s+|\z)"
  if ($existing -match $pattern) {
    $updated = [regex]::Replace($existing, $pattern, $hostBlock.TrimStart())
    Set-Content -Path $sshConfig -Value $updated -NoNewline
  } else {
    Add-Content -Path $sshConfig -Value $hostBlock
  }
} else {
  Set-Content -Path $sshConfig -Value $hostBlock.TrimStart()
}

$binDir = "$HOME\bin"
Ensure-Directory $binDir

Set-Content -Path "$binDir\ai-shell.ps1" -Value @"
param([string]`$Workdir = "~/GIT")
ssh -t $HostAlias "cd `$Workdir && bash -l"
"@

Set-Content -Path "$binDir\codex-server.ps1" -Value @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Args)
`$joined = `$Args -join " "
ssh -t $HostAlias "cd ~/GIT && codex `$joined"
"@

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$binDir*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
}

Write-Host "Public key to add to the server if needed:"
Get-Content "$KeyPath.pub"
Write-Host ""
Write-Host "Verifying SSH..."
ssh $HostAlias "echo SSH_OK && hostname && whoami"
Write-Host ""
Write-Host "Windows station ready. Open a new PowerShell window, then use ai-shell or codex-server."
