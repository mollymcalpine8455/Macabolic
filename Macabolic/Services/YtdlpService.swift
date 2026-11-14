import Combine
import CryptoKit
import Foundation

@MainActor
class YtdlpService: ObservableObject {
    @Published private(set) var version: String?
    @Published private(set) var isUpdating = false
    @Published private(set) var updateError: String?

    private var ytdlpPath: URL?
    private var ffmpegDirectory: URL?
    private var setupTask: Task<Void, Never>?
    private var runtimeSetupTask: Task<Void, Error>?
    private let minimumVersion = "2025.11.12" // First stable release with EJS support
    private let progressPrefix = "MACABOLIC_PROGRESS:"
    private let filepathPrefix = "MACABOLIC_FILE:"

    private let appSupport: URL

    init(appSupport: URL? = nil) {
        self.appSupport = appSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Macabolic")
    }

    private var searchDirectories: [String] {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return ["/opt/homebrew/bin", "/usr/local/bin"]
            + inherited.split(separator: ":").map(String.init)
    }

    private var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([appSupport.path] + searchDirectories + ["/usr/bin", "/bin"]).joined(separator: ":")
        return environment
    }

    func setupBinaries() async {
        if setupTask == nil {
            setupTask = Task {
                await findYtdlp()
                await findFfmpeg()
            }
        }
        await setupTask?.value
    }

    private func findYtdlp() async {
        if ytdlpPath != nil { return }
        let managed = appSupport.appendingPathComponent("yt-dlp")
        let installed = searchDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent("yt-dlp") }
        let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil)
        let candidates = [managed] + installed + [bundled].compactMap { $0 }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            guard let foundVersion = try? await readVersion(at: candidate),
                  foundVersion.compare(minimumVersion, options: .numeric) != .orderedAscending else { continue }
            // An explicit update may have finished while the candidate was being checked.
            if ytdlpPath == nil {
                ytdlpPath = candidate
                version = foundVersion
            }
            return
        }

        if ytdlpPath == nil {
            await updateYtdlp()
        }
    }

    func updateYtdlp() async {
        guard !isUpdating else { return }
        isUpdating = true
        updateError = nil
        defer { isUpdating = false }

        let source = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let destination = appSupport.appendingPathComponent("yt-dlp")
        let staging = appSupport.appendingPathComponent(".yt-dlp-" + UUID().uuidString)
        let files = FileManager.default
        defer { try? files.removeItem(at: staging) }

        do {
            try files.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let downloaded = try await downloadAsset(from: source)
            defer { try? files.removeItem(at: downloaded) }
            try files.moveItem(at: downloaded, to: staging)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
            let foundVersion = try await readVersion(at: staging)
            guard foundVersion.compare(minimumVersion, options: .numeric) != .orderedAscending else {
                throw YtdlpError.commandFailed("yt-dlp \(foundVersion) does not support YouTube EJS.")
            }

            // Both paths are in the same directory. A failed update leaves the working binary in place.
            guard rename(staging.path, destination.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            ytdlpPath = destination
            version = foundVersion
        } catch {
            updateError = error.localizedDescription
        }
    }

    private func readVersion(at path: URL) async throws -> String {
        let result = try await runCommand(
            executable: path, arguments: ["--ignore-config", "--version"]
        )
        let version = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: #"^\d{4}\.\d{2}\.\d{2}(?:[.\w+-]+)?$"#, options: .regularExpression) != nil else {
            throw YtdlpError.commandFailed("Could not read the yt-dlp version.")
        }
        return version
    }

    private func findFfmpeg() async {
        let files = FileManager.default
        let directories = searchDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) } + [appSupport]
        if let installed = directories.first(where: { directory in
            ["ffmpeg", "ffprobe"].allSatisfy {
                files.isExecutableFile(atPath: directory.appendingPathComponent($0).path)
            }
        }) {
            ffmpegDirectory = installed
            return
        }

        do {
            try files.createDirectory(at: appSupport, withIntermediateDirectories: true)
            for name in ["ffmpeg", "ffprobe"] {
                guard !files.isExecutableFile(atPath: appSupport.appendingPathComponent(name).path) else { continue }
                let suffix = name == "ffmpeg" ? "zip" : "ffprobe/zip"
                let source = URL(string: "https://evermeet.cx/ffmpeg/get/" + suffix)!
                let archive = try await downloadAsset(from: source)
                defer { try? files.removeItem(at: archive) }
                _ = try await runCommand(
                    executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                    arguments: ["-o", archive.path, name, "-d", appSupport.path]
                )
                try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appSupport.appendingPathComponent(name).path)
            }
            ffmpegDirectory = appSupport
        } catch {
            print("FFmpeg setup failed: \(error.localizedDescription)")
        }
    }

    private func prepareYouTubeRuntime(for url: String) async throws {
        guard let host = URL(string: url)?.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
                || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") else { return }

        if runtimeSetupTask == nil {
            runtimeSetupTask = Task {
                let directories = [appSupport.path] + searchDirectories
                let runtimes = [("deno", "2.3.0"), ("node", "22.0.0"), ("qjs", "")]
                for (runtime, minimum) in runtimes {
                    for directory in directories {
                        let path = URL(fileURLWithPath: directory).appendingPathComponent(runtime)
                        guard FileManager.default.isExecutableFile(atPath: path.path) else { continue }
                        if runtime == "qjs" { return }
                        if let output = try? await runCommand(executable: path, arguments: ["--version"]),
                           let range = output.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression),
                           output[range].compare(minimum, options: .numeric) != .orderedAscending {
                            return
                        }
                    }
                }
                try await installDeno()
            }
        }

        do {
            try await runtimeSetupTask?.value
        } catch {
            runtimeSetupTask = nil
            throw YtdlpError.runtimeSetupFailed(error.localizedDescription)
        }
    }

    private func installDeno() async throws {
        // Checksums from the official Deno v2.9.8 release.
        #if arch(arm64)
        let architecture = "aarch64"
        let checksum = "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e"
        #else
        let architecture = "x86_64"
        let checksum = "4b2f5edd2639b7470f034238b321d7002d8dfb4726d8558f52c17afac370eb2c"
        #endif
        let source = URL(string: "https://github.com/denoland/deno/releases/download/v2.9.8/deno-\(architecture)-apple-darwin.zip")!
        let archive = try await downloadAsset(from: source)
        let staging = appSupport.appendingPathComponent(".deno-" + UUID().uuidString, isDirectory: true)
        let files = FileManager.default
        defer {
            try? files.removeItem(at: archive)
            try? files.removeItem(at: staging)
        }
        let digest = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == checksum else {
            throw YtdlpError.commandFailed("The Deno archive failed its SHA-256 check.")
        }
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = try await runCommand(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                 arguments: ["-o", archive.path, "deno", "-d", staging.path])
        let extracted = staging.appendingPathComponent("deno")
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: extracted.path)
        _ = try await runCommand(executable: extracted, arguments: ["--version"])
        guard rename(extracted.path, appSupport.appendingPathComponent("deno").path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func downloadAsset(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (file, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: file)
            throw YtdlpError.commandFailed("Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return file
    }

    func fetchInfo(url: String) async throws -> MediaInfo {
        let output = try await fetchMetadata(url: url, args: ["--dump-single-json", "--no-playlist"])
        return try JSONDecoder().decode(MediaInfo.self, from: Data(output.utf8))
    }

    func fetchPlaylistInfo(url: String) async throws -> [MediaInfo] {
        let output = try await fetchMetadata(url: url, args: ["--dump-json", "--yes-playlist"])
        let decoder = JSONDecoder()
        let entries = output.split(separator: "\n").compactMap { line in
            try? decoder.decode(MediaInfo.self, from: Data(line.utf8))
        }.filter { $0.downloadURL != nil }
        guard !entries.isEmpty else { throw YtdlpError.noPlaylistEntries }
        return entries
    }

    private func fetchMetadata(url: String, args: [String]) async throws -> String {
        await setupBinaries()
        guard let path = ytdlpPath else { throw YtdlpError.notFound(updateError) }
        try await prepareYouTubeRuntime(for: url)
        return try await runCommand(
            executable: path,
            arguments: commonArguments() + ["--simulate", "--flat-playlist", "--ignore-no-formats-error"]
                + args + ["--", url]
        )
    }

    private func commonArguments() -> [String] {
        var args = ["--ignore-config", "--color", "never", "--js-runtimes", "node", "--js-runtimes", "quickjs"]
        if let ffmpegDirectory = ffmpegDirectory {
            args += ["--ffmpeg-location", ffmpegDirectory.path]
        }
        let browser = UserDefaults.standard.string(forKey: "browserForCookies") ?? "none"
        if browser != "none" {
            args += ["--cookies-from-browser", browser]
        }
        return args
    }

    func download(
        url: String,
        options: DownloadOptions,
        onProcessCreated: @escaping (Process) -> Void,
        onProgress: @escaping (Double, String?, String?) -> Void,
        onOutput: @escaping (String) -> Void
    ) async throws -> URL {
        await setupBinaries()
        guard let path = ytdlpPath else { throw YtdlpError.notFound(updateError) }
        try await prepareYouTubeRuntime(for: url)

        var args = commonArguments() + ["--no-playlist"]
        let outputTemplate: String
        if let filename = options.customFilename, !filename.isEmpty {
            let escaped = filename.replacingOccurrences(of: "%", with: "%%")
                .replacingOccurrences(of: "/", with: "／")
                .replacingOccurrences(of: ":", with: "：")
            outputTemplate = "\(escaped).%(ext)s"
        } else {
            outputTemplate = "%(title)s.%(ext)s"
        }
        args += ["-o", outputTemplate] + buildFormatArgs(options: options)

        if options.downloadSubtitles && !options.subtitleLanguages.isEmpty {
            var subFormat = options.subtitleFormat?.ytdlpValue ?? "srt"
            if options.embedSubtitles && options.fileType == .webm {
                subFormat = "vtt"
            }
            let languages = options.subtitleLanguages.sorted()
                .map { "^" + NSRegularExpression.escapedPattern(for: $0) + "$" }
                .joined(separator: ",")
            args += ["--sub-format", "\(subFormat)/best", "--sub-langs", languages,
                     "--write-subs", "--write-auto-subs", "--convert-subs", subFormat]
            if options.embedSubtitles && options.fileType.isVideo {
                args += ["--embed-subs", "--compat-options", "no-keep-subs"]
            }
        }

        if options.downloadThumbnail { args.append("--write-thumbnail") }
        if options.embedThumbnail && options.fileType.supportsEmbeddedThumbnail {
            args.append("--embed-thumbnail")
        }

        // Metadata also controls chapter embedding by default, so pass the chapter toggle explicitly.
        if options.embedMetadata { args.append("--embed-metadata") }
        args.append("--embed-chapters")
        if options.splitChapters { args.append("--split-chapters") }
        if options.sponsorBlock { args += ["--sponsorblock-remove", "all"] }
        if let start = options.timeFrameStart, let end = options.timeFrameEnd {
            args += ["--download-sections", "*\(start)-\(end)"]
        }
        if options.forceOverwrite == true { args.append("--force-overwrites") }
        if let additional = options.additionalArguments, !additional.isEmpty {
            args += splitArguments(additional)
        }

        args += ["--no-quiet", "--progress", "--newline",
                 "--progress-template", "download:\(progressPrefix)%(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s",
                 "--print", "after_move:\(filepathPrefix)%(filepath)j", "--", url]

        let command = ([path.path] + args).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        onOutput("[COMMAND] \(command)")

        let result = try await runProcess(executable: path, arguments: args, directory: options.saveFolder,
            onProcessCreated: onProcessCreated,
            onLine: { [progressPrefix, filepathPrefix] line in
                if line.hasPrefix(filepathPrefix) { return }
                onOutput(line)
                guard line.hasPrefix(progressPrefix) else { return }
                let parts = line.dropFirst(progressPrefix.count).split(whereSeparator: \.isWhitespace)
                if let first = parts.first,
                   let percent = Double(first.replacingOccurrences(of: "%", with: "")), percent.isFinite {
                    let speed = parts.count > 1 ? String(parts[1]) : nil
                    let eta = parts.count > 2 ? String(parts[2]) : nil
                    onProgress(min(max(percent / 100, 0), 1), speed, eta)
                }
            })

        guard result.status == 0 else {
            let error = result.error
            if error.contains("HTTP Error 429") || error.contains("Too Many Requests") {
                throw YtdlpError.tooManyRequests
            }
            let lastError = error.split(separator: "\n").last(where: { $0.hasPrefix("ERROR:") })
            if let lastError = lastError, ["subtitle", "caption"].contains(where: lastError.localizedCaseInsensitiveContains) {
                throw YtdlpError.subtitleError(error)
            }
            throw YtdlpError.downloadFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let paths = result.output.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix(filepathPrefix) else { return nil }
            return try? JSONDecoder().decode(String.self, from: Data(line.dropFirst(filepathPrefix.count).utf8))
        }
        if let path = paths.last, !path.isEmpty {
            let file = URL(fileURLWithPath: path, relativeTo: options.saveFolder).absoluteURL
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        throw YtdlpError.noSavedFile
    }

    private func buildFormatArgs(options: DownloadOptions) -> [String] {
        let audioCodec = options.audioCodec?.ytdlpFilter ?? ""
        let target = options.fileType.fileExtension

        guard options.fileType.isVideo else {
            let selector = audioCodec.isEmpty ? "ba/b" : "ba\(audioCodec)/b\(audioCodec)/ba/b"
            return ["-f", selector, "-x", "--audio-format", target,
                    "--audio-quality", options.audioQuality?.ytdlpValue ?? "0"]
        }

        let videoCodec = options.videoCodec?.ytdlpFilter ?? ""
        let resolution = options.videoResolution
        let height = resolution?.maximumHeight.map { "[height<=\($0)]" } ?? ""
        let video = resolution == .worst ? "wv" : "bv"
        let combined = resolution == .worst ? "w" : "b"
        let webmVideo = options.fileType == .webm ? "[vcodec~='^(vp0?[89]|av0?1)']" : ""
        let webmAudio = options.fileType == .webm ? "[acodec~='^(opus|vorbis|vrbs)']" : ""

        var selectors: [String] = []
        func addFormats(height: String, videoCompatibility: String, audioCompatibility: String) {
            let preferences = [(videoCodec, audioCodec), (videoCodec, ""), ("", audioCodec), ("", "")]
            for (v, a) in preferences {
                let videoFilters = height + videoCompatibility + v
                let audioFilters = audioCompatibility + a
                for selector in ["\(video)\(videoFilters)+ba\(audioFilters)",
                                 "\(combined)\(videoFilters)\(audioFilters)"] where !selectors.contains(selector) {
                    selectors.append(selector)
                }
            }
        }

        addFormats(height: height, videoCompatibility: webmVideo, audioCompatibility: webmAudio)
        addFormats(height: height, videoCompatibility: "", audioCompatibility: "")
        if !height.isEmpty {
            addFormats(height: "", videoCompatibility: webmVideo, audioCompatibility: webmAudio)
            addFormats(height: "", videoCompatibility: "", audioCompatibility: "")
        }
        let merge = options.fileType == .mkv ? "mkv" : "\(target)/mkv"
        let conversion = options.fileType == .mkv ? "--remux-video" : "--recode-video"
        var args = ["-f", selectors.joined(separator: "/"), "--merge-output-format", merge, conversion, target]
        if let height = resolution?.maximumHeight {
            args += ["-S", "height:\(height)"]
        }
        return args
    }

    private func runCommand(executable: URL, arguments: [String]) async throws -> String {
        let result = try await runProcess(executable: executable, arguments: arguments)
        guard result.status == 0 else {
            throw YtdlpError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
        return result.output
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        directory: URL? = nil,
        onProcessCreated: ((Process) -> Void)? = nil,
        onLine: (@MainActor (String) -> Void)? = nil
    ) async throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = error
        process.environment = processEnvironment

        try process.run()
        onProcessCreated?(process)

        async let stdout = Self.readPipe(output.fileHandleForReading, onLine: onLine)
        async let stderr = Self.readPipe(error.fileHandleForReading, onLine: onLine)
        let (outputText, errorText) = try await (stdout, stderr)
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
        return (status, outputText, errorText)
    }

    nonisolated private static func readPipe(
        _ handle: FileHandle, onLine: (@MainActor (String) -> Void)?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    var data = Data()
                    var pending = Data()
                    while let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty {
                        data.append(chunk)
                        guard let onLine = onLine else { continue }
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 0x0A) {
                            let line = String(decoding: pending.prefix(upTo: newline), as: UTF8.self)
                            pending.removeSubrange(...newline)
                            DispatchQueue.main.async { onLine(line) }
                        }
                    }
                    if let onLine = onLine, !pending.isEmpty {
                        let line = String(decoding: pending, as: UTF8.self)
                        DispatchQueue.main.async { onLine(line) }
                    }
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func splitArguments(_ input: String) -> [String] {
        var result: [String] = []
        var current: String = ""
        var inQuotes: Bool = false
        var quoteChar: Character? = nil
        
        var iterator = input.makeIterator()
        while let char = iterator.next() {
            if char == "\"" || char == "'" {
                if inQuotes {
                    if char == quoteChar {
                        inQuotes = false
                        quoteChar = nil
                    } else {
                        current.append(char)
                    }
                } else {
                    inQuotes = true
                    quoteChar = char
                }
            } else if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            result.append(current)
        }
        
        return result
    }
}

enum YtdlpError: LocalizedError {
    case notFound(String?)
    case commandFailed(String)
    case downloadFailed(String)
    case tooManyRequests
    case subtitleError(String)
    case noSavedFile
    case noPlaylistEntries
    case runtimeSetupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notFound(let reason):
            return reason.map { "yt-dlp setup failed: \($0)" } ?? "yt-dlp not found. Open Settings → Advanced to update it."
        case .commandFailed(let output):
            return "Command failed: \(output)"
        case .downloadFailed(let output):
            return output.isEmpty ? "Download failed" : output
        case .tooManyRequests:
            return "429: Too Many Requests"
        case .subtitleError(let output):
            return "Subtitle error: \(output)"
        case .noSavedFile:
            return "yt-dlp did not report a saved media file."
        case .noPlaylistEntries:
            return "No downloadable playlist entries."
        case .runtimeSetupFailed(let reason):
            return "Could not set up JavaScript for YouTube. Install Deno or retry. \(reason)"
        }
    }
}
