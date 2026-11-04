import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private func box(_ name: String, project: String? = nil, running: Bool = true) -> Container {
    Container(id: name + "-id", name: name, image: "img", state: running ? .running : .exited,
              status: running ? "Up 1 hour" : "Exited (0)", composeProject: project)
}

@MainActor
@Suite struct MenuBarListTests {
    private let fleet = [
        box("api", project: "shop"), box("db", project: "shop"), box("worker", project: "shop", running: false),
        box("web", project: "blog"), box("mailpit"), box("nginx", running: false),
    ]

    @Test func withoutFavoritesItListsTheFirstNAToZGroupedByProject() {
        let list = MenuBarList.make(containers: fleet, favorites: ContainerFavorites(), limit: 4)
        #expect(list.kind == .containers)
        // A to Z: api, db, mailpit, nginx — then grouped: projects A to Z, standalone last.
        #expect(list.groups.map(\.name) == ["shop", "Standalone"])
        #expect(list.groups.map { $0.containers.map(\.name) } == [["api", "db"], ["mailpit", "nginx"]])
        #expect(list.shownCount == 4)
    }

    @Test func allShowsEveryContainer() {
        let list = MenuBarList.make(containers: fleet, favorites: ContainerFavorites(), limit: nil)
        #expect(list.shownCount == 6)
        #expect(list.groups.map(\.name) == ["blog", "shop", "Standalone"])
    }

    @Test func runningFavoritesReplaceTheListAndAStarredProjectCountsAllItsContainers() {
        var favorites = ContainerFavorites()
        favorites.toggle(project: "shop")
        favorites.toggle(container: "mailpit")
        favorites.toggle(container: "nginx") // stopped: not shown
        let list = MenuBarList.make(containers: fleet, favorites: favorites, limit: 4)
        #expect(list.kind == .favorites)
        #expect(list.groups.map { $0.containers.map(\.name) } == [["api", "db"], ["mailpit"]])
    }

    @Test func favoritesThatAreAllStoppedFallBackToTheFirstN() {
        var favorites = ContainerFavorites()
        favorites.toggle(container: "nginx")
        let list = MenuBarList.make(containers: fleet, favorites: favorites, limit: 8)
        #expect(list.kind == .containers)
        #expect(list.shownCount == 6)
    }

    @Test func favoritesToggleAndAnswerForProjectsAndContainers() {
        var favorites = ContainerFavorites()
        favorites.toggle(project: "shop")
        #expect(favorites.contains(box("api", project: "shop")))
        #expect(favorites.isFavorite(project: "shop"))
        #expect(!favorites.contains(box("mailpit")))
        favorites.toggle(project: "shop")
        #expect(favorites.isEmpty)
    }
}

@MainActor
@Suite struct FavoritesSettingsTests {
    private func defaults() -> UserDefaults {
        let name = "coliui.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func favoritesAreKeptPerScopeAndSurviveARelaunch() {
        let store = defaults()
        let settings = AppSettings(defaults: store, loginItem: NoLoginItem())
        settings.toggleFavorite(container: "api", scope: "colima/default")
        settings.toggleFavorite(project: "shop", scope: "colima/work")

        let reloaded = AppSettings(defaults: store, loginItem: NoLoginItem())
        #expect(reloaded.favorites(scope: "colima/default").contains(box("api")))
        #expect(!reloaded.favorites(scope: "colima/default").isFavorite(project: "shop"))
        #expect(reloaded.favorites(scope: "colima/work").isFavorite(project: "shop"))
    }

    @Test func theMenuBarLimitDefaultsTo8AndIsSaved() {
        let store = defaults()
        let settings = AppSettings(defaults: store, loginItem: NoLoginItem())
        #expect(settings.menuBarLimit == .eight)
        #expect(MenuBarLimit.all.count == nil)
        settings.menuBarLimit = .all
        #expect(AppSettings(defaults: store, loginItem: NoLoginItem()).menuBarLimit == .all)
    }
}

private final class NoLoginItem: LoginItem {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
