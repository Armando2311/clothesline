import AppKit
import ClotheslineCore

/// Release discovery is explicit. Installation stays in the user's normal download flow.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var checking = false
    private struct Release:Decodable { let tag_name:String; let html_url:URL; let prerelease:Bool; let draft:Bool }
    func check() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                let url = URL(string:"https://api.github.com/repos/Armando2311/clothesline/releases/latest")!
                var request = URLRequest(url:url); request.timeoutInterval = 20
                request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
                let (data,response) = try await URLSession.shared.data(for:request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 { show("No published release yet",detail:"Your development build is ready to use. Signed releases will appear here when published."); return }
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(Release.self,from:data)
                guard !release.draft,!release.prerelease,ReleaseVersion.isTrustedReleaseURL(release.html_url) else { throw URLError(.badServerResponse) }
                let current = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0"
                if ReleaseVersion.isNewer(release.tag_name,than:current) {
                    show("Clothesline \(release.tag_name) is available",detail:"You have version \(current). View the release notes and download the update.",releaseURL:release.html_url)
                } else { show("You’re up to date",detail:"You have Clothesline \(current).") }
            } catch { show("Could not check for updates",detail:"Check your connection and try again. \(error.localizedDescription)") }
        }
    }
    private func show(_ title:String,detail:String,releaseURL:URL? = nil) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.window.level = WorkflowPresentation.modalLevel
        alert.addButton(withTitle:releaseURL == nil ? "OK" : "View Release")
        if releaseURL != nil { alert.addButton(withTitle:"Later") }
        NSApp.activate(ignoringOtherApps:true)
        if alert.runModal() == .alertFirstButtonReturn,let releaseURL { NSWorkspace.shared.open(releaseURL) }
    }
}
