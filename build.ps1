param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework 4.x C# compiler is required.' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'Ryujin-LCD-Player.exe'
$arguments = @(
    '/nologo', '/target:winexe', '/platform:x64', '/optimize+',
    '/reference:System.Windows.Forms.dll',
    ('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')),
    ('/out:' + $output)
)
foreach ($name in @('Ryujin-Player.ps1','Ryujin-Usb.ps1','Ryujin-Storage.ps1','Ryujin-Sensors.ps1','Ryujin-Dashboard.jpg','Ryujin-Dashboard-temperature.jpg','Ryujin-Dashboard-mixed.jpg')) {
    $arguments += '/resource:' + (Join-Path $PSScriptRoot $name) + ',' + $name
}
$arguments += Join-Path $PSScriptRoot 'Launcher.cs'
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
Write-Output $output
