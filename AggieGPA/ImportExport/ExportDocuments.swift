import SwiftUI
import UniformTypeIdentifiers

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw BackupError.invalidFile }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum CSVService {
    static let headers = ["Academic Year", "Quarter", "Course Code", "Course Title", "Units", "Grade", "Grade Points", "Major Course", "Upper Division", "Repeat", "Included in GPA", "Institution", "Notes"]

    static func export(terms: [AcademicTerm]) -> String {
        var rows = [headers.map(escape).joined(separator: ",")]
        for term in terms.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            for course in term.courses.sorted(by: { $0.courseCode < $1.courseCode }) {
                let gradePoints = course.grade.gradePointValue.map { $0 * course.units }
                let values = [term.academicYear, term.displayName, course.courseCode, course.courseTitle,
                              DecimalFormatters.compact(course.units), course.grade.rawValue,
                              gradePoints.map(DecimalFormatters.compact) ?? "", String(course.isMajorCourse),
                              String(course.isUpperDivision), String(course.isRepeatCourse),
                              String(course.isIncludedInGPA), course.institution.rawValue, course.notes]
                rows.append(values.map(escape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

