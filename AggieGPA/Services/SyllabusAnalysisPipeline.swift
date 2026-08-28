import Foundation

/// The deterministic, local-only document preparation step used before any
/// model call. It keeps page markers attached to every chunk so extracted
/// evidence can be reviewed against the original PDF.
nonisolated enum SyllabusSectionKind: String, Codable, Hashable, Sendable {
    case grading
    case assessment
    case policy
    case mixed
    case context
}

nonisolated struct SyllabusTextSection: Equatable, Sendable {
    let page: Int
    let kind: SyllabusSectionKind
    let text: String
}

nonisolated struct SyllabusAnalysisChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let pages: [Int]
    let kind: SyllabusSectionKind
    let text: String

    init(id: UUID = UUID(), pages: [Int], kind: SyllabusSectionKind, text: String) {
        self.id = id
        self.pages = pages
        self.kind = kind
        self.text = text
    }
}

nonisolated enum SyllabusAnalysisPipeline {
    static let defaultMaximumCharacters = 9_000

    static func sections(from document: SyllabusTextExtractor.Document) -> [SyllabusTextSection] {
        var result: [SyllabusTextSection] = []
        for page in document.pages {
            guard let rawText = page.text else { continue }
            let normalized = rawText
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let pageSections = normalized
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { text in
                    SyllabusTextSection(page: page.number, kind: classify(text), text: text)
                }
            result.append(contentsOf: pageSections)
        }
        return result
    }

    static func relevantSections(from document: SyllabusTextExtractor.Document) -> [SyllabusTextSection] {
        let all = sections(from: document)
        let relevant = all.filter { $0.kind != .context }
        // A short syllabus may not use any of the English/Chinese headings we
        // recognize. In that case retain all native PDF text rather than
        // silently dropping material from the analysis.
        return relevant.isEmpty ? all : relevant
    }

    static func chunks(
        from document: SyllabusTextExtractor.Document,
        maximumCharacters: Int = defaultMaximumCharacters
    ) -> [SyllabusAnalysisChunk] {
        let limit = max(512, maximumCharacters)
        let sections = relevantSections(from: document)
        guard !sections.isEmpty else { return [] }

        var chunks: [SyllabusAnalysisChunk] = []
        var currentText = ""
        var currentPages: [Int] = []
        var currentKinds: [SyllabusSectionKind] = []

        func flush() {
            guard !currentText.isEmpty else { return }
            let kind = Set(currentKinds).count == 1 ? (currentKinds.first ?? .context) : .mixed
            chunks.append(SyllabusAnalysisChunk(pages: currentPages, kind: kind, text: currentText))
            currentText = ""
            currentPages = []
            currentKinds = []
        }

        for section in sections {
            let prefix = "[PAGE \(section.page)]\n"
            let text = prefix + section.text
            if text.count > limit {
                flush()
                var cursor = section.text.startIndex
                let bodyLimit = max(1, limit - prefix.count)
                while cursor < section.text.endIndex {
                    let end = section.text.index(cursor, offsetBy: bodyLimit, limitedBy: section.text.endIndex) ?? section.text.endIndex
                    let body = String(section.text[cursor..<end])
                    chunks.append(
                        SyllabusAnalysisChunk(
                            pages: [section.page],
                            kind: section.kind,
                            text: prefix + body
                        )
                    )
                    cursor = end
                }
                continue
            }

            let candidate = currentText.isEmpty ? text : currentText + "\n\n" + text
            if candidate.count > limit { flush() }
            currentText = currentText.isEmpty ? text : currentText + "\n\n" + text
            if !currentPages.contains(section.page) { currentPages.append(section.page) }
            currentKinds.append(section.kind)
        }
        flush()
        return chunks
    }

    static func relevantText(from document: SyllabusTextExtractor.Document) -> String {
        chunks(from: document).map(\.text).joined(separator: "\n\n")
    }

    /// Produces a smaller retry context without dropping the page marker. The
    /// first attempt already receives a relevant, bounded chunk; this helper
    /// is deliberately more conservative so a malformed model response can
    /// be retried without simply increasing context pressure again.
    static func compactRetryText(_ text: String, maximumCharacters: Int = 3_200) -> String {
        let limit = max(512, maximumCharacters)
        guard text.count > limit else { return text }
        let separator = "\n[… relevant section shortened for retry …]\n"
        let bodyLimit = max(2, limit - separator.count)
        let headCount = max(1, (bodyLimit * 2) / 3)
        let tailCount = max(1, bodyLimit - headCount)
        let head = String(text.prefix(headCount))
        let tail = String(text.suffix(tailCount))
        return head + separator + tail
    }

    private static func classify(_ text: String) -> SyllabusSectionKind {
        let value = text.lowercased()
        let grading = [
            "grading", "grade", "evaluation", "percentage", "weight", "score", "rubric",
            "成绩", "评分", "考核", "百分比", "权重", "分数", "评分标准"
        ]
        let assessment = [
            "assignment", "homework", "quiz", "exam", "midterm", "final", "project", "lab",
            "作业", "家庭作业", "测验", "考试", "期中", "期末", "项目", "实验"
        ]
        let policy = [
            "late", "attendance", "extra credit", "bonus", "drop lowest", "best of", "replacement",
            "missing work", "迟交", "出勤", "加分", "奖励分", "最低分", "替代考试", "缺交"
        ]
        func matches(_ keyword: String) -> Bool {
            if keyword.contains(" ") || keyword.unicodeScalars.contains(where: { $0.value > 127 }) {
                return value.contains(keyword)
            }
            return value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == keyword }
        }
        let hasGrading = grading.contains { matches($0) } || value.contains("%")
        let hasAssessment = assessment.contains { matches($0) }
        let hasPolicy = policy.contains { matches($0) }
        let kind: SyllabusSectionKind
        switch (hasGrading, hasAssessment, hasPolicy) {
        case (true, _, true): kind = .mixed
        case (true, _, false): kind = .grading
        case (false, true, true): kind = .mixed
        case (false, true, false): kind = .assessment
        case (false, false, true): kind = .policy
        case (false, false, false): kind = .context
        }
        return kind
    }
}
