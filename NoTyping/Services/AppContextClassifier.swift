import AppKit
import Foundation

struct AppContextResolution: Equatable {
    var matchedRule: AppRule?
    var category: AppCategory
    var profile: DictationProfile
    var aggressiveness: RewriteAggressiveness
    var disableRewrite: Bool
}

final class AppContextClassifier {
    private let defaults: [(String, AppCategory)] = [
        ("com.apple.mail", .email),
        ("com.apple.notes", .notes),
        ("com.apple.TextEdit", .document),
        ("com.apple.Safari", .browser),
        ("com.google.Chrome", .browser),
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.apple.MobileSMS", .chat),
        ("com.microsoft.Outlook", .email),
        ("com.apple.Terminal", .terminal),
        ("com.googlecode.iterm2", .terminal),
        ("com.microsoft.VSCode", .code),
        ("com.apple.dt.Xcode", .code)
    ]

    func classify(bundleIdentifier: String?, focusedElement: FocusedElementContext, rules: [AppRule]) -> AppCategory {
        if let rule = matchingRule(bundleIdentifier: bundleIdentifier, rules: rules) {
            return rule.category
        }

        return classifyDefault(bundleIdentifier: bundleIdentifier, focusedElement: focusedElement)
    }

    func matchingRule(bundleIdentifier: String?, rules: [AppRule]) -> AppRule? {
        guard let bundleIdentifier else { return nil }
        return rules.first(where: { bundleIdentifier.localizedCaseInsensitiveContains($0.bundleIdentifierPattern) })
    }

    func resolve(bundleIdentifier: String?, focusedElement: FocusedElementContext, settings: AppSettings) -> AppContextResolution {
        let matchedRule = matchingRule(bundleIdentifier: bundleIdentifier, rules: settings.appRules)
        let category = matchedRule?.category ?? classifyDefault(bundleIdentifier: bundleIdentifier, focusedElement: focusedElement)
        let profile = matchedRule?.preferredProfile ?? defaultProfile(for: category, settings: settings)
        let aggressiveness = matchedRule?.aggressivenessOverride ?? settings.rewriteAggressiveness

        return AppContextResolution(
            matchedRule: matchedRule,
            category: category,
            profile: profile,
            aggressiveness: aggressiveness,
            disableRewrite: matchedRule?.disableRewrite ?? false
        )
    }

    private func classifyDefault(bundleIdentifier: String?, focusedElement: FocusedElementContext) -> AppCategory {
        if let bundleIdentifier {
            for (pattern, category) in defaults where bundleIdentifier == pattern || bundleIdentifier.hasPrefix(pattern) {
                return category
            }
        }

        if focusedElement.fieldType == .singleLine {
            return .chat
        }
        return .unknown
    }

    private func defaultProfile(for category: AppCategory, settings: AppSettings) -> DictationProfile {
        switch category {
        case .code, .terminal:
            .codeAware
        case .email:
            .email
        case .notes:
            .notes
        default:
            settings.defaultProfile
        }
    }
}
