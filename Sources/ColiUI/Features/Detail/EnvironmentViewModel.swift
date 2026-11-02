import ColiUICore
import Foundation
import Observation

/// One table row; `value` is the real value (what COPY copies), `shownValue` what the table shows.
struct EnvironmentRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let value: String
    let shownValue: String
    let source: EnvironmentEntry.Source
    let isSecret: Bool
    let isRevealed: Bool
}

/// Environment.dc.html: the container's variables, secrets masked until revealed.
@MainActor
@Observable
final class EnvironmentViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case container = "Container"
        case image = "Image"
        var id: Self { self }
    }

    enum State: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    var filter = ""
    var scope: Scope = .all
    /// "Show secrets"; each row's eye adds to `revealed` instead.
    var revealAll = false
    private(set) var revealed: Set<String> = []
    private(set) var state: State = .idle
    private(set) var entries: [EnvironmentEntry] = []

    let containerID: String
    private let source: ContainerEnvironmentSource

    init(containerID: String, source: ContainerEnvironmentSource) {
        self.containerID = containerID
        self.source = source
    }

    func load() async {
        if entries.isEmpty { state = .loading }
        do {
            entries = try await source.environment(id: containerID)
            state = .loaded
        } catch {
            entries = []
            state = .failed(error.localizedDescription)
        }
    }

    func count(of scope: Scope) -> Int {
        entries.filter { Self.matches($0, scope) }.count
    }

    /// Matches the name or the shown value, so a masked secret can't be found by what it hides.
    var rows: [EnvironmentRow] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return entries.enumerated().compactMap { index, entry in
            guard Self.matches(entry, scope) else { return nil }
            let isRevealed = !entry.isSecret || revealAll || revealed.contains(entry.name)
            let shown = isRevealed ? entry.value : SecretMask.placeholder
            guard query.isEmpty || entry.name.localizedCaseInsensitiveContains(query) || shown.localizedCaseInsensitiveContains(query) else {
                return nil
            }
            return EnvironmentRow(id: index, name: entry.name, value: entry.value, shownValue: shown,
                                  source: entry.source, isSecret: entry.isSecret, isRevealed: isRevealed)
        }
    }

    func toggleReveal(_ name: String) {
        if revealed.contains(name) { revealed.remove(name) } else { revealed.insert(name) }
    }

    /// Leaving the tab masks everything again.
    func hideSecrets() {
        revealAll = false
        revealed = []
    }

    /// "Copy as .env": the visible rows as shown.
    var dotEnv: String {
        rows.map { "\($0.name)=\($0.shownValue)\n" }.joined()
    }

    var footnote: String {
        if revealAll { return "Secrets visible until you leave this tab" }
        let hidden = entries.filter { $0.isSecret && !revealed.contains($0.name) }.count
        return "\(hidden) \(hidden == 1 ? "secret" : "secrets") masked"
    }

    private static func matches(_ entry: EnvironmentEntry, _ scope: Scope) -> Bool {
        switch scope {
        case .all: true
        case .container: entry.source == .container
        case .image: entry.source == .image
        }
    }
}
