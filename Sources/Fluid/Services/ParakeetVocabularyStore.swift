import Foundation
#if arch(arm64)
import FluidAudio
#endif

/// JSON-backed store for Parakeet vocabulary boosting terms.
/// Persists to Application Support so it survives app updates and can be user-edited.
final class ParakeetVocabularyStore {
    static let shared = ParakeetVocabularyStore()

    struct VocabularyConfig: Codable, Sendable {
        struct Term: Codable, Hashable, Sendable {
            let text: String
            let weight: Float?
            let aliases: [String]?
        }

        let alpha: Float?
        let minCtcScore: Float?
        let minSimilarity: Float?
        let minCombinedConfidence: Float?
        let minTermLength: Int?
        let terms: [Term]
    }

    struct ResolvedConfig: Sendable {
        let alpha: Float
        let minCtcScore: Float
        let minSimilarity: Float
        let minCombinedConfidence: Float
        let minTermLength: Int
        let terms: [VocabularyConfig.Term]
    }

    enum StoreError: LocalizedError {
        case invalidJSON(String)
        case applicationSupportUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let details):
                return "Invalid vocabulary JSON: \(details)"
            case .applicationSupportUnavailable:
                return "Could not access Application Support directory."
            }
        }
    }

    private enum Defaults {
        static let alpha: Float = 3.2
        static let minCtcScore: Float = -2.4
        static let minSimilarity: Float = 0.68
        static let minCombinedConfidence: Float = 0.58
        static let minTermLength: Int = 2
        static let maxTerms: Int = 256
    }

    private let fileName = "parakeet_custom_vocabulary.json"
    private let appSupportFolder = "FluidVoice"

    private init() {}

    func vocabularyFileURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.applicationSupportUnavailable
        }
        let directory = base.appendingPathComponent(self.appSupportFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(self.fileName)
    }

    @discardableResult
    func ensureVocabularyFileExists() throws -> URL {
        let url = try self.vocabularyFileURL()
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        if let bundled = Bundle.main.url(forResource: "parakeet_custom_vocabulary.default", withExtension: "json"),
           let bundledText = try? String(contentsOf: bundled, encoding: .utf8)
        {
            try bundledText.write(to: url, atomically: true, encoding: .utf8)
        } else {
            try Self.defaultTemplateJSON().write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    func loadRawJSON() throws -> String {
        let url = try self.ensureVocabularyFileExists()
        return try String(contentsOf: url, encoding: .utf8)
    }

    func validateJSON(_ json: String) throws -> VocabularyConfig {
        let data = Data(json.utf8)
        do {
            return try JSONDecoder().decode(VocabularyConfig.self, from: data)
        } catch {
            throw StoreError.invalidJSON(error.localizedDescription)
        }
    }

    func saveRawJSON(_ json: String) throws {
        _ = try self.validateJSON(json)
        let url = try self.ensureVocabularyFileExists()
        try json.write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .parakeetVocabularyDidChange, object: nil)
    }

    func hasAnyBoostTerms() -> Bool {
        (try? self.loadResolvedConfig())?.terms.isEmpty == false
    }

    func loadResolvedConfig() throws -> ResolvedConfig {
        let rawJSON = try self.loadRawJSON()
        let parsed = (try? self.validateJSON(rawJSON)) ?? VocabularyConfig(
            alpha: nil,
            minCtcScore: nil,
            minSimilarity: nil,
            minCombinedConfidence: nil,
            minTermLength: nil,
            terms: []
        )

        let mergedTerms = self.mergeAndNormalizeTerms(jsonTerms: parsed.terms, dictionaryEntries: SettingsStore.shared.customDictionaryEntries)

        return ResolvedConfig(
            alpha: parsed.alpha ?? Defaults.alpha,
            minCtcScore: parsed.minCtcScore ?? Defaults.minCtcScore,
            minSimilarity: parsed.minSimilarity ?? Defaults.minSimilarity,
            minCombinedConfidence: parsed.minCombinedConfidence ?? Defaults.minCombinedConfidence,
            minTermLength: parsed.minTermLength ?? Defaults.minTermLength,
            terms: mergedTerms
        )
    }

    private func mergeAndNormalizeTerms(
        jsonTerms: [VocabularyConfig.Term],
        dictionaryEntries: [SettingsStore.CustomDictionaryEntry]
    ) -> [VocabularyConfig.Term] {
        var mergedByText: [String: VocabularyConfig.Term] = [:]

        func normalizeAliases(_ aliases: [String]?, excluding text: String) -> [String]? {
            let normalized = (aliases ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0.caseInsensitiveCompare(text) != .orderedSame }
            let deduped = Array(Set(normalized.map { $0.lowercased() })).sorted()
            return deduped.isEmpty ? nil : deduped
        }

        func upsert(_ term: VocabularyConfig.Term) {
            let normalizedText = term.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return }
            let key = normalizedText.lowercased()

            if let existing = mergedByText[key] {
                let combinedAliases = Array(Set((existing.aliases ?? []) + (term.aliases ?? []))).sorted()
                let combinedWeight = max(existing.weight ?? 0, term.weight ?? 0)
                mergedByText[key] = VocabularyConfig.Term(
                    text: existing.text,
                    weight: combinedWeight > 0 ? combinedWeight : nil,
                    aliases: combinedAliases.isEmpty ? nil : combinedAliases
                )
                return
            }

            mergedByText[key] = VocabularyConfig.Term(
                text: normalizedText,
                weight: term.weight,
                aliases: normalizeAliases(term.aliases, excluding: normalizedText)
            )
        }

        for term in jsonTerms {
            upsert(term)
        }

        for entry in dictionaryEntries {
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replacement.isEmpty else { continue }
            let aliases = entry.triggers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            upsert(VocabularyConfig.Term(text: replacement, weight: 10.0, aliases: aliases))
        }

        return mergedByText.values.sorted { lhs, rhs in
            lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
        }
    }

    static func defaultTemplateJSON() -> String {
        """
        {
          "alpha": 3.2,
          "minCtcScore": -2.4,
          "minSimilarity": 0.68,
          "minCombinedConfidence": 0.58,
          "minTermLength": 2,
          "terms": [
            {
              "text": "FluidVoice",
              "aliases": ["fluid voice", "fluid boys"],
              "weight": 12.0
            }
          ]
        }
        """
    }
}

extension Notification.Name {
    static let parakeetVocabularyDidChange = Notification.Name("ParakeetVocabularyDidChange")
}

#if arch(arm64)
extension ParakeetVocabularyStore {
    /// Creates tokenized vocabulary + CTC models for FluidAudio vocabulary boosting.
    func loadTokenizedVocabularyBundle(
        maxTerms: Int = 256
    ) async throws -> (vocabulary: CustomVocabularyContext, ctcModels: CtcModels)? {
        let resolved = try self.loadResolvedConfig()
        guard !resolved.terms.isEmpty else { return nil }

        let cappedLimit = min(maxTerms, Defaults.maxTerms)
        let cappedTerms = Array(resolved.terms.prefix(cappedLimit))
        let ctcModels = try await CtcModels.downloadAndLoad(variant: .ctc110m)
        let ctcTokenizer = try await CtcTokenizer.load(from: CtcModels.defaultCacheDirectory(for: ctcModels.variant))

        let tokenizedTerms: [CustomVocabularyTerm] = cappedTerms.compactMap { term in
            let tokens = ctcTokenizer.encode(term.text)
            guard !tokens.isEmpty else { return nil }
            return CustomVocabularyTerm(
                text: term.text,
                weight: term.weight,
                aliases: term.aliases,
                tokenIds: nil,
                ctcTokenIds: tokens
            )
        }

        guard !tokenizedTerms.isEmpty else { return nil }

        let vocabulary = CustomVocabularyContext(
            terms: tokenizedTerms,
            alpha: resolved.alpha,
            minCtcScore: resolved.minCtcScore,
            minSimilarity: resolved.minSimilarity,
            minCombinedConfidence: resolved.minCombinedConfidence,
            minTermLength: resolved.minTermLength
        )

        return (vocabulary, ctcModels)
    }
}
#endif
