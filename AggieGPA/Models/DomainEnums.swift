import Foundation

enum TermType: String, Codable, CaseIterable, Identifiable {
    case fall = "Fall"
    case winter = "Winter"
    case spring = "Spring"
    case summerOne = "Summer Session I"
    case summerTwo = "Summer Session II"
    case summerSpecial = "Summer Special Session"
    case other = "Other"

    var id: String { rawValue }
}

enum CourseGrade: String, Codable, CaseIterable, Identifiable {
    case aPlus = "A+", a = "A", aMinus = "A-"
    case bPlus = "B+", b = "B", bMinus = "B-"
    case cPlus = "C+", c = "C", cMinus = "C-"
    case dPlus = "D+", d = "D", dMinus = "D-"
    case f = "F"
    case pass = "P", noPass = "NP", satisfactory = "S", unsatisfactory = "U"
    case incomplete = "I", inProgress = "IP", noGrade = "NG"
    case planned = "Planned"

    var id: String { rawValue }

    /// UC Davis grade-point mapping verified against DDR A540(B) on 2026-07-21.
    /// A+ is deliberately 4.0, not 4.3. Non-letter notations return nil.
    var gradePointValue: Decimal? {
        switch self {
        case .aPlus, .a: 4
        case .aMinus: Decimal(string: "3.7")
        case .bPlus: Decimal(string: "3.3")
        case .b: 3
        case .bMinus: Decimal(string: "2.7")
        case .cPlus: Decimal(string: "2.3")
        case .c: 2
        case .cMinus: Decimal(string: "1.7")
        case .dPlus: Decimal(string: "1.3")
        case .d: 1
        case .dMinus: Decimal(string: "0.7")
        case .f: 0
        case .pass, .noPass, .satisfactory, .unsatisfactory,
             .incomplete, .inProgress, .noGrade, .planned: nil
        }
    }

    var isPending: Bool {
        self == .incomplete || self == .inProgress || self == .noGrade || self == .planned
    }
}

enum GradingBasis: String, Codable, CaseIterable, Identifiable {
    case letter = "Letter Grade"
    case passNoPass = "P/NP"
    case satisfactoryUnsatisfactory = "S/U"

    var id: String { rawValue }
}

enum InstitutionType: String, Codable, CaseIterable, Identifiable {
    case ucDavis = "UC Davis"
    case otherUC = "Other UC Campus"
    case communityCollege = "Community College"
    case highSchool = "High School Credit"
    case examCredit = "AP / IB / A-Level"
    case otherInstitution = "Other Institution"
    case transferCredit = "Transfer Credit"
    case planningOnly = "Personal Planning Only"

    var id: String { rawValue }
    var defaultIncludesInUCGPA: Bool { self == .ucDavis || self == .otherUC }
}

enum RepeatHandlingMode: String, Codable, CaseIterable, Identifiable {
    case originalAttempt = "Original Attempt"
    case secondAttempt = "Second Attempt"
    case mostRecentAttempt = "Most Recent Attempt"
    case includeBoth = "Include Both"
    case excludeOriginal = "Exclude Original Under Repeat Rule"
    case transcriptDecided = "Official Transcript Already Decided"
    case manualReview = "Manual Review Needed"

    var id: String { rawValue }
}

enum ScenarioType: String, Codable, CaseIterable, Identifiable {
    case bestCase = "Best Case"
    case expected = "Expected"
    case conservative = "Conservative"
    case finalsGoal = "Finals Goal"
    case custom = "Custom"

    var id: String { rawValue }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case english = "English"
    case simplifiedChinese = "简体中文"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

enum AppIconStyle: String, Codable, CaseIterable, Identifiable {
    case defaultStyle = "Default", dark = "Dark", clear = "Clear", tinted = "Tinted"
    var id: String { rawValue }
}

enum PrivacyLockDelay: String, Codable, CaseIterable, Identifiable {
    case immediately = "Immediately", oneMinute = "1 minute", fiveMinutes = "5 minutes"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self { case .immediately: 0; case .oneMinute: 60; case .fiveMinutes: 300 }
    }
}
