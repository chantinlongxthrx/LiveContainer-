//
//  CompanionAppUpdateChecker.swift
//  LiveContainerSwiftUI
//
//  Checks GitHub Releases for newer versions of the standalone companion
//  apps LiveContainer integrates with (LocalDevVPN, StikPair, StikDebug).
//
//  This can only ever be a "check and notify" feature, not a silent
//  auto-installer: LiveContainer is a regular sandboxed app and has no way
//  to install or update a *different* app on the system without the user
//  going through AltStore/SideStore/Xcode like any other sideload. Tapping
//  a result opens that release's GitHub page so the user can grab it.
//
import Foundation

struct CompanionRepo: Identifiable {
    let id: String
    let displayName: String
    let owner: String
    let repo: String
    /// True if this owner/repo is a confirmed canonical source rather than
    /// a best guess. StikPair's public repo couldn't be confirmed via web
    /// search at the time this was written, so it's left editable below.
    let confirmed: Bool
    
    var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }
    
    var repoURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }
}

enum CompanionAppRepos {
    // Confirmed via the project's own README/repo metadata.
    static let localDevVPN = CompanionRepo(id: "localdevvpn", displayName: "LocalDevVPN", owner: "jkcoxson", repo: "LocalDevVPN", confirmed: true)
    static let stikDebug = CompanionRepo(id: "stikdebug", displayName: "StikDebug", owner: "StephenDev0", repo: "StikDebug", confirmed: true)
    // Best guess from the same author/license as StikDebug; not directly
    // confirmed. Edit `repo` below if this turns out to be wrong.
    static let stikPair = CompanionRepo(id: "stikpair", displayName: "StikPair", owner: "StephenDev0", repo: "StikPair", confirmed: false)
    static let feather = CompanionRepo(id: "feather", displayName: "Feather", owner: "claration", repo: "Feather", confirmed: true)
    static let ksign = CompanionRepo(id: "ksign", displayName: "Ksign", owner: "Nyasami", repo: "Ksign-public", confirmed: true)
    
    static let all: [CompanionRepo] = [localDevVPN, stikPair, stikDebug, feather, ksign]
}

struct CompanionReleaseInfo {
    let version: String
    let releaseURL: URL
    let publishedAt: Date?
}

enum CompanionUpdateCheckError: Error {
    case network
    case noReleases
}

@MainActor
final class CompanionAppUpdateChecker: ObservableObject {
    static let shared = CompanionAppUpdateChecker()
    
    @Published var results: [String: Result<CompanionReleaseInfo, Error>] = [:]
    @Published var isChecking = false
    
    func checkAll() async {
        isChecking = true
        defer { isChecking = false }
        
        await withTaskGroup(of: (String, Result<CompanionReleaseInfo, Error>).self) { group in
            for repo in CompanionAppRepos.all {
                group.addTask {
                    do {
                        let info = try await Self.fetchLatestRelease(for: repo)
                        return (repo.id, .success(info))
                    } catch {
                        return (repo.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                results[id] = result
            }
        }
    }
    
    private static func fetchLatestRelease(for repo: CompanionRepo) async throws -> CompanionReleaseInfo {
        var request = URLRequest(url: repo.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CompanionUpdateCheckError.noReleases
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else {
            throw CompanionUpdateCheckError.noReleases
        }
        
        var publishedAt: Date? = nil
        if let publishedString = json["published_at"] as? String {
            publishedAt = ISO8601DateFormatter().date(from: publishedString)
        }
        
        return CompanionReleaseInfo(version: tagName, releaseURL: htmlURL, publishedAt: publishedAt)
    }
}
