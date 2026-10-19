<#
release.ps1 - build and publish the WowVision installer.

  Much smaller than the Sku release script it comes from: WowVision itself is
  released by its maintainers (a V* tag in wow-vision/WowVision, packaged by a
  GitHub Action), and the installer finds each new addon release by itself. So
  this script only ever ships the INSTALLER: the exe and installer-version.txt,
  as a pair, on a release of the installer repository.

  BUILD ONLY (nothing leaves this PC):
    .\release.ps1 -BuildOnly
      1. dotnet build -c Release (installer + self-test).
      2. Copy WowVisionInstaller.exe into dist\.
      3. Write dist\installer-version.txt: version= and sha256= of THAT file.
      4. Run the self-test's "versionfile" check on it.

  PUBLISH (a new installer version for everyone):
    .\release.ps1 -Publish
      Steps 1-4, then a GitHub release "installer-v<version>" on the installer
      repository carrying BOTH files (plus the bootstrap script) in one
      upload, marked Latest. Installed
      updaters read installer-version.txt from releases/latest/download, so
      they offer the new exe on their next start. Afterwards run
        WowVisionSelfTest\bin\Release\net48\WowVisionSelfTest.exe selfupdate
      which downloads the published exe and verifies it the way users' copies
      will. It prints PASS or FAIL.

  Bump <Version> in WowVisionInstaller\WowVisionInstaller.csproj before
  publishing: an installed updater only replaces itself with a HIGHER version.

  Add -DryRun to see every step without doing it.
#>
param(
    [switch]$BuildOnly,
    [switch]$Publish,
    [string]$Notes,
    [switch]$DryRun
)

# NOT 'Stop': native tools (gh, dotnet) write normal status to stderr, which
# PowerShell 5.1 turns into a fatal error under 'Stop'. We check $LASTEXITCODE
# after every native call instead (see Exec).
$ErrorActionPreference = 'Continue'

$InstallerRepo = 'JeanStiletto/WowVision-Installer'   # keep in step with Config.InstallerRepo
$Root        = $PSScriptRoot
$Csproj      = Join-Path $Root 'WowVisionInstaller\WowVisionInstaller.csproj'
$TestCsproj  = Join-Path $Root 'WowVisionSelfTest\WowVisionSelfTest.csproj'
$ExeBuilt    = Join-Path $Root 'WowVisionInstaller\bin\Release\net48\WowVisionInstaller.exe'
$SelfTestExe = Join-Path $Root 'WowVisionSelfTest\bin\Release\net48\WowVisionSelfTest.exe'
$Dist        = Join-Path $Root 'dist'
$ExeDist     = Join-Path $Dist 'WowVisionInstaller.exe'
# Published beside the exe on every installer release, and read by SelfUpdater
# through the rolling releases/latest/download URL. WITHOUT the hash the
# installer refuses to self-update at all (it will not run an unverified exe),
# so the two files are always published together.
$VersionFile = Join-Path $Dist 'installer-version.txt'
# The one-line PowerShell starter (downloads the exe, checks the hash, runs it).
$Bootstrap   = Join-Path $Root 'bootstrap\Install-WowVisionUpdater.ps1'

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Dry ($m) { Write-Host "  [dry-run] $m" -ForegroundColor Yellow }

function Exec {
    param([string]$What, [scriptblock]$Do)
    if ($DryRun) { Dry $What; return }
    Info "  $What"
    & $Do
    if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE): $What" }
}

# The version as the installer itself formats it (AppVersion.Number): trailing
# zero components dropped, never below major.minor.
function Get-InstallerVersion {
    if (-not (Test-Path $ExeDist)) { return $null }
    $fv = (Get-Item $ExeDist).VersionInfo.FileVersion    # e.g. "1.0.0.0"
    if (-not $fv) { return $null }
    $parts = @($fv.Split('.'))
    $last = $parts.Count - 1
    while ($last -gt 1 -and $parts[$last] -eq '0') { $last-- }
    return ($parts[0..$last] -join '.')
}

function Build {
    Exec "dotnet build installer (Release)" { dotnet build $Csproj -c Release -nologo -clp:NoSummary }
    Exec "dotnet build self-test (Release)" { dotnet build $TestCsproj -c Release -nologo -clp:NoSummary }
    if ($DryRun) { Dry "copy the exe to $ExeDist"; return }
    if (-not (Test-Path $ExeBuilt)) { throw "Built exe missing: $ExeBuilt" }
    New-Item -ItemType Directory -Force $Dist | Out-Null
    Copy-Item $ExeBuilt $ExeDist -Force -ErrorAction Stop
    Info "  -> $ExeDist"
}

# Both values are taken from the FILE in dist, never from the csproj text - it
# is the file that gets uploaded and the file the hash must match.
function Write-VersionFile {
    if ($DryRun) { Dry "write $VersionFile (version + sha256 of the built exe)"; return }
    $ver = Get-InstallerVersion
    if (-not $ver) { throw "Could not read the installer version from $ExeDist." }
    $hash = (Get-FileHash $ExeDist -Algorithm SHA256).Hash.ToLower()
    # No BOM, LF only: the parser tolerates both, but there is no reason to test it.
    [System.IO.File]::WriteAllText($VersionFile, "version=$ver`nsha256=$hash`n", (New-Object System.Text.UTF8Encoding($false)))
    Info "  installer-version.txt: version=$ver sha256=$($hash.Substring(0,12))..."
}

function Check-VersionFile {
    Exec "self-test: versionfile" { & $SelfTestExe versionfile $VersionFile }
}

function Publish-Release {
    $ver = Get-InstallerVersion
    if ($DryRun -and -not $ver) { $ver = '<version>' }
    $tag = "installer-v$ver"
    if (-not $DryRun) {
        & gh release view $tag --repo $InstallerRepo *> $null
        if ($LASTEXITCODE -eq 0) { throw "Release $tag already exists. Bump <Version> in the csproj first." }
    }
    $body = $Notes
    if (-not $body) { $body = "WowVision Installer $ver. Download WowVisionInstaller.exe and run it; it finds and installs the newest WowVision release by itself." }
    # Both files in ONE call, so the exe and the checksum that describes it can
    # never land separately.
    Exec "gh release create $tag (exe + installer-version.txt + bootstrap, Latest)" {
        gh release create $tag $ExeDist $VersionFile $Bootstrap --repo $InstallerRepo --title "WowVision Installer $ver" --notes $body --latest
    }
    Info "  Done. Now run: $SelfTestExe selfupdate"
}

if ($DryRun) { Write-Host "DRY RUN - nothing is built, written or published." -ForegroundColor Yellow }

if ($Publish)       { Build; Write-VersionFile; Check-VersionFile; Publish-Release }
elseif ($BuildOnly) { Build; Write-VersionFile; Check-VersionFile }
else {
    Write-Host "Pick a mode:" -ForegroundColor Yellow
    Write-Host "  -BuildOnly    build the exe and installer-version.txt into dist\ (nothing published)"
    Write-Host "  -Publish      build, then publish both on a new installer release (Latest)"
    Write-Host "  add -DryRun to preview either."
}
