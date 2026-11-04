import ColiUICore

/// Settings › General › Menu bar › Containers to show.
enum MenuBarLimit: String, CaseIterable, Identifiable {
    case four = "4", eight = "8", twelve = "12", all = "All"

    var id: Self { self }

    /// Nil for All.
    var count: Int? { Int(rawValue) }
}

/// What the menu bar popover lists (Favorites.dc.html): the running favorites when there are any,
/// otherwise the first containers A to Z — grouped by Compose project either way.
struct MenuBarList {
    enum Kind { case favorites, containers }

    let kind: Kind
    let groups: [ComposeGroup]
    let shownCount: Int

    static func make(containers: [Container], favorites: ContainerFavorites, limit: Int?) -> MenuBarList {
        let runningFavorites = containers.filter { $0.isRunning && favorites.contains($0) }
        if !runningFavorites.isEmpty {
            return MenuBarList(kind: .favorites, groups: ComposeGroup.grouped(runningFavorites, standaloneName: "Standalone"),
                               shownCount: runningFavorites.count)
        }
        let sorted = containers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let shown = limit.map { Array(sorted.prefix($0)) } ?? sorted
        return MenuBarList(kind: .containers, groups: ComposeGroup.grouped(shown, standaloneName: "Standalone"),
                           shownCount: shown.count)
    }
}
