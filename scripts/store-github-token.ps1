$ErrorActionPreference = 'Stop'
$tokenPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'repositorytoken.txt'
$raw = [IO.File]::ReadAllText($tokenPath).Trim()
$match = [regex]::Match($raw, '(github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+)')
if (-not $match.Success) { throw 'No recognized GitHub token found; source preserved.' }
$token = $match.Value
try {
    $account = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers @{Authorization="Bearer $token"; 'User-Agent'='GrandPrixReminder-setup'}
} catch { throw 'GitHub authentication failed; source preserved. No credential details logged.' }
$entry = "protocol=https`nhost=github.com`nusername=$($account.login)`npassword=$token`n`n"
$entry | git credential-manager store
if ($LASTEXITCODE -ne 0) { throw 'Credential storage failed; source preserved.' }
$stored = "protocol=https`nhost=github.com`nusername=$($account.login)`n`n" | git credential-manager get
if ($LASTEXITCODE -ne 0 -or -not ($stored -contains "password=$token")) { throw 'Credential verification failed; source preserved.' }
Remove-Item -LiteralPath $tokenPath
$token = $null
$raw = $null
$entry = $null
$stored = $null
Write-Output 'GitHub authentication verified; credential saved in Git Credential Manager; plaintext file deleted.'
