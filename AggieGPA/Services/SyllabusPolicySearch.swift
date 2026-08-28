import Foundation
import NaturalLanguage

/// A page-backed excerpt returned by the local syllabus search index. The
/// original document is kept in the current import flow only; this value is a
/// compact, reviewable citation rather than a persisted copy of the PDF.
nonisolated struct SyllabusPolicyEvidence: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let page: Int
    let sourceText: String
    let confidence: Double
    let score: Double

    init(page: Int, sourceText: String, confidence: Double, score: Double) {
        self.id = "\(page)|\(sourceText)"
        self.page = page
        self.sourceText = sourceText
        self.confidence = confidence
        self.score = score
    }
}

nonisolated enum SyllabusPolicySearchStatus: String, Codable, Sendable {
    case evidenceFound
    case noMatchingEvidence
    case emptyQuery
}

nonisolated enum SyllabusPolicyRetrievalMode: String, Codable, Sendable {
    case sentenceEmbedding
    case lexicalFallback
}

nonisolated struct SyllabusPolicySearchResult: Codable, Equatable, Sendable {
    let query: String
    let status: SyllabusPolicySearchStatus
    let matches: [SyllabusPolicyEvidence]
    let searchedPageCount: Int
    let retrievalMode: SyllabusPolicyRetrievalMode

    init(
        query: String,
        status: SyllabusPolicySearchStatus,
        matches: [SyllabusPolicyEvidence],
        searchedPageCount: Int,
        retrievalMode: SyllabusPolicyRetrievalMode = .lexicalFallback
    ) {
        self.query = query
        self.status = status
        self.matches = matches
        self.searchedPageCount = searchedPageCount
        self.retrievalMode = retrievalMode
    }

    var hasEvidence: Bool { !matches.isEmpty }
}

nonisolated enum SyllabusPolicyExplanationSource: String, Codable, Sendable {
    case localModel
    case manualEvidenceFallback
}

nonisolated struct SyllabusPolicyExplanation: Codable, Equatable, Sendable {
    let text: String
    let source: SyllabusPolicyExplanationSource
    let confidence: Double

    static func manualFallback(query: String, evidence: [SyllabusPolicyEvidence]) -> Self {
        let excerpts = evidence.prefix(2).map { "Page \($0.page): \($0.sourceText)" }.joined(separator: "\n")
        return Self(
            text: "The syllabus evidence below is the answer to \"\(query)\". Review the cited page before relying on it.\n\n\(excerpts)",
            source: .manualEvidenceFallback,
            confidence: evidence.map(\.confidence).min() ?? 0
        )
    }
}

/// Deterministic, evidence-first retrieval over the native text saved for a
/// course after import. It never sends the entire PDF to a model and it
/// returns no answer when no source excerpt matches the query.
nonisolated enum SyllabusPolicySearchEngine {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "can", "do", "does", "for", "how", "i", "if", "in",
        "is", "it", "me", "my", "of", "on", "or", "submit", "the", "this", "to", "what",
        "when", "where", "will", "with", "you", "your"
    ]

    private static let policyExpansions: [String: Set<String>] = [
        "late": ["late", "迟交", "延期", "extension", "extensions", "延迟"],
        "迟交": ["late", "迟交", "延期", "extension", "extensions", "延迟"],
        "homework": ["homework", "assignment", "assignments", "作业", "练习"],
        "作业": ["homework", "assignment", "assignments", "作业", "练习"],
        "exam": ["exam", "exams", "test", "midterm", "final", "考试", "期中", "期末"],
        "考试": ["exam", "exams", "test", "midterm", "final", "考试", "期中", "期末"],
        "final": ["final", "exam", "exams", "期末", "考试"],
        "percentage": ["percentage", "percent", "weight", "worth", "%", "占比", "比例"],
        "weight": ["weight", "worth", "percentage", "percent", "%", "占比", "比例"],
        "attendance": ["attendance", "absence", "出勤", "缺勤"],
        "出勤": ["attendance", "absence", "出勤", "缺勤"],
        "extra": ["extra", "bonus", "加分", "额外"],
        "加分": ["extra", "bonus", "加分", "额外"],
        "drop": ["drop", "dropped", "lowest", "舍弃", "最低分"],
        "最低分": ["drop", "dropped", "lowest", "舍弃", "最低分"]
    ]

    private struct SearchCandidate {
        let page: Int
        let text: String
    }

    private static let semanticCandidateLimit = 120

    static func search(
        query: String,
        in document: SyllabusTextExtractor.Document,
        limit: Int = 5
    ) -> SyllabusPolicySearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .init(query: query, status: .emptyQuery, matches: [], searchedPageCount: document.pages.count)
        }

        let matches = lexicalMatches(
            query: trimmedQuery,
            candidates: candidates(in: document),
            limit: limit
        )
        return .init(
            query: trimmedQuery,
            status: matches.isEmpty ? .noMatchingEvidence : .evidenceFound,
            matches: matches,
            searchedPageCount: document.pages.count,
            retrievalMode: .lexicalFallback
        )
    }

    /// Hybrid local retrieval used by the user-facing policy question flow.
    /// Apple's sentence embedding is optional and system-provided, so it adds
    /// no app-bundle model. When unavailable (including simulator limitations),
    /// the exact deterministic lexical search remains the safe fallback.
    static func searchSemantic(
        query: String,
        in document: SyllabusTextExtractor.Document,
        limit: Int = 5
    ) -> SyllabusPolicySearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return search(query: query, in: document, limit: limit)
        }

        let candidates = candidates(in: document)
        let lexicalMatches = lexicalMatches(query: trimmedQuery, candidates: candidates, limit: limit)
        let lexical = SyllabusPolicySearchResult(
            query: trimmedQuery,
            status: lexicalMatches.isEmpty ? .noMatchingEvidence : .evidenceFound,
            matches: lexicalMatches,
            searchedPageCount: document.pages.count,
            retrievalMode: .lexicalFallback
        )

        // Deterministic lexical evidence is already grounded and ordered. Do
        // not pay the sentence-embedding cost just to rerank an answer we can
        // already show. Semantic retrieval is reserved for genuine paraphrase
        // queries with no lexical evidence.
        guard lexicalMatches.isEmpty,
              let embedding = sentenceEmbedding(for: trimmedQuery) else { return lexical }

        let terms = searchTerms(trimmedQuery)
        let semanticCandidates = boundedSemanticCandidates(
            candidates.filter { hasPolicySignal(in: $0.text) },
            limit: semanticCandidateLimit
        )
        let scored = semanticCandidates.compactMap { candidate -> SyllabusPolicyEvidence? in
            let distance = embedding.distance(
                between: trimmedQuery,
                and: candidate.text,
                distanceType: .cosine
            )
            guard distance.isFinite else { return nil }
            let semanticSimilarity = max(0, min(1, 1 - distance))
            let lexicalScore = relevance(of: candidate.text, terms: terms, query: trimmedQuery)
            let policySignal = hasPolicySignal(in: candidate.text)
            // Semantic similarity may discover paraphrases, but it cannot
            // override the evidence-first policy boundary by itself. Require
            // either a lexical policy hit or an explicit policy signal.
            guard lexicalScore > 0 || (semanticSimilarity >= 0.62 && policySignal) else { return nil }
            let score = lexicalScore + semanticSimilarity * 1.5
            let confidence = min(0.98, max(0.35, 0.45 + semanticSimilarity * 0.5))
            return SyllabusPolicyEvidence(
                page: candidate.page,
                sourceText: candidate.text,
                confidence: confidence,
                score: score
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.page != $1.page { return $0.page < $1.page }
            return $0.sourceText < $1.sourceText
        }

        var seen = Set<String>()
        let matches = scored.filter { seen.insert($0.id).inserted }.prefix(max(1, limit))
        guard !matches.isEmpty else { return lexical }
        return .init(
            query: trimmedQuery,
            status: .evidenceFound,
            matches: Array(matches),
            searchedPageCount: document.pages.count,
            retrievalMode: .sentenceEmbedding
        )
    }

    private static func candidates(
        in document: SyllabusTextExtractor.Document
    ) -> [SearchCandidate] {
        document.pages.flatMap { page -> [SearchCandidate] in
            guard let text = page.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return []
            }
            let paragraphs = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return (paragraphs.isEmpty ? [text] : paragraphs).map {
                SearchCandidate(page: page.number, text: $0)
            }
        }
    }

    private static func lexicalMatches(
        query: String,
        candidates: [SearchCandidate],
        limit: Int
    ) -> [SyllabusPolicyEvidence] {
        let terms = searchTerms(query)
        let resultLimit = max(1, limit)
        var seen = Set<String>()
        var best: [SyllabusPolicyEvidence] = []
        best.reserveCapacity(resultLimit)

        for candidate in candidates {
            let score = relevance(of: candidate.text, terms: terms, query: query)
            guard score > 0 else { continue }
            let confidence = min(0.98, max(0.35, score / max(Double(terms.count), 1)))
            let evidence = SyllabusPolicyEvidence(
                page: candidate.page,
                sourceText: candidate.text,
                confidence: confidence,
                score: score
            )
            guard seen.insert(evidence.id).inserted else { continue }

            // Keep only the requested number of candidates while scanning. The
            // old implementation materialized and sorted every matching
            // paragraph, even though the UI only displays the first five.
            best.append(evidence)
            best.sort(by: isBetter)
            if best.count > resultLimit { best.removeLast() }
        }
        return best
    }

    private static func isBetter(
        _ lhs: SyllabusPolicyEvidence,
        _ rhs: SyllabusPolicyEvidence
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.page != rhs.page { return lhs.page < rhs.page }
        return lhs.sourceText < rhs.sourceText
    }

    private static func boundedSemanticCandidates(
        _ candidates: [SearchCandidate],
        limit: Int
    ) -> [SearchCandidate] {
        guard candidates.count > limit, limit > 0 else { return candidates }
        let stride = Double(candidates.count) / Double(limit)
        return (0..<limit).map { index in
            candidates[min(Int(Double(index) * stride), candidates.count - 1)]
        }
    }

    private static func searchTerms(_ query: String) -> [String] {
        let lowercased = query.lowercased()
        var terms: [String] = []
        var current = ""
        for scalar in lowercased.unicodeScalars {
            let character = Character(String(scalar))
            if character.isLetter || character.isNumber {
                current.unicodeScalars.append(scalar)
            } else {
                if current.count >= 2, !stopWords.contains(current) { terms.append(current) }
                current = ""
                if scalar.value >= 0x4E00, scalar.value <= 0x9FFF {
                    terms.append(String(scalar))
                }
            }
        }
        if current.count >= 2, !stopWords.contains(current) { terms.append(current) }

        var expanded = Set(terms)
        for term in terms {
            expanded.formUnion(policyExpansions[term] ?? [])
        }
        // Chinese questions often arrive as one uninterrupted scalar run, so
        // also expand known policy phrases before lexical scoring.
        for (phrase, synonyms) in policyExpansions where lowercased.contains(phrase) {
            expanded.insert(phrase)
            expanded.formUnion(synonyms)
        }
        return Array(expanded).sorted()
    }

    private static func relevance(of text: String, terms: [String], query: String) -> Double {
        let lowercased = text.lowercased()
        let normalizedQuery = query.lowercased()
        var score = lowercased.contains(normalizedQuery) ? 2.0 : 0
        for term in terms {
            if containsToken(term, in: lowercased) {
                score += term.count == 1 ? 0.5 : 1
            }
        }
        // A policy answer should be grounded by more than a generic occurrence
        // such as a heading named "Homework". Require either a phrase match,
        // two lexical hits, or one explicit policy signal.
        let policySignal = hasPolicySignal(in: lowercased)
        if score < 2, !policySignal { return 0 }
        return score
    }

    private static func hasPolicySignal(in text: String) -> Bool {
        let lowercased = text.lowercased()
        return [
            "late", "迟交", "extension", "延期", "policy", "规则", "drop", "lowest", "最低",
            "final", "exam", "midterm", "quiz", "percentage", "percent", "weight", "worth", "%",
            "期末", "考试", "占比", "比例"
        ].contains {
            containsToken($0, in: lowercased)
        }
    }

    private static func sentenceEmbedding(for query: String) -> NLEmbedding? {
        let hasChinese = query.unicodeScalars.contains {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }
        return NLEmbedding.sentenceEmbedding(for: hasChinese ? .simplifiedChinese : .english)
    }

    private static func containsToken(_ term: String, in text: String) -> Bool {
        guard term.count > 1 else { return text.contains(term) }
        guard term.unicodeScalars.allSatisfy({
            let character = Character(String($0))
            return character.isLetter || character.isNumber
        }) else {
            return text.contains(term)
        }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        return text.range(of: "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])", options: .regularExpression) != nil
    }
}

nonisolated protocol SyllabusPolicyExplainer: Sendable {
    func explainPolicy(
        query: String,
        evidence: [SyllabusPolicyEvidence]
    ) async throws -> SyllabusPolicyExplanation
}
