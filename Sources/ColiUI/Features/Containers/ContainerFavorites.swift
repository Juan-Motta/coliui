import ColiUICore
import Foundation

/// Favorites.dc.html: starred containers (by name) and Compose projects (all their containers count).
struct ContainerFavorites: Codable, Equatable {
    private(set) var containers: Set<String> = []
    private(set) var projects: Set<String> = []

    var isEmpty: Bool { containers.isEmpty && projects.isEmpty }

    func contains(_ container: Container) -> Bool {
        containers.contains(container.name) || container.composeProject.map(projects.contains) == true
    }

    func isFavorite(project: String) -> Bool { projects.contains(project) }

    mutating func toggle(container name: String) {
        if containers.remove(name) == nil { containers.insert(name) }
    }

    mutating func toggle(project name: String) {
        if projects.remove(name) == nil { projects.insert(name) }
    }
}
