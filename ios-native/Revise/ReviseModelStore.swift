import Foundation
import MoonshineVoice

/// Finds the on-device model files. PRD section 6: models are bundled in the app and nothing
/// is ever downloaded, so lookup is a plain, instant file check that works in airplane mode.
///
/// Expected layout inside the app bundle (folder reference "Models", built from
/// ios-native/Models by ios-native/fetch-models.sh):
///   Models/stt-small-streaming/   Moonshine Small Streaming English
///   Models/diarization/           Moonshine speaker-ID models
///   Models/llm/*.gguf             (later)
enum ReviseModelStore {
    /// Small Streaming per the PRD. If you change this, change the folder + fetch script too.
    static let sttArch: ModelArch = .smallStreaming

    private static let sttFolder = "stt-small-streaming"
    private static let diarizationFolder = "diarization"
    private static let llmFolder = "llm"

    /// Every file Moonshine needs in each folder; a half-copied folder must not pass.
    private static let sttFiles = [
        "adapter.ort", "cross_kv.ort", "decoder_kv.ort", "encoder.ort",
        "frontend.model.ort", "frontend.weights.ort", "streaming_config.json", "tokenizer.bin",
    ]
    private static let diarizationFiles = ["segmentation.ort", "embedding.ort"]

    /// Where the speech model is, or nil if it isn't complete.
    static func sttDirectory() -> URL? { directory(sttFolder, requiring: sttFiles) }

    /// Where the speaker-ID models are, or nil if they aren't complete.
    static func diarizationDirectory() -> URL? { directory(diarizationFolder, requiring: diarizationFiles) }

    /// Human-readable list of what is missing, for the error shown in the UI.
    static func missingDescription() -> String {
        var missing: [String] = []
        if sttDirectory() == nil { missing.append("speech model (Models/\(sttFolder))") }
        if diarizationDirectory() == nil { missing.append("speaker model (Models/\(diarizationFolder))") }
        return missing.isEmpty ? "" : "Missing from the app: " + missing.joined(separator: ", ")
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

    private static func directory(_ folder: String, requiring files: [String]) -> URL? {
        guard let dir = bundledRoot()?.appendingPathComponent(folder, isDirectory: true) else {
            return nil
        }
        let fm = FileManager.default
        return files.allSatisfy { fm.fileExists(atPath: dir.appendingPathComponent($0).path) } ? dir : nil
    }
}
