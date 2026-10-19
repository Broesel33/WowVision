# WowVision Installer & Updater

A screen-reader-accessible Windows installer and updater for the WowVision
World of Warcraft addon. It is the Sku installer (Sku-TBC `installer/`, version
5.5) taken over for WowVision: WowVision is one zip on one GitHub release, with
no companion addons. The WoW Login Tool and the extra addons are taken over
from Sku as they are.

## What it does

1. Finds every supported WoW client on the PC (or lets the user browse to it).
2. Asks GitHub for the newest WowVision release and compares it with what each
   client has.
3. Downloads the release zip once, unpacks it once, and copies its folders into
   every selected client.
4. Keeps the TOC each client reads in step with that client's build, so a
   client patch does not stop WowVision from loading.
5. Sets the two game settings that otherwise block a blind player.
6. Installs and updates the extra addons (Questie, AtlasLoot Continued,
   Details, Pawn, Deadly Boss Mods, GTFO, BugSack with BugGrabber), each client
   getting the build that exists for it.
7. Installs the WoW Login Tool for the clients it supports.
8. Optionally installs the NVDA voice bridge and makes all Windows voices
   available to the game.
9. Puts a copy of itself in `%LOCALAPPDATA%\WowVisionUpdater` with a desktop and
   Start menu shortcut "WowVision Updater". Run later, that copy is the updater:
   it first updates itself, then WowVision.

Everything is spoken: every page announces itself, progress is announced at
milestones and every 10 seconds during the download, and the event log can be
read back line by line.

## The clients

Offered in this order. For each: the folder, the TOC it reads, the interface
numbers that belong to it.

- WoW Forever: `_classic_beta_`, `WowVision_Camelot.toc`, 16000 to 19999.
- Anniversary (TBC): `_anniversary_`, `WowVision_TBC.toc`, 20000 to 29999.
- Classic Era (Vanilla): `_classic_era_`, `WowVision_Vanilla.toc`, 10000 to 15999.
- Mists of Pandaria Classic: `_classic_`, `WowVision_Mists.toc`, 50000 to 59999.
- Retail: `_retail_`, `WowVision_Standard.toc` (or `_Mainline`), 100000 and up.

All of it lives in one table, `WowLocator.Clients`. Adding a client is one entry
there plus its texts.

## The WoW Login Tool

Taken over unchanged from the Sku installer, downloaded from the Sku
repository's rolling `login-tool` release (`Config.LoginToolRepo`,
`Config.LoginToolVersion` 4.0 — keep in step with Sku's). Per client, from the
tool's own game types (`data\gametypes.ini` and `GametypeFromVersion` in the
tool):

- WoW Forever: the tool only. The client narrates its own login screens; no
  textures or fonts are copied.
- Anniversary and Classic Era: the tool plus its recognition textures and the
  readable-font override in that client's folder.
- Mists Classic: not installed. The tool has no screen data for 5.x and
  announces it as unsupported.
- Retail: not installed.

The table is the `LoginTool` column of `WowLocator.Clients`.

## Extra addons

Sku's list, with the same packages, pins and checks (SHA-256 for CurseForge
pins, zip shape, symlink guard, obsolete AtlasLoot folders removed, choices
kept in `%LOCALAPPDATA%\WowVisionUpdater\WowVisionManagedAddons.txt`, Pawn off
by default). What is new is the check per game version. Each package names the
clients it exists for, taken from the real zips on 2026-10-19:

- Questie: every client except Retail.
- AtlasLoot Continued: WoW Forever, Anniversary, Classic Era (no Mists or
  Retail TOC).
- Details, GTFO, BugSack with BugGrabber: all five.
- Deadly Boss Mods: core and dungeons for all five; raid mods per era (BC for
  Anniversary, Vanilla for Era and Forever, the new DBM-MoP package for Mists;
  Retail's raids are in the core zip).
- Pawn: one zip per client; new are the Pandaria zip for Mists and the plain
  zip for Retail.

On the components page each addon says which of the chosen game versions it is
not available for. At install time a second check looks into the downloaded
zip: if none of its folders has a TOC that client loads, it is not installed
there and the next run does not download it again. The opening screen names
the extra addons "Update now" would update or install, per client.

## Where things come from

- The addon: `wow-vision/WowVision`, the maintainers' repository. The newest
  release is found from the redirect of `github.com/wow-vision/WowVision/releases/latest`
  (the website, not `api.github.com`, which allows only 60 calls an hour per IP
  and locked Sku users out). The zip's name is read from the `release.json`
  the packager puts beside it; if that fails, the naming `WowVision-<tag>.zip`
  is used. The pre-release "beta" never carries the Latest badge, so it is
  never offered.
- The installer: its own repository, `JeanStiletto/WowVision-Installer`
  (`Config.InstallerRepo`, still to be created). Its newest release carries
  `WowVisionInstaller.exe`, `installer-version.txt` (version and SHA-256 of the
  exe) and the bootstrap script. Installed updaters read the version file from
  `releases/latest/download` and only run a downloaded exe whose hash matches.
- `Config.FallbackTag` (V0.9.0) is used when GitHub cannot be reached. A newer
  live tag always wins; an older one never does.

## Rules worth knowing

- Every top-level folder of the zip is a candidate. V0.9.0 has only
  `WowVision`; the next release (and the "beta" today) also carries
  `WowVision_MapData_TBC`. That map data lives in the WowVision repository as a
  submodule, but the packager moves it out into an addon folder of its own
  (`.pkgmeta` move-folders), so it is still a separate addon in AddOns. The
  `WowVision` folder goes into every client; any other folder only into the
  clients its TOC is written for: the map data ("## Interface: 20506, 16001")
  into Anniversary and WoW Forever. A zip without a `WowVision` folder is
  refused.
- The download happens before the "close the game" question. The game has to
  be closed only for a first install into a client and for the settings
  writes. An update of an installed WowVision is copied live, file by file; a
  locked file is skipped and retried on the next run.
- TOC sync (`TocSync`): only the TOC the client reads is touched, and in it only
  the entries of that client's own family are replaced by the client's build.
  Entries for other clients stay, and a plain TOC with no entry for this client
  is left alone. A TOC that already names the build is never touched. The
  V0.9.0 zip needs this today: its Vanilla TOC says 11508, Classic Era runs 11509.
- A symlinked or junctioned folder (the WowVision dev setup) is never written
  to and counts as current.
- A test build (TOC version "beta", or anything that is not a release number)
  is never replaced unasked. "Reinstall everything" replaces it.
- Versions compare number by number after the V: 0.10.0 is newer than 0.9.0.
  The installer never downgrades.

## Game settings

Set on every run, only with the game closed (the client rewrites these files on
exit):

- `checkAddonVersion 0` in `WTF\Config.wtf`: "Load out of date AddOns".
- `AllowDangerousScripts 1` in each account's `config-cache.wtf`: no
  "run this script?" popup.

## Left out on purpose

- Companion addons and language packs: WowVision has none, and its sounds are
  inside the one zip.
- The macOS installer. The Sku one is Objective-C built on a Mac; it can follow
  once there is a Mac to build and test on.
- An in-game "a newer version exists" notice: that would be addon code in
  WowVision itself, not part of the installer.

## The NVDA voice bridge

`payload\sapi2sr-payload.zip` is byte for byte the bridge the Sku installer
ships. Both installers write the same `Program Files\SAPI2SR` folders and
register the same voice, so they never disagree as long as the payloads stay
identical. Its signing script keeps its Sku name because it sits inside that
shared payload.

## Footprint and removal

There is no uninstaller, because there is nothing to uninstall beyond files:

- the addon folders under each client's `Interface\AddOns`,
- `WowVisionInstall.json` in each AddOns folder (which release each folder came from),
- the two setting lines in `Config.wtf` and `config-cache.wtf`,
- `%LOCALAPPDATA%\WowVisionUpdater` (the updater copy and `WowVisionPaths.txt`,
  the remembered game folders, mirrored in `%ProgramData%\WowVisionUpdater`),
- the "WowVision Updater" shortcuts,
- the extra addons' folders and `WowVisionManagedAddons.txt`,
- the `WoW Login Tool` folder at the WoW base, its shortcuts, and for
  Anniversary and Era its textures in `Interface` and four fonts in `Fonts`,
- if chosen: the SAPI2SR folders and voice, and the copied Windows voices (with
  a registry backup in `%ProgramData%\WowVision`).

`WowVisionPaths.txt` is plain text, one `product=path` line per client. Deleting
a line makes the installer detect that client again.

## Build

```
dotnet build WowVisionInstaller\WowVisionInstaller.csproj
dotnet build WowVisionSelfTest\WowVisionSelfTest.csproj
```

.NET Framework 4.8 WinForms; any recent .NET SDK builds it.

## Test without the windows

`WowVisionSelfTest\bin\Debug\net48\WowVisionSelfTest.exe <command>` prints
PASS and FAIL lines and sets the exit code. Without a command it lists them.

- `offline`: every network-free test in one run (the next eight).
- `clienttest`: a throwaway World of Warcraft folder with all five clients plus
  a PTR: detection, the TOC each client reads, TOC drift, folder picking, game
  settings, status lines, a developer junction.
- `toctest`: build number to interface number, the TOC rewrite rule, BOM and
  CRLF kept.
- `versiontest`: version order, test builds, what needs the release.
- `pathmemory`: remembered folders, against a throwaway store.
- `loc`: English, German and French have the same keys and placeholders, and
  every key the code uses exists.
- `logtest`: the log bundle from the throwaway folder.
- `availability`: who gets the map data, the login tool and each extra addon.
- `texturesweep`: the login tool's stale-texture cleanup.
- `managedinstall [product]`: every extra addon of one client, REAL downloads,
  into a throwaway folder, then a second run that must find nothing to do.
- `logintool [product]`: the REAL login tool into a throwaway client: folder,
  marker, textures only where needed. No shortcut is created.
- `resolve`: the newest WowVision release online, no download.
- `fullinstall`: the REAL release downloaded once and installed into all five
  throwaway clients, then a second run that must find nothing to do.
- `selfupdate`, `selfupdateproof`: the published installer and its hash check
  (need the installer repository to exist).
- `versionfile`: `dist\installer-version.txt` parsed as the installer would.
- `swaptest`: a running exe can be renamed aside and replaced.
- `flavors`: the clients on this PC, read only.

None of them touches the real game folders, the real remembered folders, the
voice registry, the desktop or Downloads. (`managedinstall` reads, never
writes, the real extra-addon choices.)

## Release

`release.ps1 -BuildOnly` builds the Release exe and `dist\installer-version.txt`
and checks the pair. `release.ps1 -Publish` does the same and then creates the
release `installer-v<version>` on the installer repository with the exe, the
version file and the bootstrap script, marked Latest. Bump `<Version>` in the
csproj first. Afterwards run `WowVisionSelfTest.exe selfupdate`. Add `-DryRun`
to see the steps without doing them.

## Files

- `WowVisionInstaller\`: the installer.
  - `Config.cs`: repositories, release pin, file names.
  - `WowLocator.cs`: the client table, detection, TOC files, client builds.
  - `GitHubClient.cs`: latest-release redirect, release.json, downloads.
  - `ReleasePackage.cs`: the release zip, downloaded and unpacked once per run.
  - `AddonInstaller.cs`: what needs the release, copying folders, version order.
  - `InstallRunner.cs`: plan, download, install, summary across all clients.
  - `InstallTarget.cs`: one client and its status line.
  - `TocSync.cs`, `GameSettings.cs`, `InstallManifest.cs`, `PathMemory.cs`.
  - `ManagedAddons.cs`: the extra addons (list, resolution, install).
  - `LoginToolInstaller.cs`: the WoW Login Tool.
  - `SelfUpdater.cs`, `Shortcut.cs`, `Sapi2SrInstaller.cs`, `WindowsVoicesInstaller.cs`.
  - `LogCollector.cs`, `Logger.cs`, `Loc.cs`, `ScreenReaderAnnouncer.cs`, `AppVersion.cs`.
  - The windows: `UpdatePromptForm`, `SelfUpdatePromptForm`, `VersionSelectForm`,
    `FolderConfirmForm`, `ComponentsForm`, `ProgressForm`, `CompletionForm`,
    `WizardForm`, `CancelConfirm`; the entry point is `Program.cs`.
- `WowVisionSelfTest\`: the headless test harness.
- `bootstrap\Install-WowVisionUpdater.ps1`: download, check and start the exe in one line.
- `release.ps1`: build and publish.
