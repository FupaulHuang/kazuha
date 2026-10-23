param(
    [Parameter(Mandatory = $true)][string] $Executable,
    [Parameter(Mandatory = $true)][string] $PackageFullName,
    [Parameter(Mandatory = $true)][int] $ApplicationProcessId,
    [string] $PipeName = 'composa-mcp',
    [string] $NodeExecutable = 'node'
)

# Attach to a package-activated app that the caller has prepared for testing.
# This wrapper never installs/launches the editor or changes any settings.
# The MCP client bridge is a short-lived subprocess; only its verified server
# can receive test edits. All output is under verification/installed.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$output = Join-Path $workspace 'verification\installed'
[IO.Directory]::CreateDirectory($output) | Out-Null
$Executable = (Resolve-Path -LiteralPath $Executable).ProviderPath

if (-not ('ComposaInstalledTest.ProcessIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace ComposaInstalledTest {
    public static class ProcessIdentity {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder name);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out uint processId);
        public static string Read(int processId) {
            IntPtr handle = OpenProcess(0x1000, false, processId);
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                uint length = 0;
                int code = GetPackageFullName(handle, ref length, null);
                if (code != 122) throw new Win32Exception(code, "Process does not expose the expected MSIX package identity.");
                var name = new StringBuilder((int)length);
                code = GetPackageFullName(handle, ref length, name);
                if (code != 0) throw new Win32Exception(code);
                return name.ToString();
            } finally { CloseHandle(handle); }
        }
    }
}
'@
}

$process = Get-Process -Id $ApplicationProcessId
if (-not $process.Path.Equals($Executable, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Application path mismatch: expected $Executable, found $($process.Path)."
}
$actualPackage = [ComposaInstalledTest.ProcessIdentity]::Read($ApplicationProcessId)
if ($actualPackage -cne $PackageFullName) { throw "Package identity mismatch: $actualPackage" }

$pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [IO.Pipes.PipeDirection]::InOut)
try {
    $pipe.Connect(5000)
    [uint32] $serverProcessId = 0
    if (-not [ComposaInstalledTest.ProcessIdentity]::GetNamedPipeServerProcessId($pipe.SafePipeHandle.DangerousGetHandle(), [ref]$serverProcessId)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    if ($serverProcessId -ne $ApplicationProcessId) {
        throw "MCP pipe belongs to process $serverProcessId, not the package-activated process $ApplicationProcessId. No test edits were made."
    }
} finally { $pipe.Dispose() }

$identity = [ordered]@{
    VerifiedAt = [DateTime]::UtcNow.ToString('o')
    Executable = $Executable
    PackageFullName = $actualPackage
    ApplicationProcessId = $ApplicationProcessId
    PipeName = $PipeName
    PipeServerProcessId = $serverProcessId
    WindowTitleBeforeTest = $process.MainWindowTitle
    ProcessStartTime = $process.StartTime.ToUniversalTime().ToString('o')
    Validation = 'Win32 GetPackageFullName and GetNamedPipeServerProcessId'
}
$identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'package-process-verification.json') -Encoding utf8

$testVariables = @{
    COMPOSA_TEST_EXE = $Executable
    COMPOSA_MCP_PIPE = $PipeName
    COMPOSA_INSTALLED_PACKAGE = $PackageFullName
    COMPOSA_INSTALLED_PID = [string]$ApplicationProcessId
}
$previousVariables = @{}
$resultCode = 1
try {
    foreach ($key in $testVariables.Keys) {
        $previousVariables[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $testVariables[$key], 'Process')
    }
    & $NodeExecutable (Join-Path $PSScriptRoot 'installed-smoke-test.mjs')
    $resultCode = $LASTEXITCODE
    $after = Get-Process -Id $ApplicationProcessId
    if ($after.StartTime -ne $process.StartTime) { throw 'The activated application process changed during the test.' }
    if ([ComposaInstalledTest.ProcessIdentity]::Read($ApplicationProcessId) -cne $PackageFullName) {
        throw 'Package identity changed during the test.'
    }
} finally {
    foreach ($key in $previousVariables.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previousVariables[$key], 'Process')
    }
}
exit $resultCode
