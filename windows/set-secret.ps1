param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Z_][A-Z0-9_]*$')]
  [string[]]$Name,

  [string]$Provider,
  [string]$Project,
  [string]$Server,
  [string]$GitRoot,
  [string]$RemoteGitRoot = "GIT",
  [string]$VerifyCommand,
  [switch]$NoUpload
)

$ErrorActionPreference = "Stop"

function Find-DefaultGitRoot {
  $repoDir = Split-Path -Parent $PSScriptRoot
  $parent = Split-Path -Parent $repoDir

  if ((Split-Path -Leaf $repoDir) -eq "codex-claude-set" -and (Test-Path (Join-Path $parent "DEV.md"))) {
    return $parent
  }

  if ((Test-Path (Join-Path (Get-Location) "DEV.md")) -and (Test-Path (Join-Path (Get-Location) "README.md"))) {
    return (Get-Location).Path
  }

  return $repoDir
}

function Infer-Provider {
  param([string]$EnvName)
  switch -Regex ($EnvName) {
    '^OPENAI_' { return "openai" }
    '^ANTHROPIC_' { return "anthropic" }
    '^GEMINI_' { return "gemini" }
    '^(GOOGLE_|GMAIL_)' { return "google" }
    '^(GITHUB_|GH_)' { return "github" }
    '^(GITLAB_|GLAB_)' { return "gitlab" }
    '^TELEGRAM_' { return "telegram" }
    default { throw "Cannot infer provider for $EnvName; pass -Provider." }
  }
}

function ConvertFrom-SecureStringPlainText {
  param([System.Security.SecureString]$Secure)
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Format-DotEnvValue {
  param([string]$Value)
  if ($Value -match "[`r`n]") {
    throw "Secret value must be one line."
  }
  if ($Value -match '^[A-Za-z0-9_./:@+=,-]+$') {
    return $Value
  }
  return "'" + $Value.Replace("'", "'\''") + "'"
}

function Write-EnvValue {
  param(
    [string]$Path,
    [string]$EnvName,
    [string]$EncodedValue
  )

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $escapedName = [regex]::Escape($EnvName)
  $lines = @()
  if (Test-Path $Path) {
    $lines = Get-Content -Path $Path | Where-Object { $_ -notmatch "^\s*(export\s+)?$escapedName\s*=" }
  }

  $newLines = @($lines) + "$EnvName=$EncodedValue"
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($Path, [string[]]$newLines, $utf8NoBom)
}

function Quote-Bash {
  param([string]$Value)
  return "'" + $Value.Replace("'", "'\''") + "'"
}

function Upload-EnvFile {
  param(
    [string]$ServerHost,
    [string]$LocalFile,
    [string]$RemoteRoot,
    [string]$RemoteRel
  )

  $tmpName = ".codex-claude-set-env.$PID"
  Write-Host "==> Uploading $(Split-Path -Leaf $LocalFile) to ${ServerHost}:$RemoteRoot/$RemoteRel"
  scp -q $LocalFile "${ServerHost}:$tmpName"

  $quotedRoot = Quote-Bash $RemoteRoot
  $quotedRel = Quote-Bash $RemoteRel
  $quotedTmp = Quote-Bash $tmpName
  $remoteCommand = @"
set -euo pipefail
git_root=$quotedRoot
remote_rel=$quotedRel
tmp_name=$quotedTmp
case "`$git_root" in
  /*) base="`$git_root" ;;
  *) base="`$HOME/`$git_root" ;;
esac
target="`$base/`$remote_rel"
mkdir -p "`$(dirname "`$target")"
mv "`$HOME/`$tmp_name" "`$target"
chmod 600 "`$target"
echo "saved `$target"
"@
  ssh $ServerHost $remoteCommand
}

function Import-DotEnvFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Env file not found: $Path"
  }

  foreach ($line in Get-Content -Path $Path) {
    if ($line -match '^\s*$' -or $line -match '^\s*#') {
      continue
    }
    if ($line -notmatch '^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$') {
      continue
    }

    $key = $Matches[1]
    $value = $Matches[2].Trim()
    if ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
      $value = $value.Substring(1, $value.Length - 2).Replace("'\\''", "'")
    } elseif ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    [Environment]::SetEnvironmentVariable($key, $value, "Process")
  }
}

function Invoke-VerifyCommand {
  param(
    [string]$Command,
    [System.Collections.Specialized.OrderedDictionary]$ChangedFiles
  )

  if (-not $Command) {
    return
  }

  Write-Host "==> Running verification command"
  foreach ($entry in $ChangedFiles.GetEnumerator()) {
    Import-DotEnvFile -Path $entry.Key
  }
  $global:LASTEXITCODE = 0
  Invoke-Expression $Command
  if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    throw "Verification command failed with exit code $LASTEXITCODE."
  }
  Write-Host "==> Verification passed"
}

function Get-TargetForName {
  param([string]$EnvName)

  if ($Project) {
    $targetFile = Join-Path (Join-Path $GitRoot $Project) ".env"
    $remoteRel = ($Project.TrimEnd([char[]]@('\', '/')) + "/.env").Replace("\", "/")
    return @{
      Path = $targetFile
      RemoteRel = $remoteRel
    }
  }

  if ($Provider) {
    $targetProvider = $Provider
  } else {
    $targetProvider = Infer-Provider $EnvName
  }
  if ($targetProvider -notmatch '^[a-z0-9_-]+$') {
    throw "-Provider must be lowercase safe text."
  }

  return @{
    Path = (Join-Path $GitRoot ".env-$targetProvider")
    RemoteRel = ".env-$targetProvider"
  }
}

if ($Project -and [System.IO.Path]::IsPathRooted($Project)) {
  throw "-Project must be relative to GIT root."
}
if ($Project -and $Project.Contains("..")) {
  throw "-Project must not contain .."
}

if (-not $GitRoot) {
  $GitRoot = Find-DefaultGitRoot
}

$changedFiles = [ordered]@{}

foreach ($envName in $Name) {
  $target = Get-TargetForName $envName
  $targetFile = $target.Path
  $remoteRel = $target.RemoteRel

  if (Test-Path $targetFile) {
    Write-Host "==> Updating $targetFile"
  } else {
    Write-Host "==> Creating $targetFile"
  }

  $secureValue = Read-Host "Enter value for $envName (input hidden)" -AsSecureString
  $plainValue = ConvertFrom-SecureStringPlainText $secureValue
  if (-not $plainValue) {
    throw "Empty value for $envName; nothing written."
  }

  $encodedValue = Format-DotEnvValue $plainValue
  $plainValue = $null

  Write-EnvValue -Path $targetFile -EnvName $envName -EncodedValue $encodedValue
  $encodedValue = $null
  $changedFiles[$targetFile] = $remoteRel
}

Write-Host "==> Saved locally"
Invoke-VerifyCommand -Command $VerifyCommand -ChangedFiles $changedFiles

if (-not $NoUpload -and $Server) {
  foreach ($entry in $changedFiles.GetEnumerator()) {
    Upload-EnvFile -ServerHost $Server -LocalFile $entry.Key -RemoteRoot $RemoteGitRoot -RemoteRel $entry.Value
  }
} elseif (-not $NoUpload) {
  Write-Host "==> No -Server given; local file was not uploaded"
}
