using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace WowVisionInstaller
{
    /// <summary>
    /// Finds the newest WowVision release and streams it down; fetches the small
    /// files the self-updater reads.
    ///
    /// We deliberately do NOT call the api.github.com REST API. That endpoint caps
    /// unauthenticated callers at 60 requests/hour PER source IP, and users behind
    /// shared / CGNAT / VPN addresses get a 403 "rate limit exceeded" on the very
    /// first metadata fetch — before any download has even started. (The Sku
    /// installer learned this the hard way.)
    ///
    /// The newest release tag is discovered from the redirect of
    /// github.com/OWNER/REPO/releases/latest (the website URL, NOT the API — it
    /// 302s to /releases/tag/&lt;tag&gt; and we read the tag out of the final URL).
    /// That's how an old installer exe still finds releases published after it was
    /// built. If the redirect can't be resolved, the build-time pin in
    /// <see cref="Config"/> is the fallback. Every download uses the direct
    /// github.com release-download URL, which is not rate-limited.
    /// </summary>
    public class GitHubClient : IDisposable
    {
        private readonly HttpClient _http;

        public GitHubClient()
        {
            // .NET Framework can default to an old TLS that GitHub rejects.
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }

            _http = new HttpClient();
            _http.DefaultRequestHeaders.Add("User-Agent", "WowVisionInstaller");
            _http.Timeout = TimeSpan.FromMinutes(10); // the addon zip is ~80 MB
        }

        /// <summary>
        /// Startup step (shared by installer and self-test): resolve the newest
        /// release online and adopt it into <see cref="Config"/> when it is NEWER
        /// than the build-time pin. Never adopts an older one — if the "Latest"
        /// badge ever lags, a freshly-pinned exe must not downgrade anyone.
        ///
        /// The zip's name is read from the release's own release.json (written by
        /// the packager) so a change in the packager's naming does not break old
        /// installers; when that file can't be read, the naming convention stands.
        /// </summary>
        public static void ResolveAndAdoptLatestRelease()
        {
            using (var github = new GitHubClient())
            {
                string resolved = github.ResolveLatestTagAsync().GetAwaiter().GetResult();
                if (string.IsNullOrEmpty(resolved))
                {
                    Logger.Info($"Using built-in release pin {Config.LatestTag}.");
                    return;
                }

                if (AddonInstaller.CompareVersions(resolved, Config.LatestTag) <= 0)
                {
                    Logger.Info($"Newest release online: {resolved}; built-in pin {Config.LatestTag} is current.");
                    resolved = Config.LatestTag;
                }
                else
                {
                    Logger.Info($"Newest release online: {resolved} (built-in pin {Config.LatestTag}) — adopting it.");
                }

                string asset = github.ResolveAssetNameAsync(resolved).GetAwaiter().GetResult();
                Config.OverrideLatest(resolved, asset);
                Logger.Info($"Release asset: {Config.AssetName}");
            }
        }

        /// <summary>
        /// Resolve the newest addon release tag (e.g. "V0.9.0") from the
        /// github.com/.../releases/latest redirect. Not an API call, so it can't
        /// rate-limit. Returns null on any failure — offline, timeout, or a
        /// "Latest" tag that doesn't look like a release tag (V&lt;digits&gt;…) —
        /// and the caller falls back to the build-time pin.
        /// </summary>
        public async Task<string> ResolveLatestTagAsync()
        {
            string url = $"https://github.com/{Config.AddonRepo}/releases/latest";
            try
            {
                // Own short timeout: _http.Timeout is sized for the addon download
                // and would leave an offline user staring at a frozen start.
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15)))
                using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token))
                {
                    resp.EnsureSuccessStatusCode();
                    // HttpClient auto-follows the 302; the final request URI is
                    // .../releases/tag/<tag>. ResponseHeadersRead avoids pulling
                    // the HTML release page body.
                    string finalPath = resp.RequestMessage?.RequestUri?.AbsolutePath ?? string.Empty;
                    var m = Regex.Match(finalPath, @"/releases/tag/([vV]\d[\d.]*)$");
                    if (!m.Success)
                    {
                        Logger.Warning($"/releases/latest resolved to '{finalPath}' — not a release tag; using the built-in pin.");
                        return null;
                    }
                    return m.Groups[1].Value;
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not resolve /releases/latest ({ex.Message}); using the built-in pin.");
                return null;
            }
        }

        /// <summary>
        /// The zip named in a release's release.json, or null. The packager writes
        /// that file next to every zip it uploads:
        ///   {"releases":[{"name":"WowVision","version":"V0.9.0","filename":"WowVision-V0.9.0.zip",…}]}
        /// A plain regex is enough for one string field; a missing file (404) or
        /// an unexpected shape returns null and the caller keeps the convention.
        /// </summary>
        public async Task<string> ResolveAssetNameAsync(string tag)
        {
            string json = await DownloadTextAsync(BuildAddonDownloadUrl(tag, "release.json"),
                                                  TimeSpan.FromSeconds(15));
            if (string.IsNullOrEmpty(json)) return null;

            var m = Regex.Match(json, "\"filename\"\\s*:\\s*\"([^\"]+\\.zip)\"");
            if (!m.Success)
            {
                Logger.Warning($"release.json of {tag} names no zip; using {Config.ConventionalAssetName(tag)}.");
                return null;
            }
            return m.Groups[1].Value;
        }

        /// <summary>
        /// The github.com release-download URL for a tagged addon asset, e.g.
        /// https://github.com/wow-vision/WowVision/releases/download/V0.9.0/WowVision-V0.9.0.zip .
        /// It 302-redirects to the storage backend and is NOT the rate-limited
        /// api.github.com host.
        /// </summary>
        public static string BuildAddonDownloadUrl(string tag, string assetName) =>
            $"https://github.com/{Config.AddonRepo}/releases/download/" +
            $"{Uri.EscapeDataString(tag)}/{Uri.EscapeDataString(assetName)}";

        /// <summary>
        /// The ROLLING download URL for an asset on whichever INSTALLER release
        /// currently carries the "Latest" badge, e.g.
        /// https://github.com/JeanStiletto/WowVision-Installer/releases/latest/download/WowVisionInstaller.exe .
        /// <see cref="SelfUpdater"/> uses it so an exe built a year ago still
        /// resolves today's build without knowing any tag.
        /// </summary>
        public static string BuildInstallerDownloadUrl(string assetName) =>
            $"https://github.com/{Config.InstallerRepo}/releases/latest/download/" +
            $"{Uri.EscapeDataString(assetName)}";

        /// <summary>
        /// Fetches a small text asset. Returns null on any failure — a missing
        /// file (404 on a release that predates it) is an ordinary outcome here,
        /// not an error worth stopping for. Own short timeout, like
        /// <see cref="ResolveLatestTagAsync"/>.
        /// </summary>
        public async Task<string> DownloadTextAsync(string url, TimeSpan timeout)
        {
            try
            {
                using (var cts = new CancellationTokenSource(timeout))
                using (var resp = await _http.GetAsync(url, cts.Token))
                {
                    if (!resp.IsSuccessStatusCode)
                    {
                        Logger.Info($"{url} -> HTTP {(int)resp.StatusCode}.");
                        return null;
                    }
                    return await resp.Content.ReadAsStringAsync();
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not fetch {url}: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Streams a release asset to disk, reporting (bytesDone, bytesTotal);
        /// bytesTotal is -1 when the server sends no Content-Length.
        ///
        /// <paramref name="cancel"/> is honoured per 64 KB chunk, which is what
        /// makes the Cancel button on the progress window mean something: a cancel
        /// that only took effect once an 80 MB download had finished would be
        /// indistinguishable from one that did nothing. Cancelling throws
        /// <see cref="OperationCanceledException"/>; the caller is responsible for
        /// clearing up the partial file.
        /// </summary>
        public async Task DownloadFileAsync(string url, string destPath,
                                            Action<long, long> progress = null,
                                            CancellationToken cancel = default(CancellationToken))
        {
            using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel))
            {
                resp.EnsureSuccessStatusCode();
                long total = resp.Content.Headers.ContentLength ?? -1L;

                using (var src = await resp.Content.ReadAsStreamAsync())
                using (var dst = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, true))
                {
                    var buf = new byte[1 << 16];
                    long done = 0;
                    int read;
                    while ((read = await src.ReadAsync(buf, 0, buf.Length, cancel)) > 0)
                    {
                        cancel.ThrowIfCancellationRequested();
                        await dst.WriteAsync(buf, 0, read, cancel);
                        done += read;
                        progress?.Invoke(done, total);
                    }
                }
            }
            Logger.Info($"Downloaded: {Path.GetFileName(destPath)}");
        }

        public void Dispose() => _http?.Dispose();
    }
}
