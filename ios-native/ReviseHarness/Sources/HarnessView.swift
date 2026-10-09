import SwiftUI

/// One caption row, keyed by segmentId so a partial is replaced in place by its final.
struct CaptionRow: Identifiable {
    let id: String
    var text: String
    var speakerId: Int
    var isFinal: Bool
    var startMs: Int
}

/// Plays the role Flutter will play later: owns a ReviseEngine and reacts to its events.
@MainActor
final class HarnessModel: ObservableObject {
    @Published var rows: [CaptionRow] = []
    @Published var state = "idle"
    @Published var message = ""

    private var engine: ReviseEngine!

    init() {
        // Same contract as the EventChannel: one event map at a time, delivered on main.
        engine = ReviseEngine { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
    }

    private func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "state":
            state = event["state"] as? String ?? "?"
            message = event["message"] as? String ?? ""
        case "caption":
            guard let id = event["segmentId"] as? String else { return }
            let row = CaptionRow(
                id: id,
                text: event["text"] as? String ?? "",
                speakerId: event["speakerId"] as? Int ?? 0,
                isFinal: event["isFinal"] as? Bool ?? false,
                startMs: event["tStartMs"] as? Int ?? 0)
            if let i = rows.firstIndex(where: { $0.id == id }) {
                if rows[i].isFinal { return }   // contract: ignore anything after final
                rows[i] = row
            } else {
                rows.append(row)
            }
        default: break
        }
    }

    func run(_ label: String, _ work: @escaping (ReviseEngine) async throws -> Void) {
        Task {
            do { try await work(engine) } catch let e as ReviseError {
                message = "\(label): \(e.code.rawValue) - \(e.message)"
            } catch { message = "\(label): \(error.localizedDescription)" }
        }
    }

    func initEngine() {
        message = "Loading models (first run downloads them)…"
        Task {
            let r = await engine.initialize()
            message = "init → sttReady=\(r["sttReady"] ?? false) llmReady=\(r["llmReady"] ?? false)"
        }
    }
    func start() { rows = []; run("start") { try await $0.start(language: "en") } }
    func pause() { run("pause") { try await $0.pause() } }
    func resume() { run("resume") { try await $0.resume() } }
    func stop() { run("stop") { try await $0.stop() } }
}

struct HarnessView: View {
    @StateObject private var model = HarnessModel()
    private let colors: [Color] = [.gray, .blue, .orange, .green, .purple]

    var body: some View {
        VStack(spacing: 12) {
            Text("State: \(model.state)").font(.headline)
            if !model.message.isEmpty {
                Text(model.message).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows.sorted { $0.startMs < $1.startMs }) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.speakerId == 0 ? "Unknown" : "Speaker \(row.speakerId)")
                                    .font(.caption.bold())
                                    .foregroundStyle(colors[min(row.speakerId, colors.count - 1)])
                                Text(row.text)
                                    .font(.title3)
                                    .foregroundStyle(row.isFinal ? Color.primary : Color.secondary)
                            }
                            .id(row.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.rows.last?.text) { _, _ in
                    if let last = model.rows.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack {
                Button("Init", action: model.initEngine)
                Button("Start", action: model.start)
                Button("Pause", action: model.pause)
                Button("Resume", action: model.resume)
                Button("Stop", action: model.stop)
            }
            .buttonStyle(.borderedProminent)
            .font(.footnote)
        }
        .padding()
    }
}
