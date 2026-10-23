$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace 'verification\installed'
[IO.Directory]::CreateDirectory($output) | Out-Null
$packageFullName = 'Local.Composa.Windows_1.4.0.0_x64__xm7mbcjr5tpj6'
$packageFamilyName = 'Local.Composa.Windows_xm7mbcjr5tpj6'
$executable = 'C:\Program Files\WindowsApps\Local.Composa.Windows_1.4.0.0_x64__xm7mbcjr5tpj6\composa.exe'
$applicationId = 'shell:AppsFolder\' + $packageFamilyName + '!Composa'
$settingsPaths = @(
    (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Composa\settings.json'),
    (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Packages\' + $packageFamilyName + '\LocalCache\Roaming\Composa\settings.json'))
)
$snapshots = @()
$testProcess = $null
$normalProcess = $null
$resultCode = 1
$failure = $null
$restored = $false

function Start-RegisteredComposa {
    $before = @(Get-Process -Name composa -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    Start-Process -FilePath explorer.exe -ArgumentList $applicationId -WindowStyle Hidden
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $started = @(Get-Process -Name composa -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -eq $executable -and $_.Id -notin $before -and $_.MainWindowHandle -ne 0
        })
        if ($started.Count -eq 1) { return $started[0] }
        if ($started.Count -gt 1) { throw 'More than one new package process appeared.' }
        Start-Sleep -Milliseconds 500
    }
    throw 'The registered package did not create a window within 30 seconds.'
}

function Get-BytesHash([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

if (@(Get-Process -Name composa -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Composa is already running. Refusing to change settings beneath an existing process.'
}

try {
    foreach ($settingsPath in $settingsPaths) {
        $existed = Test-Path -LiteralPath $settingsPath
        $bytes = if ($existed) { [IO.File]::ReadAllBytes($settingsPath) } else { $null }
        $backupName = if ($snapshots.Count -eq 0) { 'settings-real.original.json' } else { 'settings-package.original.json' }
        if ($existed) { [IO.File]::WriteAllBytes((Join-Path $output $backupName), $bytes) }
        $snapshots += [pscustomobject]@{
            Path = $settingsPath
            Existed = $existed
            Bytes = $bytes
            Sha256 = if ($existed) { Get-BytesHash $bytes } else { $null }
            Backup = if ($existed) { Join-Path $output $backupName } else { $null }
        }
    }
    # The per-package location takes precedence over the shared roaming file.
    # Only this temporary package copy is changed to enable the test bridge.
    $packageSettings = $settingsPaths[1]
    $temporarySettings = if ($snapshots[1].Existed) {
        [Text.Encoding]::UTF8.GetString($snapshots[1].Bytes) | ConvertFrom-Json
    } elseif ($snapshots[0].Existed) {
        [Text.Encoding]::UTF8.GetString($snapshots[0].Bytes) | ConvertFrom-Json
    } else { [pscustomobject]@{} }
    $temporarySettings | Add-Member -NotePropertyName AllowAiControl -NotePropertyValue $true -Force
    $temporarySettings | Add-Member -NotePropertyName CheckForUpdates -NotePropertyValue $false -Force
    [IO.Directory]::CreateDirectory((Split-Path -Parent $packageSettings)) | Out-Null
    [IO.File]::WriteAllText($packageSettings, ($temporarySettings | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))

    $testProcess = Start-RegisteredComposa
    Write-Output ('Activated installed package process ' + $testProcess.Id)
    & (Join-Path $PSScriptRoot 'Run-InstalledSmokeTest.ps1') -Executable $executable -PackageFullName $packageFullName -ApplicationProcessId $testProcess.Id
    $resultCode = $LASTEXITCODE
    if ($resultCode -ne 0) { throw "Installed smoke test failed with exit code $resultCode." }
    $nativeModules = $testProcess.Modules | Where-Object { $_.ModuleName -match 'onnx|Skia|HarfBuzz|Magick' } |
        Select-Object ModuleName, FileName
    @($nativeModules) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $output 'native-modules.json') -Encoding utf8
} catch {
    $failure = $_.Exception.ToString()
    Write-Output $failure
} finally {
    # Every test document is saved by the harness before this normal close.
    if ($null -ne $testProcess -and -not $testProcess.HasExited) {
        if (-not $testProcess.CloseMainWindow()) { throw 'Could not request a normal close for the package test window.' }
        if (-not $testProcess.WaitForExit(10000)) {
            throw 'The test window did not close; settings have not been restored beneath the running app.'
        }
    }
    foreach ($snapshot in $snapshots) {
        if ($snapshot.Existed) { [IO.File]::WriteAllBytes($snapshot.Path, $snapshot.Bytes) }
        elseif (Test-Path -LiteralPath $snapshot.Path) { Remove-Item -LiteralPath $snapshot.Path }
    }
    $restoration = foreach ($snapshot in $snapshots) {
        $present = Test-Path -LiteralPath $snapshot.Path
        $actual = if ($present) { Get-BytesHash ([IO.File]::ReadAllBytes($snapshot.Path)) } else { $null }
        [pscustomobject]@{
            SettingsPath = $snapshot.Path
            PreviouslyExisted = $snapshot.Existed
            OriginalSha256 = $snapshot.Sha256
            RestoredSha256 = $actual
            RestoredExactly = ($present -eq $snapshot.Existed -and $actual -eq $snapshot.Sha256)
            BackupPath = $snapshot.Backup
        }
    }
    @($restoration) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'settings-restoration.json') -Encoding utf8
    if (@($restoration | Where-Object { -not $_.RestoredExactly }).Count -ne 0) { throw 'Settings restoration verification failed.' }
    $restored = $true
}

if ($restored) {
    $normalProcess = Start-RegisteredComposa
    [pscustomobject]@{
        ActivatedAt = [DateTime]::UtcNow.ToString('o')
        PackageFullName = $packageFullName
        Executable = $executable
        NormalApplicationProcessId = $normalProcess.Id
        SettingsRestored = $restored
        SmokeTestResultCode = $resultCode
        Error = $failure
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'normal-launch.json') -Encoding utf8
    Write-Output ('Normal installed app relaunched with restored settings; PID ' + $normalProcess.Id)
}
if ($failure) { exit 1 }
exit $resultCode
