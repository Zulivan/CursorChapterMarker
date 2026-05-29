#Requires -Version 5.1
<#
.SYNOPSIS
    Build script for the cursor-chapter-marker OBS plugin.

.DESCRIPTION
    1. Downloads Qt6 obs-deps (headers + import libs)
    2. Sparse-clones obs-studio 32.0.4 for headers
    3. Generates obs.lib / obs-frontend-api.lib from the installed DLLs
    4. Configures and builds with cmake + Ninja (from VS BuildTools)
    5. Copies the DLL + data to OBS plugin directories

.PARAMETER SkipDownload
    Skip downloading deps (they already exist in .deps/)

.PARAMETER SkipBuild
    Skip the cmake build step

.PARAMETER InstallOnly
    Only copy the already-built DLL to OBS
#>
param(
    [switch]$SkipDownload,
    [switch]$SkipBuild,
    [switch]$InstallOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Paths ──────────────────────────────────────────────────────────────────
$root        = $PSScriptRoot
$depsDir     = "$root\.deps"
$buildDir    = "$root\build_x64"
$obsInstall  = "X:\obs-studio"
$obsBinDir   = "$obsInstall\bin\64bit"
$obsPlugDir  = "$obsInstall\obs-plugins\64bit"
$obsDataDir  = "$obsInstall\data\obs-plugins\cursor-chapter-marker"

$vsBase  = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
$cmake   = "$vsBase\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$ninja   = "$vsBase\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
$git     = "X:\Git\cmd\git.exe"

# Resolve lib.exe and dumpbin.exe from VS BuildTools
$msvcTools = Get-ChildItem "$vsBase\VC\Tools\MSVC" -Directory |
             Sort-Object Name -Descending | Select-Object -First 1
$libExe      = "$($msvcTools.FullName)\bin\Hostx64\x64\lib.exe"
$dumpbinExe  = "$($msvcTools.FullName)\bin\Hostx64\x64\dumpbin.exe"

# obs-deps versions (matching OBS 32.0.4 buildspec.json)
$obsDepsVersion = "2025-08-23"
$qt6Url  = "https://github.com/obsproject/obs-deps/releases/download/$obsDepsVersion/windows-deps-qt6-$obsDepsVersion-x64.zip"
$qt6Hash = "c62e82483bc7c0bf199e8ac3220c66a85a6e8a0cd69a05b6d44f873b830e415f"

$obsTag  = "32.0.4"
$obsRepo = "https://github.com/obsproject/obs-studio.git"

# ── Helpers ────────────────────────────────────────────────────────────────
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    [!!] $msg" -ForegroundColor Red; exit 1 }

function Invoke-Checked {
    param([string]$Exe, [string[]]$Args, [string]$WorkDir = $root)
    $result = & $Exe @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $result | Write-Host
        Write-Fail "Command failed: $Exe $Args"
    }
    $result
}

# ── Generate import lib from a DLL ────────────────────────────────────────
function New-ImportLib {
    param(
        [string]$DllPath,
        [string]$OutLib,
        [string]$LibExe,
        [string]$DumpbinExe
    )

    $libName = [IO.Path]::GetFileNameWithoutExtension($DllPath)
    $defPath = [IO.Path]::ChangeExtension($OutLib, ".def")

    # Extract exports via dumpbin (ignoring non-zero exit code)
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $raw = & $DumpbinExe /exports $DllPath 2>&1
    $ErrorActionPreference = $prev
    # Format: "   ordinal hint RVA name = name"
    $funcNames = $raw |
        Where-Object { $_ -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)' } |
        ForEach-Object { [regex]::Match($_, '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)').Groups[1].Value }

    if (-not $funcNames) {
        Write-Fail "No exports found in $DllPath - is dumpbin working?"
    }

    $def  = "LIBRARY $libName`r`nEXPORTS`r`n"
    $def += ($funcNames | ForEach-Object { "    $_" }) -join "`r`n"
    [IO.File]::WriteAllText($defPath, $def, [Text.Encoding]::ASCII)

    & $LibExe /nologo /machine:x64 /def:$defPath /out:$OutLib 2>&1 | Out-Null
    if (-not (Test-Path $OutLib)) { Write-Fail "lib.exe failed to produce $OutLib" }
    Write-OK "Generated $([IO.Path]::GetFileName($OutLib))"
}

# ── 0. Pre-flight checks ───────────────────────────────────────────────────
Write-Step "Pre-flight checks"
foreach ($tool in @($cmake, $ninja, $git, $libExe, $dumpbinExe)) {
    if (-not (Test-Path $tool)) { Write-Fail "Not found: $tool" }
}
if (-not (Test-Path $obsBinDir)) { Write-Fail "OBS not found at $obsInstall" }
Write-OK "All tools present"

New-Item -ItemType Directory -Force -Path $depsDir | Out-Null

# ── 1. Download Qt6 obs-deps ───────────────────────────────────────────────
$qt6Dir = "$depsDir\qt6"

if (-not $SkipDownload -and -not $InstallOnly) {
    Write-Step "Downloading Qt6 obs-deps ($obsDepsVersion)"
    $qt6Zip = "$depsDir\qt6.zip"

    if (-not (Test-Path $qt6Zip)) {
        Write-Host "    Downloading $qt6Url ..."
        Invoke-WebRequest -Uri $qt6Url -OutFile $qt6Zip -UseBasicParsing
    } else {
        Write-Host "    Using cached qt6.zip"
    }

    # Verify hash
    $hash = (Get-FileHash $qt6Zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $qt6Hash) {
        Write-Fail "Qt6 zip hash mismatch! Expected $qt6Hash, got $hash"
    }
    Write-OK "Hash verified"

    if (-not (Test-Path "$qt6Dir\lib\cmake")) {
        Write-Host "    Extracting Qt6..."
        Expand-Archive -Path $qt6Zip -DestinationPath $qt6Dir -Force
    } else {
        Write-Host "    Qt6 already extracted"
    }
    Write-OK "Qt6 ready at $qt6Dir"
} else {
    if (-not (Test-Path "$qt6Dir\lib\cmake")) {
        Write-Fail "Qt6 not found at $qt6Dir. Run without -SkipDownload first."
    }
    Write-OK "Using existing Qt6 at $qt6Dir"
}

# ── 2. Sparse-clone obs-studio headers ────────────────────────────────────
$obsHeadersDir = "$depsDir\obs-studio"

if (-not $SkipDownload -and -not $InstallOnly) {
    Write-Step "Fetching obs-studio $obsTag headers (sparse checkout)"

    if (-not (Test-Path "$obsHeadersDir\.git")) {
        Write-Host "    Cloning (sparse, depth 1)..."
        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & $git clone --depth 1 --branch $obsTag --filter=blob:none --sparse `
            $obsRepo $obsHeadersDir 2>&1 | Write-Host
        $cloneExit = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($cloneExit -ne 0) { Write-Fail "git clone failed (exit $cloneExit)" }

        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        Set-Location $obsHeadersDir
        & $git sparse-checkout set libobs frontend/api 2>&1 | Out-Null
        Set-Location $root
        $ErrorActionPreference = $prev
    } else {
        Write-Host "    obs-studio headers already present"
    }
    Write-OK "Headers at $obsHeadersDir"
} else {
    if (-not (Test-Path "$obsHeadersDir\libobs\obs-module.h")) {
        Write-Fail "OBS headers not found. Run without -SkipDownload first."
    }
    Write-OK "Using existing OBS headers"
}

# ── 3. Generate import libs ────────────────────────────────────────────────
$implibDir = "$depsDir\implibs"
New-Item -ItemType Directory -Force -Path $implibDir | Out-Null

$obsLib     = "$implibDir\obs.lib"
$frontendLib = "$implibDir\obs-frontend-api.lib"

if (-not $InstallOnly) {
    Write-Step "Generating import libs from OBS DLLs"

    if (-not (Test-Path $obsLib)) {
        New-ImportLib -DllPath "$obsBinDir\obs.dll" `
                      -OutLib $obsLib `
                      -LibExe $libExe `
                      -DumpbinExe $dumpbinExe
    } else {
        Write-OK "obs.lib already exists"
    }

    if (-not (Test-Path $frontendLib)) {
        New-ImportLib -DllPath "$obsBinDir\obs-frontend-api.dll" `
                      -OutLib $frontendLib `
                      -LibExe $libExe `
                      -DumpbinExe $dumpbinExe
    } else {
        Write-OK "obs-frontend-api.lib already exists"
    }
}

# ── 4. CMake configure + build ─────────────────────────────────────────────
if (-not $SkipBuild -and -not $InstallOnly) {
    Write-Step "Configuring cmake"

    # Normalise to forward-slashes for cmake
    function To-CMakePath($p) { $p -replace '\\', '/' }

    $cmakeArgs = @(
        "-S", $root,
        "-B", $buildDir,
        "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
        "-DCMAKE_MAKE_PROGRAM=$(To-CMakePath $ninja)",
        "-DOBS_BIN_DIR=$(To-CMakePath $obsBinDir)",
        "-DOBS_HEADERS_DIR=$(To-CMakePath $obsHeadersDir)",
        "-DOBS_IMPLIB_DIR=$(To-CMakePath $implibDir)",
        "-DOBS_DEPS_QT6_DIR=$(To-CMakePath $qt6Dir)"
    )

    # Use vcvars64 so MSVC cl.exe is on PATH for cmake
    $vcvars = "$vsBase\VC\Auxiliary\Build\vcvars64.bat"

    # Wrap cmake call inside cmd /c "vcvars64 && cmake ..."
    $cmakeArgStr = ($cmakeArgs | ForEach-Object { "`"$_`"" }) -join " "
    $cmdLine = "`"$vcvars`" && `"$cmake`" $cmakeArgStr"

    Write-Host "    Running: $cmdLine"
    $result = cmd /c $cmdLine 2>&1
    $result | Write-Host
    if ($LASTEXITCODE -ne 0) { Write-Fail "cmake configure failed" }
    Write-OK "cmake configured"

    Write-Step "Building"
    $buildCmd = "`"$vcvars`" && `"$cmake`" --build `"$buildDir`" --config RelWithDebInfo"
    $result = cmd /c $buildCmd 2>&1
    $result | Write-Host
    if ($LASTEXITCODE -ne 0) { Write-Fail "cmake build failed" }
    Write-OK "Build succeeded"
}

# ── 5. Copy to OBS ─────────────────────────────────────────────────────────
Write-Step "Installing to OBS"

$builtDll = "$buildDir\cursor-chapter-marker.dll"
if (-not (Test-Path $builtDll)) {
    Write-Fail "Built DLL not found at $builtDll — did the build succeed?"
}

Copy-Item -Path $builtDll -Destination $obsPlugDir -Force
Write-OK "Copied cursor-chapter-marker.dll -> $obsPlugDir"

# Copy locale data
$dataSource = "$root\data"
if (Test-Path $dataSource) {
    New-Item -ItemType Directory -Force -Path $obsDataDir | Out-Null
    Copy-Item -Path "$dataSource\*" -Destination $obsDataDir -Recurse -Force
    Write-OK "Copied data/ -> $obsDataDir"
}

Write-Host "`n*** Build + install complete! ***" -ForegroundColor Green
Write-Host "    DLL: $obsPlugDir\cursor-chapter-marker.dll"
Write-Host "    Data: $obsDataDir"
Write-Host "    Restart OBS to load the plugin."
