import Foundation
import MoonshineVoice

/// Finds the on-device model files. PRD section 6: models are local files, and a
/// release build must never download anything.
///
/// Lookup order for each model:
///   1. App bundle:  <App>.app/Models/<folder>   (add a "Models" folder reference to Runner)
///   2. Moonshine's cache: Application Support/MoonshineModels/<key>
///      (this is where the DEBUG-only downloader below puts files)
enum ReviseModelStore {
    /// Small Streaming per the PRD. Switch to `.tinyStreaming` if captions lag on the phone.
    static let sttArch: ModelArch = .smallStreaming

    private static let sttSpec = ModelSpec.stt(language: "en", modelArch: sttArch)
    private static let sttFolder = "stt-small-streaming"
    private static let diarizationFolder = "diarization"
    private static let llmFolder = "llm"

    static func sttDirectory() -> URL? {
        locate(bundleFolder: sttFolder, spec: sttSpec)
    }

    static func diarizationDirectory() -> URL? {
        locate(bundleFolder: diarizationFolder, spec: .diarization)
    }

    /// "Assets are present", not "inference works" (PRD section 7, `llmReady`).
    static func llmAssetPresent() -> Bool {
        guard let dir = bundledRoot()?.appendingPathComponent(llmFolder, isDirectory: true),
            let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return false }
        return names.contains { $0.hasSuffix(".gguf") }
    }

    private static func bundledRoot() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true)
    }

    private static func locate(bundleFolder: String, spec: ModelSpec) -> URL? {
        if let bundled = bundledRoot()?.appendingPathComponent(bundleFolder, isDirectory: true),
            hasFiles(bundled)
        {
            return bundled
        }
        let cached = ModelCache.defaultRoot()
            .appendingPathComponent(ModelCache.key(for: spec), isDirectory: true)
        return hasFiles(cached) ? cached : nil
    }

    /// Crude presence check: a non-empty folder. A half-finished download would pass,
    /// so if captions fail to load, delete the app from the phone and run again.
    private static func hasFiles(_ dir: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return !names.isEmpty
    }

    #if DEBUG
    /// DEVELOPMENT ONLY. Fetches the STT + diarization models once over the internet so
    /// you can test before the files are bundled. Compiled out of Release builds, so the
    /// shipped app contains no download path from this file.
    static func downloadMissingForDevelopment() async throws {
        let downloader = AssetDownloader()
        for spec in [sttSpec, ModelSpec.diarization] {
            let root = try ModelCache.directory(for: spec)
            _ = try await downloader.ensureModelPresent(root: root, spec: spec)
        }
    }
    #endif
}
