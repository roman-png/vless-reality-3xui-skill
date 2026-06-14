# Bootstrap key-based SSH to a password-only host from Windows using OpenSSH SSH_ASKPASS.
# No plink/sshpass needed. The password is a parameter (never hardcoded) and the temporary
# askpass file is deleted immediately after use.
#
# Usage:
#   .\ssh-bootstrap-key.ps1 -HostTarget root@203.0.113.10 -Password 'the-host-password'
#   .\ssh-bootstrap-key.ps1 -HostTarget root@host -Password 'pw' -KeyName myvps
param(
  [Parameter(Mandatory = $true)][string]$HostTarget,
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$KeyName = "vps_key"
)

$ErrorActionPreference = 'Stop'
$sshDir = Join-Path $env:USERPROFILE ".ssh"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
$keyPath = Join-Path $sshDir $KeyName
if (-not (Test-Path $keyPath)) {
  & ssh-keygen -t ed25519 -f $keyPath -N '""' -C $KeyName -q
}
$pub = (Get-Content "$keyPath.pub" -Raw).Trim()

# Temporary askpass helper (echoes the password to stdout). ASCII, deleted in finally.
$ap = Join-Path $env:TEMP ("askpass_" + $KeyName + ".cmd")
[IO.File]::WriteAllText($ap, "@echo off`r`necho $Password`r`n", [Text.Encoding]::ASCII)
$env:SSH_ASKPASS = $ap
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY = 'localhost:0'
try {
  & ssh -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=20 `
    $HostTarget "umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; echo KEY_INSTALLED"
}
finally {
  Remove-Item $ap -Force -ErrorAction SilentlyContinue
}

# Verify passwordless key login.
& ssh -i $keyPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 $HostTarget "echo KEY_LOGIN_OK; id"
Write-Host ""
Write-Host "Key ready: $keyPath"
Write-Host "Use:  ssh -i `"$keyPath`" $HostTarget"
Write-Host "Optional hardening on the server: set 'PasswordAuthentication no' in sshd_config, then 'systemctl reload ssh'."
