# Build the pinned Kazuha-branded source with a workspace-local .NET SDK.
# Prepare-KazuhaSource.ps1 supplies SourceDirectory and BrandingRecordPath.
# Install/extract SDK 10.0.402 under build/dotnet first, or pass DotnetRoot.
param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [Parameter(Mandatory=$true)][string]$BrandingRecordPath,
    [string]$DotnetRoot,
    [string]$OutputRootPath,
    [string]$ReportsDirectory,
    [switch]$SkipTests,
    [string]$TestEvidenceProvenancePath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = Split-Path -Parent $PSScriptRoot
$source = [IO.Path]::GetFullPath($SourceDirectory)
$upstream = Join-Path $workspace 'source\Composa'
if (-not $source.StartsWith((Join-Path $workspace 'build') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Branding source must stay inside workspace build directory' }
$brandingRecordFile = [IO.Path]::GetFullPath($BrandingRecordPath)
$branding = Get-Content -LiteralPath $brandingRecordFile -Raw | ConvertFrom-Json
$brandingHash = (Get-FileHash -LiteralPath $brandingRecordFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($branding.name -ne 'Kazuha' -or $branding.sourceDirectory -ne $source -or $branding.sourceCommit -ne '86529d3b5355d28ddc28ec3db2e4de1d4d00f63b') { throw 'Unexpected branding source record' }
$sdkRoot = if ($DotnetRoot) { [IO.Path]::GetFullPath($DotnetRoot) } else { Join-Path $workspace 'build\dotnet' }
$dotnet = Join-Path $sdkRoot 'dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet -PathType Leaf)) { throw 'SDK not found. Extract the official .NET SDK 10.0.402 Windows x64 ZIP into build/dotnet, or pass -DotnetRoot. This helper does not install an SDK globally.' }
$outputRoot = if ($OutputRootPath) { [IO.Path]::GetFullPath($OutputRootPath) } else { Join-Path $workspace 'dist\store-managed' }
if (-not $outputRoot.StartsWith((Join-Path $workspace 'dist') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must stay inside workspace dist directory' }
$payload = Join-Path $outputRoot 'kazuha-1.4.0-win-x64'
if (Test-Path -LiteralPath $payload) { throw 'The payload output already exists. Choose a fresh -OutputRootPath so stale files cannot enter the package.' }
$reports = if ($ReportsDirectory) { [IO.Path]::GetFullPath($ReportsDirectory) } else { Join-Path $workspace 'verification\store-managed-final' }
if (-not $reports.StartsWith((Join-Path $workspace 'verification') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Reports must stay inside workspace verification directory' }
$environmentNames = @('DOTNET_ROOT','DOTNET_CLI_HOME','NUGET_PACKAGES','NUGET_HTTP_CACHE_PATH','NUGET_PLUGINS_CACHE_PATH','NUGET_SCRATCH','DOTNET_CLI_TELEMETRY_OPTOUT','DOTNET_SKIP_FIRST_TIME_EXPERIENCE','DOTNET_GENERATE_ASPNET_CERTIFICATE','DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE','DOTNET_NOLOGO','DOTNET_MULTILEVEL_LOOKUP','PATH')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$originalLocation = Get-Location
try {
$env:DOTNET_ROOT = $sdkRoot
$env:DOTNET_CLI_HOME = Join-Path $workspace 'build\dotnet-home'
$env:NUGET_PACKAGES = Join-Path $workspace 'build\nuget'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $workspace 'build\nuget-http-cache'
$env:NUGET_PLUGINS_CACHE_PATH = Join-Path $workspace 'build\nuget-plugins-cache'
$env:NUGET_SCRATCH = Join-Path $workspace 'build\nuget-scratch'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_MULTILEVEL_LOOKUP = '0'
$env:PATH = $sdkRoot + [IO.Path]::PathSeparator + $env:PATH
New-Item -ItemType Directory -Path $outputRoot,$reports -Force | Out-Null
Set-Location -LiteralPath $source
$commit = (& git rev-parse HEAD).Trim()
$sourceTag = (& git describe --exact-match --tags HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -ne '86529d3b5355d28ddc28ec3db2e4de1d4d00f63b' -or $sourceTag -ne 'v1.4.0') { throw 'Unexpected source revision or tag' }
$upstreamCommit = & git -C $upstream rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $upstreamCommit.Trim() -ne $commit) { throw 'Pristine upstream revision is not the pinned source commit' }
$upstreamStatus = @(& git -C $upstream status --porcelain)
if ($LASTEXITCODE -ne 0 -or $upstreamStatus.Count -ne 0) { throw 'Pristine upstream source changed or could not be inspected' }
foreach ($entry in $branding.changedFiles) {
    $brandedPath = [IO.Path]::GetFullPath((Join-Path $source $entry.path))
    if (-not $brandedPath.StartsWith($source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Branding record path leaves source' }
    if ((Get-FileHash -LiteralPath $brandedPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Branding record mismatch: $($entry.path)" }
}
$diffCheck = Join-Path $reports 'source-before-build.diff'
$diffLines = @(& git -C $source diff --binary --no-ext-diff HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect branding source diff' }
[IO.File]::WriteAllText($diffCheck, (($diffLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$diffHash = (Get-FileHash -LiteralPath $diffCheck -Algorithm SHA256).Hash.ToLowerInvariant()
if ($diffHash -ne $branding.sourceDiffSha256) { throw 'Branding source diff differs from preparation record' }
$modelChecks = @{
    'modnet.onnx'='07c308cf0fc7e6e8b2065a12ed7fc07e1de8febb7dc7839d7b7f15dd66584df9'
    'u2netp.onnx'='309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8'
    'realesr-general-x4v3.onnx'='09b757accd747d7e423c1d352b3e8f23e77cc5742d04bae958d4eb8082b76fa4'
}
foreach ($modelName in $modelChecks.Keys) {
    $modelDestination = Join-Path $source "src\Composa.Core\Models\$modelName"
    if (-not (Test-Path -LiteralPath $modelDestination)) {
        if ($modelName -ne 'modnet.onnx') { throw "Tracked model absent: $modelName" }
        $modelSource = Join-Path $upstream "src\Composa.Core\Models\$modelName"
        if (-not (Test-Path -LiteralPath $modelSource -PathType Leaf)) { throw 'MODNet is missing. Run scripts/models/fetch.sh in the pristine upstream checkout first; the pinned model is ignored by Git.' }
        if ((Get-FileHash -LiteralPath $modelSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $modelChecks[$modelName]) { throw 'Cached upstream model hash mismatch' }
        Copy-Item -LiteralPath $modelSource -Destination $modelDestination
    }
    if ((Get-FileHash -LiteralPath $modelDestination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $modelChecks[$modelName]) { throw "Model hash mismatch: $modelName" }
}
$sdkVersion = (& $dotnet --version).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkVersion -ne '10.0.402') { throw 'Unexpected SDK version' }
Write-Output "Building Kazuha from $sourceTag with recorded branding using SDK $sdkVersion"
$publishArgs = @('publish','src/Composa.App','-c','Release','-r','win-x64','--self-contained','true','-p:DebugType=none','-p:UpdateChannel=managed','-o',$payload)
& $dotnet @publishArgs 2>&1 | Tee-Object -FilePath (Join-Path $reports 'publish.log')
if ($LASTEXITCODE -ne 0) { throw "Publish failed: $LASTEXITCODE" }
foreach ($document in @('LICENSE','README.md','CHANGELOG.md')) { Copy-Item -LiteralPath (Join-Path $source $document) -Destination (Join-Path $payload $document) }
foreach ($required in @('composa.exe','composa.dll','LICENSE','THIRD-PARTY-NOTICES.txt','ImageMagick-NOTICE.txt','models/u2netp.onnx','models/modnet.onnx','models/realesr-general-x4v3.onnx','coreclr.dll','hostfxr.dll','hostpolicy.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) { throw "Payload missing $required" }
}
if (@(Get-ChildItem -LiteralPath $payload -Recurse -File -Filter '*.pdb').Count -ne 0) { throw 'Payload contains debug symbols' }
$productVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $payload 'composa.dll')).ProductVersion
if ($productVersion.Split('+')[0] -ne '1.4.0') { throw "MinVer release version incorrect: $productVersion" }
Write-Output "Published version $productVersion to $payload"
$tests = @(
    @{name='updater';project='tests/Composa.App.Tests/Composa.App.Tests.csproj';filter='FullyQualifiedName~UpdateCheckTests|FullyQualifiedName~ReleaseVersionTests|FullyQualifiedName~UpdateNoticeTests|FullyQualifiedName~UpdateWindowTests|FullyQualifiedName~UpdateDownloadTests|FullyQualifiedName~ReleaseAssetsTests|FullyQualifiedName~InstallKindTests|FullyQualifiedName~InstallerTests|FullyQualifiedName~BundledImageMagickTests|FullyQualifiedName~AppPathsTests'},
    @{name='core';project='tests/Composa.Core.Tests/Composa.Core.Tests.csproj';filter='FullyQualifiedName~RenderingTests|FullyQualifiedName~ViewRenderingTests|FullyQualifiedName~CompositingQaTests|FullyQualifiedName~EditingTests|FullyQualifiedName~HistoryTests|FullyQualifiedName~TextLayerTests'}
)
$testResults = @()
$testEvidence = $null
if ($TestEvidenceProvenancePath) {
    if (-not $SkipTests) { throw 'Reusing test evidence requires SkipTests' }
    $testEvidencePath = [IO.Path]::GetFullPath($TestEvidenceProvenancePath)
    $previousBuild = Get-Content -LiteralPath $testEvidencePath -Raw | ConvertFrom-Json
    if ($previousBuild.sourceCommit -ne $commit -or $previousBuild.sdkVersion -ne $sdkVersion -or $previousBuild.configuration -ne 'Release' -or $previousBuild.runtimeIdentifier -ne 'win-x64' -or $previousBuild.updateChannel -ne 'managed') { throw 'Previous test evidence is not from an equivalent build' }
    $iconPaths = @('packaging/icons/composa-1024.png','packaging/icons/composa-512.png','packaging/icons/composa.ico','src/Composa.App/Assets/icon.png')
    $previousNonIcons = @($previousBuild.brandingRecord.changedFiles | Where-Object { $_.path -notin $iconPaths } | Sort-Object path)
    $currentNonIcons = @($branding.changedFiles | Where-Object { $_.path -notin $iconPaths } | Sort-Object path)
    if ($previousNonIcons.Count -ne $currentNonIcons.Count) { throw 'Non-icon source files differ from tested build' }
    for ($index=0; $index -lt $currentNonIcons.Count; $index++) {
        if ($previousNonIcons[$index].path -ne $currentNonIcons[$index].path -or $previousNonIcons[$index].sha256 -ne $currentNonIcons[$index].sha256 -or $previousNonIcons[$index].baseSha256 -ne $currentNonIcons[$index].baseSha256) { throw 'Non-icon source content differs from tested build' }
    }
    $testResults = @($previousBuild.testResults)
    if ($testResults.Count -ne 2 -or @($testResults | Where-Object { $_.failed -ne 0 -or $_.passed -lt 1 }).Count -ne 0) { throw 'Previous test evidence is incomplete or failed' }
    $testEvidence = [ordered]@{
        reusedFromProvenance=$testEvidencePath
        provenanceSha256=(Get-FileHash -LiteralPath $testEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        testedSourceDirectory=$previousBuild.buildSourceDirectory
        testedBrandingRecordSha256=$previousBuild.brandingRecordSha256
        testedSourceDiffSha256=$previousBuild.sourceDiffSha256
        reuseReason='All non-icon branding changes have identical hashes to the tested preview, based on the same upstream commit and SDK. Only the four application icon assets differ.'
        comparedNonIconFiles=@($currentNonIcons | ForEach-Object { [ordered]@{path=$_.path;sha256=$_.sha256} })
        iconPathsExcludedFromBehavioralComparison=$iconPaths
    }
    Write-Output 'Reusing successful preview behavioral tests: all non-icon branding source hashes match'
}
if ($SkipTests) { $tests = @() }
foreach ($test in $tests) {
    $testArgs = @('test',$test.project,'-c','Release','-p:UpdateChannel=github','--filter',$test.filter,'--logger',"trx;LogFileName=$($test.name).trx",'--results-directory',$reports)
    & $dotnet @testArgs 2>&1 | Tee-Object -FilePath (Join-Path $reports "$($test.name)-tests.log")
    if ($LASTEXITCODE -ne 0) { throw "$($test.name) tests failed: $LASTEXITCODE" }
    [xml]$trx = Get-Content -LiteralPath (Join-Path $reports "$($test.name).trx") -Raw
    $counters = $trx.TestRun.ResultSummary.Counters
    $testResults += [ordered]@{name=$test.name;project=$test.project;filter=$test.filter;updateChannel='github';passed=[int]$counters.passed;failed=[int]$counters.failed;total=[int]$counters.total;notExecuted=[int]$counters.notExecuted;report=(Join-Path $reports "$($test.name).trx")}
}
$diffLines = @(& git -C $source diff --binary --no-ext-diff HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect branding source after build' }
[IO.File]::WriteAllText((Join-Path $reports 'source-after-build.diff'), (($diffLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
if ((Get-FileHash -LiteralPath (Join-Path $reports 'source-after-build.diff') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $diffHash) { throw 'Branding source changed during build' }
$upstreamStatus = @(& git -C $upstream status --porcelain)
if ($LASTEXITCODE -ne 0 -or $upstreamStatus.Count -ne 0) { throw 'Pristine upstream source changed or could not be inspected after build' }
$sdkDownload = $null
$sdkMetadataPath = Join-Path $workspace 'build\dotnet-download\sdk-file.json'
if (-not $DotnetRoot -and (Test-Path -LiteralPath $sdkMetadataPath -PathType Leaf)) {
    $sdkFile = Get-Content -LiteralPath $sdkMetadataPath -Raw | ConvertFrom-Json
    $sdkDownload = [ordered]@{url=$sdkFile.url;sha512=$sdkFile.hash;metadataUrl='https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json'}
}
$files = @(Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{path=[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bytes=$_.Length}
})
$provenance = [ordered]@{
    schemaVersion=1
    sourceRepository='https://github.com/dvdstelt/Composa'
    sourceCommit=$commit
    sourceDirty=$true
    upstreamSourceDirty=$false
    buildSourceDirectory=$source
    brandingRecord=$branding
    brandingRecordSha256=$brandingHash
    sourceDiffSha256=$diffHash
    sourceTag=$sourceTag
    sdkVersion=$sdkVersion
    configuration='Release'
    runtimeIdentifier='win-x64'
    selfContained=$true
    updateChannel='managed'
    debugType='none'
    builtAtUtc=[DateTime]::UtcNow.ToString('o')
    buildScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    publishCommand=('dotnet publish src/Composa.App -c Release -r win-x64 --self-contained true -p:DebugType=none -p:UpdateChannel=managed -o "' + $payload + '"')
    assemblyProductVersion=$productVersion
    sdkDownload=$sdkDownload
    testResults=$testResults
    testEvidence=$testEvidence
    files=$files
}
$provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'build-provenance.json') -Encoding utf8
Write-Output "Complete: $($files.Count) payload files; provenance at $outputRoot\build-provenance.json"
$testResults | ForEach-Object { [pscustomobject]$_ } | Format-Table name,passed,failed,total,notExecuted
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process') }
}
