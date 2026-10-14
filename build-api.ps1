param(
    [Parameter(Mandatory = $true)][string]$AirSdk
)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskCompiler = Join-Path $AirSdk 'bin/acompc.bat'
if (-not (Test-Path -LiteralPath $taskCompiler)) { throw 'Windows AIR SDK with bin/acompc.bat is required.' }
$taskBuild = Join-Path $taskRoot 'build'
New-Item -ItemType Directory -Force -Path $taskBuild | Out-Null
& $taskCompiler "-source-path=$taskRoot/as3" '-include-classes=com.fdp.documentpicker.DocumentPickerExtension' `
    "-output=$taskBuild/FDPDocumentPicker.swc" '-target-player=51.0' '-swf-version=51' '-strict=true'
if ($LASTEXITCODE -ne 0) { throw "ActionScript API compilation failed ($LASTEXITCODE)." }
Write-Output "Compiled API only: $taskBuild/FDPDocumentPicker.swc"
Write-Output 'This is not an iOS ANE. Run build-macos.sh on macOS with Xcode for the native binary.'
