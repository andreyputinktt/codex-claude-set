param(
  [string]$HostAlias = "ai-server"
)

$ErrorActionPreference = "Stop"

function Check {
  param(
    [string]$Name,
    [scriptblock]$Command
  )
  Write-Host "== $Name =="
  & $Command
  Write-Host ""
}

Check "Local Git" { git --version }
Check "Local SSH" { ssh -V }
Check "SSH connection" { ssh $HostAlias "echo SSH_OK && hostname && whoami" }
Check "Server GIT root" { ssh $HostAlias "mkdir -p ~/GIT && cd ~/GIT && pwd" }
Check "Server Codex version" { ssh $HostAlias "codex --version" }
Check "Server Codex login" { ssh $HostAlias "codex login status || true" }
Check "Server Codex daemon" { ssh $HostAlias "codex app-server daemon version || true" }
Check "Server GitHub SSH" { ssh $HostAlias "ssh -T git@github.com || true" }
