param([switch]$ShowWindow)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:ANDROID_HOME = Join-Path $projectRoot '.tools/android-sdk'
$env:ANDROID_AVD_HOME = Join-Path $projectRoot '.tools/avd'
$options = @('-avd', 'F1Reminder_API35', '-no-audio', '-no-boot-anim', '-no-snapshot', '-no-metrics', '-gpu', 'swiftshader', '-memory', '2560', '-cores', '2', '-port', '5554')
if (-not $ShowWindow) { $options += '-no-window' }
& (Join-Path $env:ANDROID_HOME 'emulator/emulator.exe') @options
