param([string]$Executable)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$settingsDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Composa'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
$directoryExisted = Test-Path -LiteralPath $settingsDirectory
$fileExisted = Test-Path -LiteralPath $settingsPath
$originalBytes = if ($fileExisted) { [IO.File]::ReadAllBytes($settingsPath) } else { $null }
$resultCode = 1
try {
    [IO.Directory]::CreateDirectory($settingsDirectory) | Out-Null
    [IO.File]::WriteAllText($settingsPath, '{"AllowAiControl":true,"CheckForUpdates":false,"WindowWidth":1400,"WindowHeight":940}')
    if ($Executable) { $env:COMPOSA_TEST_EXE = $Executable }
    & node (Join-Path $PSScriptRoot 'smoke-test.mjs')
    $resultCode = $LASTEXITCODE
}
finally {
    if ($fileExisted) {
        [IO.File]::WriteAllBytes($settingsPath, $originalBytes)
    }
    elseif (Test-Path -LiteralPath $settingsPath) {
        Remove-Item -LiteralPath $settingsPath
    }
    if (-not $directoryExisted -and (Test-Path -LiteralPath $settingsDirectory) -and @(Get-ChildItem -LiteralPath $settingsDirectory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $settingsDirectory
    }
    $audit = [ordered]@{ SettingsPath=$settingsPath; PreviouslyExisted=[bool]$fileExisted; RestoredOriginal=[bool]$fileExisted; RemovedTemporary=(-not $fileExisted -and -not (Test-Path -LiteralPath $settingsPath)); ResultCode=$resultCode }
    $audit | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $workspace 'verification/settings-restoration.json') -Encoding utf8
    Remove-Item Env:COMPOSA_TEST_EXE -ErrorAction SilentlyContinue
}
exit $resultCode
