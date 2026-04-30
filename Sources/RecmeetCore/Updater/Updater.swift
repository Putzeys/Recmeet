import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ReleaseInfo: Sendable {
    public let version: AppVersion
    public let tagName: String
    public let body: String
    public let pageURL: URL
    public let macAssetURL: URL?
    public let windowsAssetURL: URL?
}

public enum UpdaterError: Error, LocalizedError {
    case malformedResponse
    case noAssetForPlatform

    public var errorDescription: String? {
        switch self {
        case .malformedResponse: return "Couldn't parse the GitHub release response."
        case .noAssetForPlatform: return "The latest release doesn't have a binary for this platform."
        }
    }
}

public enum Updater {
    public static let repoOwner = "Putzeys"
    public static let repoName  = "Recmeet"

    /// Fetches the most recent published release from GitHub.
    /// Returns nil if the repo has no releases yet.
    public static func fetchLatestRelease() async throws -> ReleaseInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("recmeet/\(RECMEET_CURRENT_VERSION)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let version = AppVersion(tag) else {
            throw UpdaterError.malformedResponse
        }

        let body = json["body"] as? String ?? ""
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!

        var macURL: URL?
        var winURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = (asset["name"] as? String)?.lowercased(),
                      let dlString = asset["browser_download_url"] as? String,
                      let dl = URL(string: dlString) else { continue }
                if name.contains("macos")        { macURL = dl }
                else if name.contains("windows") { winURL = dl }
            }
        }

        return ReleaseInfo(
            version: version,
            tagName: tag,
            body: body,
            pageURL: page,
            macAssetURL: macURL,
            windowsAssetURL: winURL
        )
    }

    /// True when `release.version` is strictly newer than the build's bundled version.
    public static func isNewer(_ release: ReleaseInfo) -> Bool {
        release.version > RECMEET_CURRENT_VERSION
    }
}
