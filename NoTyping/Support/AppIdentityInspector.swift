import Foundation
import Security

struct AppIdentitySnapshot: Equatable {
    var bundleIdentifier: String
    var bundlePath: String
    var signingIdentity: String
    var teamIdentifier: String?

    static var placeholder: AppIdentitySnapshot {
        AppIdentitySnapshot(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown bundle identifier",
            bundlePath: Bundle.main.bundleURL.path,
            signingIdentity: "Inspecting signing identity…",
            teamIdentifier: nil
        )
    }

    var summary: String {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return "\(signingIdentity) · Team \(teamIdentifier)"
        }
        return signingIdentity
    }
}

enum AppIdentityInspector {
    static func current(bundle: Bundle = .main) -> AppIdentitySnapshot {
        let bundleIdentifier = bundle.bundleIdentifier ?? "Unknown bundle identifier"
        let bundlePath = bundle.bundleURL.path
        let fallback = AppIdentitySnapshot(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            signingIdentity: "Signing identity unavailable",
            teamIdentifier: nil
        )

        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            return fallback
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard infoStatus == errSecSuccess, let info = signingInformation as? [String: Any] else {
            return fallback
        }

        let identity = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])
            .flatMap(\.first)
            .flatMap { SecCertificateCopySubjectSummary($0) as String? }
            ?? fallback.signingIdentity
        let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String

        return AppIdentitySnapshot(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            signingIdentity: identity,
            teamIdentifier: teamIdentifier
        )
    }
}
