import Foundation

enum AppLocalization {
    static func string(_ key: String, locale: Locale) -> String {
        let localeIdentifier = locale.identifier.lowercased()
        let localizationNames: [String]

        if localeIdentifier.hasPrefix("zh") {
            localizationNames = ["zh-Hans", "zh"]
        } else if localeIdentifier.hasPrefix("en") {
            localizationNames = ["en"]
        } else {
            localizationNames = []
        }

        for localizationName in localizationNames {
            guard let path = Bundle.main.path(forResource: localizationName, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path) else {
                continue
            }
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }

        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
