$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$androidRoot = Join-Path $projectRoot 'mobile/android'
$keystorePath = Join-Path $androidRoot 'app/grandprix-upload.jks'
$propertiesPath = Join-Path $androidRoot 'key.properties'
if ((Test-Path -LiteralPath $keystorePath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Release signing files already exist; refusing to replace them.'
}

$keytool = 'C:\Program Files\Microsoft\jdk-17.0.12.7-hotspot\bin\keytool.exe'
if (-not (Test-Path -LiteralPath $keytool)) {
    $keytool = (Get-Command keytool.exe -ErrorAction Stop).Source
}

$env:GRANDPRIX_SIGNING_PASSWORD = [Convert]::ToHexString(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
try {
    & $keytool -genkeypair -noprompt -keystore $keystorePath -storetype PKCS12 `
        -alias upload -keyalg RSA -keysize 4096 -validity 10000 `
        -dname 'CN=GrandPrixReminder, OU=Release, O=GrandPrixReminder' `
        -storepass:env GRANDPRIX_SIGNING_PASSWORD `
        -keypass:env GRANDPRIX_SIGNING_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed.' }
    $properties = @(
        "storePassword=$env:GRANDPRIX_SIGNING_PASSWORD"
        "keyPassword=$env:GRANDPRIX_SIGNING_PASSWORD"
        'keyAlias=upload'
        'storeFile=grandprix-upload.jks'
    )
    [IO.File]::WriteAllLines($propertiesPath, $properties)
    Write-Output "Release keystore: $keystorePath"
    Write-Output "Ignored signing configuration: $propertiesPath"
    Write-Output 'Back up both files securely. Losing the key prevents signing future updates.'
} finally {
    Remove-Item Env:GRANDPRIX_SIGNING_PASSWORD -ErrorAction SilentlyContinue
}
