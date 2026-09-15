param(
    [ValidateSet('development', 'test')]
    [string]$ApiEnvironment = 'test',
    [string]$ApiBaseUrl = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:ANDROID_HOME = Join-Path $projectRoot '.tools/android-sdk'
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.12.7-hotspot'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$androidUser = Join-Path $projectRoot '.tools/android-user'
New-Item -ItemType Directory -Force $androidUser,(Join-Path $androidUser '.android') | Out-Null
$env:ANDROID_USER_HOME = $androidUser
$gradleOptions = "-Duser.home=$androidUser"
if ($env:HTTPS_PROXY) {
    $proxyAddress = [uri]$env:HTTPS_PROXY
    $gradleOptions += " -Dhttps.proxyHost=$($proxyAddress.Host) -Dhttps.proxyPort=$($proxyAddress.Port) -Dhttp.proxyHost=$($proxyAddress.Host) -Dhttp.proxyPort=$($proxyAddress.Port)"
}
$env:GRADLE_OPTS = $gradleOptions
Push-Location (Join-Path $projectRoot 'mobile')
try {
    $dartDefines = @("--dart-define=API_ENV=$ApiEnvironment")
    if ($ApiBaseUrl) { $dartDefines += "--dart-define=API_BASE_URL=$ApiBaseUrl" }
    & (Join-Path $projectRoot '.tools/flutter/bin/flutter.bat') build apk --debug @dartDefines
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
} finally { Pop-Location }
