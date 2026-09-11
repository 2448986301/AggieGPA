import Foundation

/// Test hosts and preview routes must never open the student's durable store,
/// even when Xcode regenerates a test descriptor without custom arguments.
enum AppDataIsolation {
    static let isEnabled: Bool = {
        isEnabled(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment,
            testRuntimeLoaded: NSClassFromString("XCTestCase") != nil
                || NSClassFromString("XCTest.XCTestCase") != nil
        )
    }()

    static func isEnabled(
        arguments: [String],
        environment: [String: String],
        testRuntimeLoaded: Bool
    ) -> Bool {
        let isolatedArguments: Set<String> = ["--uitest-in-memory", "--ui-testing", "--screenshot-demo"]
        let testEnvironmentKeys = [
            "XCTestConfigurationFilePath", "XCTestBundlePath",
            "XCTestSessionIdentifier", "XCInjectBundleInto"
        ]
        return testRuntimeLoaded
            || arguments.contains(where: isolatedArguments.contains)
            || testEnvironmentKeys.contains { !(environment[$0] ?? "").isEmpty }
    }
}
