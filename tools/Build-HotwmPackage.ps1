# Build-HotwmPackage.ps1 — Hook of the Wiimote Portable Release Packager
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$Version = "1.0.0",
    [switch]$IncludeTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path "$PSScriptRoot\..").Path

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "dist"
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$packageName = "frieds-hotwm-v$Version"
$zipPath = Join-Path $OutDir "$packageName.zip"
$shaPath = Join-Path $OutDir "$packageName.zip.sha256"

$stageDir = Join-Path ([System.IO.Path]::GetTempPath()) "hotwm_pkg_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

try {
    Write-Host "Staging files for Hook of the Wiimote v$Version..." -ForegroundColor Cyan

    $includeDirs = @("src", "config", "gui", "tools", "contract")
    if ($IncludeTests) {
        $includeDirs += "tests"
    }

    foreach ($dir in $includeDirs) {
        $srcDir = Join-Path $projectRoot $dir
        if (Test-Path $srcDir) {
            $destDir = Join-Path $stageDir $dir
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null

            Get-ChildItem -Path $srcDir -Recurse | Where-Object {
                -not $_.PSIsContainer -and
                $_.FullName -notmatch '\\__pycache__\\' -and
                $_.Extension -ne '.pyc' -and
                $_.FullName -notmatch '\\\.omc\\'
            } | ForEach-Object {
                $relPath = $_.FullName.Substring($srcDir.Length).TrimStart('\', '/')
                $targetFile = Join-Path $destDir $relPath
                $targetParent = [System.IO.Path]::GetDirectoryName($targetFile)
                if (-not (Test-Path $targetParent)) {
                    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $targetFile -Force
            }
        }
    }

    # Root files
    $rootFiles = @("Start-HotwmDashboard.bat", "README.md", "README.de.md", "LICENSE")
    foreach ($f in $rootFiles) {
        $sourcePath = Join-Path $projectRoot $f
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination (Join-Path $stageDir $f) -Force
        }
    }

    # Remove existing zip if present
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Write-Host "Creating archive: $zipPath" -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath)

    # Compute SHA256
    $fileStream = [System.IO.File]::OpenRead($zipPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($fileStream)
    $fileStream.Close()
    $hashString = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    Set-Content -Path $shaPath -Value "$hashString  $packageName.zip" -Encoding utf8

    $zipItem = Get-Item $zipPath
    $sizeKb = [math]::Round($zipItem.Length / 1KB, 2)
    $fileCount = (Get-ChildItem -Path $stageDir -Recurse -File).Count

    Write-Host "Package created successfully: $zipPath ($sizeKb KB, $fileCount files)" -ForegroundColor Green
    Write-Host "SHA256: $hashString" -ForegroundColor Gray

    return [PSCustomObject]@{
        ArchiveFile = $zipPath
        Sha256File  = $shaPath
        Sha256      = $hashString
        SizeKB      = $sizeKb
        FileCount   = $fileCount
        Version     = $Version
    }
}
finally {
    if (Test-Path $stageDir) {
        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
