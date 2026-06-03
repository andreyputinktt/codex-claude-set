param(
  [string]$LocalRoot = "$HOME\GIT",
  [string]$ServerHost = "",
  [string]$ServerUser = "",
  [string]$HostAlias = "ai-server",
  [switch]$SkipPackageInstall
)

$ErrorActionPreference = "Stop"

function Ask-Value {
  param(
    [string]$Prompt,
    [string]$Default = ""
  )
  if ($Default) {
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
  }
  return Read-Host $Prompt
}

function Ask-YesNo {
  param(
    [string]$Prompt,
    [string]$Default = "yes"
  )
  $value = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
  return $value -match "^(y|yes|д|да)$"
}

function Sanitize-LinuxUser {
  param([string]$Raw)
  $base = ($Raw -replace "@.*$", "").ToLowerInvariant()
  $base = $base -replace "[^a-z0-9_-]+", "-"
  $base = $base.Trim("-")
  if ([string]::IsNullOrWhiteSpace($base)) { $base = "codexuser" }
  if ($base -notmatch "^[a-z_]") { $base = "u-$base" }
  if ($base.Length -gt 30) { $base = $base.Substring(0, 30) }
  return $base
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Write-IfMissing {
  param(
    [string]$Path,
    [string[]]$Lines
  )
  if (-not (Test-Path $Path)) {
    Ensure-Directory (Split-Path -Parent $Path)
    Set-Content -Path $Path -Value ($Lines -join "`n")
  }
}

function Set-EnvNote {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )
  Ensure-Directory (Split-Path -Parent $Path)
  $lines = @()
  if (Test-Path $Path) {
    $lines = Get-Content $Path | Where-Object { $_ -notmatch "^\s*$([regex]::Escape($Key))\s*=" }
  }
  $escaped = $Value.Replace("'", "''")
  $lines += "$Key='$escaped'"
  Set-Content -Path $Path -Value $lines
}

function Initialize-LlmWikiRoot {
  param([string]$Root)
  Ensure-Directory $Root
  foreach ($folder in @("assistants", "projects", "services", "sites", "contexts", "outputs", "archives", "docs")) {
    Ensure-Directory (Join-Path $Root $folder)
    Write-IfMissing (Join-Path $Root "$folder\README.md") @(
      "# $folder",
      "",
      "Index for $folder. Link to child repos or important files instead of duplicating details."
    )
  }
  Write-IfMissing (Join-Path $Root "README.md") @(
    "# Repository Index",
    "",
    "Root workspace for AI-assisted work. Start here, then read DEV.md, then the target repo README.",
    "",
    "<!-- ai-index:start -->",
    "## Workspace Index",
    "",
    "Managed by ai-index-refresh on the server or scripts/refresh-llm-wiki-index.sh from this kit.",
    "<!-- ai-index:end -->"
  )
  Write-IfMissing (Join-Path $Root "DEV.md") @(
    "# Development And Server Rules",
    "",
    "Use README files as indexes. Use OpenSpec for code, behavior, deploy, integration, prompt, and workflow changes. Keep secrets in ignored .env files."
  )
  Write-IfMissing (Join-Path $Root "AGENTS.md") @("# Agent guide", "@README.md", "", "Dev rules: [DEV.md](DEV.md).")
  Write-IfMissing (Join-Path $Root "CLAUDE.md") @("@README.md")
  Write-IfMissing (Join-Path $Root "llm-wiki.md") @(
    "# LLM Wiki",
    "",
    "Read root README, then DEV, then the target repo README. One fact lives in one place."
  )
  Write-IfMissing (Join-Path $Root ".gitignore") @(".env", ".env-*", "!.env.example", "node_modules/", ".venv/", "venv/", "__pycache__/", "*.log", "logs/", "tmp/", ".cache/")
}

Write-Host "Beginner Codex/Claude Windows onboarding"
Write-Host "Windows is configured as a station/client. Repos, services, secrets, and long-running work stay on the Ubuntu server."

$loginHint = Ask-Value "Your OpenAI/Claude or work email, used for default Linux login"
$defaultUser = Sanitize-LinuxUser $loginHint

$LocalRoot = Ask-Value "Starter folder on this computer" $LocalRoot
Initialize-LlmWikiRoot $LocalRoot
$localEnv = Join-Path $LocalRoot ".env-local"
Set-EnvNote $localEnv "LOCAL_GIT_ROOT" $LocalRoot
if ($loginHint) { Set-EnvNote $localEnv "LOGIN_HINT" $loginHint }

$wantGithub = Ask-YesNo "Do you want personal GitHub configured?" "yes"
if ($wantGithub) {
  $githubKey = "$HOME\.ssh\github_account_ed25519"
  Ensure-Directory "$HOME\.ssh"
  if (-not (Test-Path $githubKey)) {
    ssh-keygen -t ed25519 -N "" -C "github-account@$env:COMPUTERNAME" -f $githubKey
  }
  Write-Host "Add this public key at: https://github.com/settings/keys"
  Get-Content "$githubKey.pub"
}

Write-Host ""
Write-Host "Server choices:"
Write-Host "  kt       - KT employee server, default ai4u.kt.team."
Write-Host "  personal - your own Timeweb/other Ubuntu server."
Write-Host "  none     - local workspace only for now."
$serverKind = Ask-Value "Server type: kt, personal, or none" "kt"
if ($serverKind -ne "none") {
  if (-not $ServerHost) {
    $defaultHost = if ($serverKind -eq "kt") { "ai4u.kt.team" } else { "" }
    $ServerHost = Ask-Value "Server IP or hostname" $defaultHost
  }
  if (-not $ServerUser) {
    $ServerUser = Ask-Value "Linux username on the server" $defaultUser
  }
  Set-EnvNote $localEnv "AI_SERVER_HOST" $ServerHost
  Set-EnvNote $localEnv "AI_SERVER_USER" $ServerUser
  Set-EnvNote $localEnv "AI_SERVER_TARGET" "$ServerUser@$ServerHost"

  & "$PSScriptRoot\bootstrap.ps1" -ServerHost $ServerHost -ServerUser $ServerUser -HostAlias $HostAlias -SkipPackageInstall:$SkipPackageInstall

  Write-Host ""
  Write-Host "If SSH is not accepted yet, send the public key printed above to the server admin/provider."
  Write-Host "For KT-managed server, ask for sudo and SSH access for user $ServerUser on $ServerHost."
}

Write-Host ""
Write-Host "Provider API key pages:"
Write-Host "OpenAI:    https://platform.openai.com/api-keys"
Write-Host "Anthropic: https://console.anthropic.com/settings/keys"
Write-Host "Gemini:    https://aistudio.google.com/app/apikey"
Write-Host ""
Write-Host "Use windows\set-secret.ps1 after server SSH works, for example:"
Write-Host ".\windows\set-secret.ps1 -Name OPENAI_API_KEY -Provider openai -Server $HostAlias"
Write-Host ""
Write-Host "Local starter folder: $LocalRoot"
Write-Host "Local notes: $localEnv"
