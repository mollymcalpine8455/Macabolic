# Macabolic 🚀

A macOS video and audio downloader powered by `yt-dlp`. This fork of [alinuxpengui/Macabolic](https://github.com/alinuxpengui/Macabolic) adds Japanese and support for current yt-dlp releases.

**[Download this fork for macOS](https://github.com/mollymcalpine8455/Macabolic/releases)** · **[日本語の使い方](#日本語で使う)**

<div align="center">
  <img src="Macabolic/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" />
  <p>
    <a href="https://mastodon.social/@macabolic_app">
      <img src="https://img.shields.io/badge/Follow-Mastodon-2b90d9?style=for-the-badge&logo=mastodon&logoColor=white" alt="Follow on Mastodon" />
    </a>
    <a href="https://bsky.app/profile/macabolicapp.bsky.social">
      <img src="https://img.shields.io/badge/Follow-Bluesky-0085ff?style=for-the-badge&logo=bluesky&logoColor=white" alt="Follow on Bluesky" />
    </a>
    <a href="https://x.com/macabolic_app">
      <img src="https://img.shields.io/badge/Follow-X-black?style=for-the-badge&logo=x&logoColor=white" alt="Follow on X" />
    </a>
  </p>
</div>

Macabolic is a native macOS frontend for the powerful [yt-dlp](https://github.com/yt-dlp/yt-dlp) command-line tool. It allows you to download videos and audio from YouTube and thousands of other supported sites with ease.

## Screenshots 📸

<div align="center">
  <table>
    <tr>
      <td width="50%"><img src="docs/screenshots/1.png" alt="Main Dashboard - Overview of all downloads" /></td>
      <td width="50%"><img src="docs/screenshots/2.png" alt="Smart Download - Custom settings and options" /></td>
    </tr>
    <tr>
      <td width="50%"><img src="docs/screenshots/3.png" alt="Advanced Preferences - Global application settings" /></td>
      <td width="50%"><img src="docs/screenshots/4.png" alt="Custom Presets - Create and manage your own templates" /></td>
    </tr>
  </table>
</div>

---

## Support the upstream project ❤️

**Note on Sponsorships:**  
Direct financial support via GitHub Sponsors is currently disabled due to local tax and regulatory complexities. While I truly appreciate the generosity of everyone who wanted to contribute, the best way to support Macabolic right now is by **starring the repository**, reporting bugs, or sharing the project with the community. Thank you for understanding! 🙏

### 🏆 The "First 5" Wall of Fame
To show my gratitude, the **first 5 sponsors** of any amount will be **permanently featured** in the "About" section of the Macabolic app. Your name will be part of the app's history forever!

1. [**Iman Montajabi**](https://github.com/ImanMontajabi) 🌟 (Our first ever sponsor!)
2. [**Semmelstulle**](https://github.com/Semmelstulle) 🌟

---

## 日本語で使う

[Releases](https://github.com/mollymcalpine8455/Macabolic/releases) の **Assets** から macOS 用ZIPをダウンロードして展開します。macOS 12以降のIntel Mac、Apple Silicon Macに対応しています。試用版はApple未公証です。

初回起動画面、または **Settings → General → Language** で **日本語** を選択できます。
macOS標準のメニューにも反映するには、アプリを終了してから開き直してください。

## yt-dlp compatibility build

This fork adds Japanese localization and updates the download integration. These changes were made on 2026-11-14 and tested with [yt-dlp 2026.10.26](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26).

- Under **Settings → Advanced**, **Update yt-dlp** downloads the current stable macOS executable from yt-dlp. The update is checked before replacing the previous executable.
- The first YouTube request uses a supported local JavaScript runtime or downloads a verified Deno 2.9.8 archive into Macabolic's Application Support directory. See the [yt-dlp EJS guide](https://github.com/yt-dlp/yt-dlp/wiki/EJS) for details.
- Macabolic checks Homebrew's standard locations for both FFmpeg and FFprobe. Install them with `brew install ffmpeg` if post-processing reports a missing dependency.
- Extra yt-dlp arguments can be entered in the download dialog. The app ignores global yt-dlp configuration files so their format and output settings cannot override the GUI by accident. Pass `--config-locations` in the dialog to use a specific config file for a download.

To build from this source, use Xcode 15 or later:

```sh
xcodebuild -project Macabolic.xcodeproj -scheme Macabolic -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

The app is in `build/Build/Products/Release`. To reproduce the standalone ZIP
with the Xcode Command Line Tools and Python 3, run
`python3 scripts/build-release.py build/Macabolic-macOS.zip`.

Set `MACABOLIC_RELEASE_REPOSITORY=OWNER/REPO` when building in Xcode to use
a repository that publishes DMG updates. This fork distributes its ZIPs
through GitHub Releases.

## Roadmap 🗺️

Here is what I'm planning to bring to Macabolic in the near future:

- [x] ~~**Browser Cookies Support:** Use cookies from your browser to bypass YouTube's bot detection and access age-restricted or private content.~~ ✅ (Completed in v2.2.0)
- [x] ~~**Advanced Codec Default Settings & Presets:** Save and manage custom download presets with preferred codecs, resolutions, and audio quality settings.~~ ✅ (Completed in v2.2.0)
- [x] ~~**Persistent History & Re-download:** Categorized completed/failed downloads that persist across sessions and easy re-downloading.~~ ✅ (Completed in v2.3.0)
- [x] ~~**Notification Support:** Get notified instantly when downloads are finished.~~ ✅ (Completed in v3.0.0)
- [x] ~~**Browser Extensions:** One-click download directly from Chrome and Firefox.~~ ✅ (Completed in v3.0.0)
- [x] ~~**Menu Bar Integration:** Manage ind downloads from your menu bar.~~ ✅ (Completed in v3.0.0)
- [ ] **Official Apple Notarization:** Removing the "Unidentified Developer" warning for a professional experience. (Waiting for the project to reach 1,000+ stars and a larger user base).
- [ ] **Custom Post-Processing:** More tools to trim, convert, and manage your downloaded files.

---

## Features ✨

- **Native macOS Experience:** Built with SwiftUI for a seamless look and feel.
- **Menu Bar App:** Manage your downloads directly from the menu bar. 🆕
- **Browser Extensions:** Start downloads with one click from Chrome and Firefox. 🆕
- **Native Notifications:** Instant updates when downloads are finished. 🆕
- **Vast Site Support:** Downloads from YouTube, Vimeo, Twitter, and [thousands more](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).
- **Multiple Formats:** Support for MP4, WebM, MP3, Opus, FLAC, and WAV.
- **High Quality:** Up to 4K (2160p) resolution support.
- **Smart Features:**
  - Embed subtitles, metadata, and thumbnails into your files.
  - **SponsorBlock** integration to automatically skip sponsors and intros.
  - Playlist downloading support.
  - Concurrent download management.
- **Multi-language:** Supports English, Turkish, and Japanese (selectable in the app).
- **Auto-Update:** Self-manages `yt-dlp` updates to ensure maximum compatibility.

## Upstream installation 🚀

### Option 1: Homebrew (Recommended)

```bash
brew tap alinuxpengui/macabolic
brew install --cask macabolic
xattr -cr /Applications/Macabolic.app
```

### Option 2: Manual Download

- **Download:** Download the latest `Macabolic-v3.0.0.dmg` from the [Releases](https://github.com/alinuxpengui/Macabolic/releases) page.
- **Install:** Open the DMG file and drag **Macabolic** to your `Applications` folder.
- **First Launch:** Since the app is not notarized, you have two options to open it:
  - **Terminal Way:** Run the following command to remove the quarantine flag:
```bash
xattr -cr /Applications/Macabolic.app
```
  - **Other Way:** Right-click the app in your Applications folder and select Open, or go to System Settings > Privacy & Security and click Open Anyway.
- **Initial Setup:** When the app opens, you will be greeted by a **Legal Disclaimer**. Please read and confirm it. Go to **Preferences (⌘,)** to set your **Language** and **Default Save Folder**.

### Option 3: Browser Extensions 🌐

#### Chrome / Brave / Edge:
1. **Download:** [MacabolicExtension_Chrome.zip](https://github.com/alinuxpengui/Macabolic/releases/download/v3.0.0/MacabolicExtension_Chrome.zip) and unzip it.
2. Go to `chrome://extensions/`
3. Enable **"Developer mode"** (top right).
4. Click **"Load unpacked"** and select the unzipped folder.

#### Firefox:
1. **Download:** [MacabolicExtension_Firefox.zip](https://github.com/alinuxpengui/Macabolic/releases/download/v3.0.0/MacabolicExtension_Firefox.zip) and unzip it.
2. Go to `about:debugging#/runtime/this-firefox`
3. Click **"Load Temporary Add-on..."**.
4. Select the `manifest.json` file inside the unzipped folder.

> 💡 **Usage:** Once installed, simply **right-click** on any video link or the page itself on supported sites (like YouTube) and select **"Download with Macabolic"** to start downloading immediately.

---

## Build Requirements 🛠️

- macOS 12.0 or later (Monterey+)
- Xcode 15.0 or later
- Swift 5.9+

## Credits ❤️

- **Parabolic by Nickvision:** This project is a macOS-native port based on the original [Parabolic](https://github.com/NickvisionApps/Parabolic) application.
- **yt-dlp:** The core engine that makes video downloading possible.

## Legal Disclaimer ⚖️

This tool is intended solely for personal use and educational or research purposes.
Videos on YouTube and other sites may be subject to DMCA protection. The authors of Parabolic/Macabolic do not endorse, and are not responsible for, the use of this application in means that will violate these laws.
Downloading videos from YouTube may violate their Terms of Service unless the video has an explicit download button or the content is licensed in a way that permits downloading.
By using this app, you assume full responsibility for any content you download and how you use it. The developer does not condone or support any misuse of this tool to infringe upon copyrights or violate platform rules.

## License ⚖️

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.

---
**Original Macabolic project by [alinuxpengui](https://github.com/alinuxpengui)**

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=alinuxpengui/Macabolic&type=date&legend=top-left)](https://www.star-history.com/#alinuxpengui/Macabolic&type=date&legend=top-left)
