import Foundation

/// Fills a CRM card's `source_segments` by LOOKING UP each value in the transcript instead of
/// asking the model to write segment IDs (which costs about a third of its output tokens and,
/// with a 1.5B model, is often off by one line). A value with no matching line gets no evidence,
/// and Dart's `applyModelOutput` then drops it, which is the PRD's "don't guess" rule.
enum CrmEvidence {
    struct Line {
        let id: String
        let text: String
    }

    /// Reads the "[s-0001] some words" lines between <transcript> tags in the Dart prompt.
    /// Returns [] if the format isn't recognised (callers then fall back to model citations).
    static func parseTranscript(from prompt: String) -> [Line] {
        guard let open = prompt.range(of: "<transcript>"),
            let close = prompt.range(of: "</transcript>", range: open.upperBound..<prompt.endIndex)
        else { return [] }
        var lines: [Line] = []
        for raw in prompt[open.upperBound..<close.lowerBound].split(separator: "\n") {
            guard raw.hasPrefix("["), let end = raw.firstIndex(of: "]") else { continue }
            let id = String(raw[raw.index(after: raw.startIndex)..<end])
            let text = raw[raw.index(after: end)...].trimmingCharacters(in: .whitespaces)
            if !id.isEmpty, !text.isEmpty { lines.append(Line(id: id, text: text)) }
        }
        return lines
    }

    /// Returns the card JSON with `source_segments` rebuilt from `lines`. If the JSON can't be
    /// parsed it is returned unchanged (Dart will then retry, as for any bad output).
    static func attach(to json: String, lines: [Line]) -> String {
        guard var card = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        else { return json }

        var sources: [String: [String]] = [:]
        func cite(_ path: String, _ value: Any?, verbatimOnly: Bool = false) {
            guard let text = value as? String, let ids = find(text, in: lines, verbatimOnly: verbatimOnly) else { return }
            sources[path] = ids
        }
        for key in ["name", "role", "organization", "follow_up", "notes"] {
            cite(key, card[key])
        }
        // An email or phone number must appear word for word; a small model happily invents
        // "client@company.example", and word overlap must never make that look supported.
        cite("contact_mentioned", card["contact_mentioned"], verbatimOnly: true)
        if card["contact_mentioned"] is String, sources["contact_mentioned"] == nil {
            card["contact_mentioned"] = NSNull()      // unsupported contact details are removed outright
        }
        for (i, topic) in ((card["topics"] as? [Any]) ?? []).enumerated() {
            cite("topics[\(i)]", topic)
        }
        for (i, item) in ((card["commitments"] as? [Any]) ?? []).enumerated() {
            guard let commitment = item as? [String: Any] else { continue }
            cite("commitments[\(i)].what", commitment["what"])
            cite("commitments[\(i)].due", commitment["due"])
        }
        card["source_segments"] = sources
        guard let data = try? JSONSerialization.data(withJSONObject: card, options: [.withoutEscapingSlashes]),
            let text = String(data: data, encoding: .utf8)
        else { return json }
        return text
    }

    // MARK: - Matching

    private static let stopwords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "in", "on", "at", "for", "by", "is", "are", "i", "we",
        "my", "me", "it", "that", "this", "with", "will", "be", "so", "you", "your", "our", "us",
    ]

    /// Ids of the lines that state `value`: lines containing it verbatim, else (unless
    /// `verbatimOnly`) the best line that contains at least 60% of its meaningful words.
    /// nil if nothing matches.
    static func find(_ value: String, in lines: [Line], verbatimOnly: Bool = false) -> [String]? {
        let wanted = normalize(value)
        guard !wanted.isEmpty else { return nil }
        let verbatim = lines.filter { normalize($0.text).contains(wanted) }.prefix(2).map(\.id)
        if !verbatim.isEmpty { return Array(verbatim) }
        if verbatimOnly { return nil }

        let words = wanted.split(separator: " ").map(String.init).filter { !stopwords.contains($0) }
        guard !words.isEmpty else { return nil }
        var best: (id: String, ratio: Double)?
        for line in lines {
            let lineWords = Set(normalize(line.text).split(separator: " ").map(String.init))
            // A word matches if the line has it exactly or shares a 4+ letter stem ("deadline"/"deadlines").
            let hits = words.filter { word in
                lineWords.contains(word)
                    || (word.count >= 4 && lineWords.contains { $0.hasPrefix(String(word.prefix(4))) })
            }.count
            let ratio = Double(hits) / Double(words.count)
            if ratio > (best?.ratio ?? 0) { best = (line.id, ratio) }
        }
        if let best, best.ratio >= 0.6 { return [best.id] }
        return nil
    }

    /// Lowercase, keep letters, digits, @ and . inside words, collapse everything else to spaces.
    private static func normalize(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._"))
        let cleaned = text.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }   // "friday." -> "friday"
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
