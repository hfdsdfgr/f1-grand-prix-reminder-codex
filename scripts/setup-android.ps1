$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sdkRoot = Join-Path $projectRoot '.tools/android-sdk'
$archive = Join-Path $projectRoot '.tools/android-command-line.zip'
$unpack = Join-Path $projectRoot '.tools/android-command-line'
$manager = Join-Path $sdkRoot 'cmdline-tools/latest/bin/sdkmanager.bat'
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.12.7-hotspot'
if (-not (Test-Path -LiteralPath $manager)) {
    & curl.exe -fL --retry 2 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' -o $archive
    if ($LASTEXITCODE -ne 0) { throw 'Android command-line tools download failed.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $unpack -Force
    New-Item -ItemType Directory -Path (Join-Path $sdkRoot 'cmdline-tools') -Force | Out-Null
    $source = [IO.Path]::GetFullPath((Join-Path $unpack 'cmdline-tools'))
    $target = [IO.Path]::GetFullPath((Join-Path $sdkRoot 'cmdline-tools/latest'))
    $boundary = [IO.Path]::GetFullPath((Join-Path $projectRoot '.tools')) + [IO.Path]::DirectorySeparatorChar
    if (-not $source.StartsWith($boundary) -or -not $target.StartsWith($boundary)) { throw 'SDK target outside workspace.' }
    Move-Item -LiteralPath $source -Destination $target
}
$env:ANDROID_HOME = $sdkRoot
$proxyOptions = @()
if ($env:HTTPS_PROXY) {
    $proxyAddress = [uri]$env:HTTPS_PROXY
    $proxyOptions = @('--proxy=http', "--proxy_host=$($proxyAddress.Host)", "--proxy_port=$($proxyAddress.Port)")
}
(1..40 | ForEach-Object { 'y' }) | & $manager "--sdk_root=$sdkRoot" @proxyOptions --licenses
if ($LASTEXITCODE -ne 0) { throw 'SDK licenses failed.' }
& $manager "--sdk_root=$sdkRoot" @proxyOptions 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'emulator' 'system-images;android-35;default;x86_64'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }
Write-Output "Android SDK installed at $sdkRoot"
