param([string]$ProductionApiUrl = 'http://8.134.70.237')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$androidRoot = Join-Path $projectRoot 'mobile/android'
if (-not (Test-Path -LiteralPath (Join-Path $androidRoot 'key.properties')) -or
    -not (Test-Path -LiteralPath (Join-Path $androidRoot 'app/grandprix-upload.jks'))) {
    throw 'Release signing files are missing. Run scripts/init-release-signing.ps1 once.'
}
$url = $ProductionApiUrl.TrimEnd('/')
$origin = [uri]$url
$ipAddress = $null
if ($url -ne 'http://8.134.70.237' -and
    ($origin.Scheme -ne 'https' -or $origin.AbsolutePath -ne '/' -or
     $origin.Host -notmatch '\.' -or
     [Net.IPAddress]::TryParse($origin.Host, [ref]$ipAddress))) {
    throw 'ProductionApiUrl must be the approved ECS HTTP origin or an HTTPS domain origin.'
}
$nextRace = Invoke-RestMethod -Uri "$url/api/v1/next-race" -TimeoutSec 15
if (-not $nextRace.updated_at) { throw 'Production backend API check failed.' }

$env:ANDROID_HOME = Join-Path $projectRoot '.tools/android-sdk'
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.12.7-hotspot'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$androidUser = Join-Path $projectRoot '.tools/android-user'
New-Item -ItemType Directory -Force $androidUser,(Join-Path $androidUser '.android') | Out-Null
$env:ANDROID_USER_HOME = $androidUser
$env:GRADLE_OPTS = "-Duser.home=$androidUser"
if ($env:HTTPS_PROXY) {
    $proxy = [uri]$env:HTTPS_PROXY
    $env:GRADLE_OPTS += " -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port) -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port)"
}
$flutter = Join-Path $projectRoot '.tools/flutter/bin/flutter.bat'
$defines = @('--dart-define=API_ENV=production', "--dart-define=API_BASE_URL=$url")
Push-Location (Join-Path $projectRoot 'mobile')
try {
    & $flutter build apk --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'Release APK build failed.' }
    & $flutter build appbundle --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'Release AAB build failed.' }
    Get-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk',
        'build/app/outputs/bundle/release/app-release.aab' |
        Select-Object FullName, Length, LastWriteTime
} finally {
    Pop-Location
}
