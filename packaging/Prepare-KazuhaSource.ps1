#requires -Version 7.2
<#
.SYNOPSIS
Creates an isolated Kazuha branding copy of pinned Composa source.
.DESCRIPTION
Leaves the upstream checkout unchanged. The output is a local clone at the same
release commit, with exact, reviewable display-string and icon replacements.
Internal Composa namespaces, assembly names, MCP and .cmps identifiers remain.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $LogoPath,
    [string] $SourceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'source\Composa'),
    [string] $OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) ('build\kazuha-source-' + [guid]::NewGuid().ToString('N')))
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$commit = '86529d3b5355d28ddc28ec3db2e4de1d4d00f63b'
$utf8 = [Text.UTF8Encoding]::new($false)
$source = (Resolve-Path -LiteralPath $SourceDirectory).ProviderPath
$logo = (Resolve-Path -LiteralPath $LogoPath).ProviderPath
$logoHash = (Get-FileHash -LiteralPath $logo -Algorithm SHA256).Hash.ToLowerInvariant()
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory already exists; choose a fresh build-copy path.' }
if ($output.StartsWith($source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Build copy must be outside the upstream checkout.' }
if ((& git -C $source rev-parse HEAD) -cne $commit -or $LASTEXITCODE -ne 0) { throw 'Unexpected upstream source revision.' }
if ((& git -C $source rev-parse 'v1.4.0^{commit}') -cne $commit -or $LASTEXITCODE -ne 0) { throw 'Unexpected upstream release tag.' }
if (@(& git -C $source status --porcelain --untracked-files=no).Count -ne 0 -or $LASTEXITCODE -ne 0) { throw 'Upstream source must have no tracked changes.' }
$null = New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force
& git clone --local --no-hardlinks --no-checkout -- $source $output
if ($LASTEXITCODE -ne 0) { throw 'Could not create the local source copy.' }
& git -C $output checkout --detach $commit
if ($LASTEXITCODE -ne 0) { throw 'Could not check out the pinned source in the build copy.' }
$before = @{}
function Edit-BrandText([string] $Relative, [object[]] $Replacements) {
    $path = Join-Path $output $Relative
    if (-not $before.ContainsKey($Relative)) { $before[$Relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $text = [IO.File]::ReadAllText($path)
    if ($Replacements.Count -eq 2 -and $Replacements[0] -is [string]) { $Replacements = ,$Replacements }
    foreach ($pair in $Replacements) {
        if (-not $text.Contains($pair[0], [StringComparison]::Ordinal)) { throw "Expected branding text not found in ${Relative}: $($pair[0])" }
        $text = $text.Replace($pair[0], $pair[1])
    }
    [IO.File]::WriteAllText($path, $text, $utf8)
}
Edit-BrandText 'src/Composa.App/AppInfo.cs' @(
    @('public const string Name = "Composa";', 'public const string Name = "Kazuha";')
)
Edit-BrandText 'src/Composa.App/MainWindow.cs' @(
    @('"Composa"', '"Kazuha"'),
    @(' - Composa"', ' - Kazuha"'),
    @('Composa did not close normally', 'Kazuha did not close normally'),
    @('Another Composa window', 'Another Kazuha window')
)
Edit-BrandText 'src/Composa.App/MainWindow.Commands.cs' @(
    @('About Composa', 'About Kazuha'),
    @('Composa {AppInfo.Version}', 'Kazuha {AppInfo.Version}'),
    @('Composa project', 'Kazuha project (.cmps)'),
    @('Exported from Composa:', 'Exported from Kazuha:'),
    @('It is a from-scratch implementation of the open-source macOS app Compositor by Robbie Tilton (MIT license).',
      'Kazuha is an independent Windows edition of Composa by Dennis van der Stelt (MIT license). Composa reimplements Compositor by Robbie Tilton / Wonder Assembly LLC (MIT license).\n\nComposa: https://github.com/dvdstelt/Composa\nCompositor: https://github.com/robbietilton/Compositor\nKazuha: https://github.com/FupaulHuang/kazuha')
)
Edit-BrandText 'src/Composa.App/MainWindow.Updates.cs' @(
    @('Composa {AppInfo.Version}', 'Kazuha {AppInfo.Version}'),
    @('Quit Composa,', 'Quit Kazuha,')
)
Edit-BrandText 'src/Composa.App/UpdateNotice.cs' @(
    @('"Composa {version}', '"Kazuha {version}'),
    @('Downloading Composa {version}', 'Downloading Kazuha {version}')
)
Edit-BrandText 'Directory.Build.props' @(
    @('<Product>Composa</Product>', "<Product>Kazuha</Product>`n    <AssemblyTitle>Kazuha</AssemblyTitle>`n    <Description>Kazuha layer-based image editor.</Description>"),
    @('<Company>Dennis van der Stelt</Company>', '<Company>Kazuha</Company>')
)
# These existing tests assert visible names; keep their behavioral assertions.
Edit-BrandText 'tests/Composa.App.Tests/UpdateNoticeTests.cs' @(
    @('Downloading Composa 9.9.9', 'Downloading Kazuha 9.9.9'),
    @('"Composa 9.9.9 is ready', '"Kazuha 9.9.9 is ready')
)
Edit-BrandText 'tests/Composa.App.Tests/AppPathsTests.cs' @(
    @('"Composa"', '"Kazuha"')
)

Add-Type -AssemblyName System.Drawing
$logoImage = [Drawing.Image]::FromFile($logo)
$iconFiles = @('src/Composa.App/Assets/icon.png', 'packaging/icons/composa.ico', 'packaging/icons/composa-1024.png', 'packaging/icons/composa-512.png')
foreach ($relative in $iconFiles) {
    $path = Join-Path $output $relative
    if (Test-Path -LiteralPath $path) { $before[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    else { $before[$relative] = $null }
}
function Get-IconPng([int] $Size) {
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $memory = [IO.MemoryStream]::new()
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($logoImage, 0, 0, $Size, $Size)
        $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
        return ,$memory.ToArray()
    }
    finally { $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    if ($logoImage.Width -ne $logoImage.Height) { throw 'The Kazuha application logo must be square.' }
    [IO.File]::WriteAllBytes((Join-Path $output 'src/Composa.App/Assets/icon.png'), (Get-IconPng 256))
    [IO.File]::WriteAllBytes((Join-Path $output 'packaging/icons/composa-512.png'), (Get-IconPng 512))
    [IO.File]::WriteAllBytes((Join-Path $output 'packaging/icons/composa-1024.png'), (Get-IconPng 1024))
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $images = @($sizes | ForEach-Object { ,(Get-IconPng $_) })
    $ico = [IO.File]::Create((Join-Path $output 'packaging/icons/composa.ico'))
    $writer = [IO.BinaryWriter]::new($ico)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
            $offset += $images[$i].Length
        }
        foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
    }
    finally { $writer.Dispose(); $ico.Dispose() }
}
finally { $logoImage.Dispose() }
if ((Get-FileHash -LiteralPath $logo -Algorithm SHA256).Hash.ToLowerInvariant() -cne $logoHash) {
    throw 'The master logo changed during preparation; create a fresh source copy from the final asset.'
}

$changedFiles = @($before.Keys | Sort-Object | ForEach-Object {
    [ordered]@{path=$_;baseSha256=$before[$_];sha256=(Get-FileHash -LiteralPath (Join-Path $output $_) -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$patchFile = $output + '.branding.patch'
$patchLines = @(& git -C $output diff --binary --no-ext-diff HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Could not record source branding diff.' }
[IO.File]::WriteAllText($patchFile, (($patchLines -join "`n") + "`n"), $utf8)
$record = [ordered]@{
    schemaVersion=1; name='Kazuha'; sourceCommit=$commit
    preparationScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    logoSha256=$logoHash
    preparedAtUtc=[DateTime]::UtcNow.ToString('o'); sourceDirectory=$output
    sourceDiffSha256=(Get-FileHash -LiteralPath $patchFile -Algorithm SHA256).Hash.ToLowerInvariant()
    patchFile=$patchFile; changedFiles=$changedFiles
}
$recordPath = $output + '.branding.json'
[IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 5), $utf8)
[pscustomobject]@{SourceDirectory=$output;BrandingRecord=$recordPath;Patch=$patchFile;ChangedFiles=$changedFiles.Count}
