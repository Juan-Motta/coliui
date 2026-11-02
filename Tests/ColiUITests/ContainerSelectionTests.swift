import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private let shopAPI = Container(id: "a", name: "api", image: "api", state: .running, status: "Up",
                                ports: [PortMapping(privatePort: 80, publicPort: 8080, proto: "tcp")],
                                composeProject: "shop", composeService: "api")
private let shopDB = Container(id: "d", name: "db", image: "pg", state: .exited, status: "Exited (0)",
                               composeProject: "shop", composeService: "db")
private let mail = Container(id: "m", name: "mailpit", image: "mail", state: .running, status: "Up")

@MainActor
private func loadedModel() async -> (ContainersViewModel, FakeContainerRepository) {
    let repository = FakeContainerRepository([mail, shopDB, shopAPI])
    let model = ContainersViewModel(repository: repository)
    await model.refresh()
    return (model, repository)
}

@MainActor
@Suite struct ContainerSelectionTests {
    @Test func arrowsWalkTheComposeOrderAndSkipCollapsedGroups() async {
        let (model, _) = await loadedModel()
        #expect(model.navigationOrder.map(\.id) == ["a", "d", "m"])
        model.selectNext()
        #expect(model.selectedID == "a")
        model.selectNext()
        model.selectNext()
        model.selectNext()
        #expect(model.selectedID == "m")
        model.selectPrevious()
        #expect(model.selectedID == "d")

        model.toggleGroup("shop")
        #expect(model.navigationOrder.map(\.id) == ["m"])
    }

    @Test func listViewFollowsItsFilterAndSort() async {
        let (model, _) = await loadedModel()
        model.viewMode = .list
        model.filter = .running
        #expect(model.navigationOrder.map(\.id) == ["a", "m"])
        model.selectPrevious()
        #expect(model.selectedID == "m")
    }

    @Test func spaceStartsOrStopsTheSelection() async {
        let (model, repository) = await loadedModel()
        model.selectedID = "a"
        await model.toggleSelected()
        model.selectedID = "d"
        await model.toggleSelected()
        #expect(repository.actions == ["stop a", "start d"])
    }

    @Test func removeAsksForConfirmation() async {
        let (model, repository) = await loadedModel()
        model.selectedID = "m"
        model.requestRemoveSelected()
        #expect(model.pendingRemoval == mail)
        #expect(repository.actions.isEmpty)
    }

    @Test func portURLOfTheSelection() async {
        let (model, _) = await loadedModel()
        model.selectedID = "a"
        #expect(model.selectedPortURL == URL(string: "http://localhost:8080"))
        model.selectedID = "m"
        #expect(model.selectedPortURL == nil)
    }

    @Test func selectionClearsWhenTheContainerDisappears() async {
        let (model, repository) = await loadedModel()
        model.selectedID = "m"
        repository.setContainers([shopAPI])
        await model.refresh()
        #expect(model.selectedID == nil)
        #expect(model.selectedContainer == nil)
    }
}
