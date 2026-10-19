namespace WowVisionInstaller
{
    /// <summary>
    /// Build-time constants. Update here when the release topology changes.
    /// See README.md "Where things come from".
    ///
    /// WowVision ships as ONE zip on the newest GitHub release of the addon repo
    /// (packaged by the BigWigs packager from a V* tag). There are no companion
    /// downloads: everything the addon needs is inside that zip. The zip may hold
    /// more than one addon folder — upstream's .pkgmeta moves the TBC map data
    /// out into its own WowVision_MapData_TBC folder — and every top-level folder
    /// of the zip is installed side by side (<see cref="ReleasePackage"/>).
    /// </summary>
    public static class Config
    {
        public const string DisplayName = "WowVision";

        // ── where the ADDON comes from ──────────────────────────────────────
        // The maintainers' repository. Its releases are made by a GitHub Action
        // from a V* tag: tag "V0.9.0", asset "WowVision-V0.9.0.zip", plus a
        // release.json the packager writes beside it (which names the zip).
        public const string AddonRepo = "wow-vision/WowVision";

        // ── where the INSTALLER comes from ──────────────────────────────────
        // A repository of its own, so an installer fix ships without waiting for
        // an addon release and the addon maintainers never have to handle the
        // exe. Its newest release carries InstallerExeName + installer-version.txt
        // (release.ps1 publishes both in one call).
        public const string InstallerRepo = "JeanStiletto/WowVision-Installer";
        public const string InstallerExeName = "WowVisionInstaller.exe";

        public const string SiteUrl = "https://github.com/" + InstallerRepo;

        // ── ADDON VERSION: live "Latest" redirect, this pin as fallback ─────
        // At startup the installer resolves the newest release tag from the
        // github.com/.../releases/latest redirect (the website URL, not the
        // rate-limited api.github.com), so an OLD installer exe still finds
        // releases published after it was built. FallbackTag is what it uses
        // when the redirect can't be resolved (offline, GitHub outage). Bump it
        // when convenient; a live tag is only adopted when it is NEWER than the
        // pin, so a fresh exe never downgrades anyone.
        //
        // RELEASE RULE this depends on: the newest addon release carries
        // GitHub's "Latest" badge. Upstream's "beta" pre-release never does, so
        // the installer always offers the stable release.
        public const string FallbackTag = "V0.9.0";

        /// <summary>The release tag the installer works with, e.g. "V0.9.0".</summary>
        public static string LatestTag { get; private set; } = FallbackTag;

        /// <summary>The tag without its V, e.g. "0.9.0" — what the user is told.</summary>
        public static string LatestVersion => LatestTag.TrimStart('v', 'V');

        /// <summary>
        /// The zip on that release. The packager's naming is "WowVision-&lt;tag&gt;.zip";
        /// the release's own release.json, when it can be read, overrides it
        /// (<see cref="GitHubClient.ResolveAndAdoptLatestRelease"/>).
        /// </summary>
        public static string AssetName { get; private set; } = ConventionalAssetName(FallbackTag);

        public static string ConventionalAssetName(string tag) => "WowVision-" + tag + ".zip";

        /// <summary>Adopt a live-resolved release (tag plus, when known, its zip name).</summary>
        public static void OverrideLatest(string tag, string assetName = null)
        {
            LatestTag = tag;
            AssetName = string.IsNullOrEmpty(assetName) ? ConventionalAssetName(tag) : assetName;
        }

        /// <summary>
        /// The addon folder that carries the version and decides "is there an
        /// update". The other folders of the zip follow it.
        /// </summary>
        public const string PrimaryFolder = "WowVision";

        /// <summary>Manifest filename written into the AddOns folder.</summary>
        public const string ManifestFileName = "WowVisionInstall.json";

        // ── the WoW Login Tool ──────────────────────────────────────────────
        // A standalone tool (originally by Yennister/Duugu, reworked with an
        // AutoHotkey v2 + OCR driver) that gives the login, server and character
        // screens an audio menu. It is NOT a WoW addon: it installs as its own
        // program folder next to the game, plus login-screen recognition textures
        // in the client's Interface folder and a readable-font override. Which
        // clients get it, and how, is WowLocator.Clients' LoginTool column.
        //
        // It ships from the Sku repository on a PERMANENT rolling tag: each new
        // build re-uploads WoW-Login-Tool.zip to the same 'login-tool' tag, so the
        // URL never changes. LoginToolVersion is the freshness signal instead:
        // keep it in step with the Sku installer's Config.LoginToolVersion, and
        // LoginToolInstaller upgrades every install whose marker predates it.
        public const string LoginToolRepo = "Sku75/Sku-WoW-Addon-TBC";
        public const string LoginToolTag = "login-tool";
        public const string LoginToolVersion = "4.0";
        public const string LoginToolAsset = "WoW-Login-Tool.zip";
        public const string LoginToolFolderName = "WoW Login Tool";

        // ── the game clients (see WowLocator.Clients for the full table) ────
        public const string EraFlavor = "wow_classic_era";
        public const string AnniversaryFlavor = "wow_anniversary";
        public const string MistsFlavor = "wow_classic";
        public const string RetailFlavor = "wow";
        public const string ForeverFlavor = "wow_classic_beta";

        /// <summary>
        /// Every game process this installer cares about: the classic clients run
        /// WowClassic.exe, retail Wow.exe, WoW Forever WowB.exe.
        /// </summary>
        public static readonly string[] GameProcessNames = { "WowClassic", "Wow", "WowB" };
    }
}
