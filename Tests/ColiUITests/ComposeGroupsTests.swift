import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private let fleet = [
    Container(id: "w", name: "shop-worker-1", image: "myapp/worker", state: .exited, status: "Exited (1)",
              composeProject: "shop", composeService: "worker", composeConfigFile: "/code/shop/docker-compose.yml"),
    Container(id: "a", name: "shop-api-1", image: "myapp/api", state: .running, status: "Up",
              composeProject: "shop", composeService: "api", composeConfigFile: "/code/shop/docker-compose.yml"),
    Container(id: "m", name: "mailpit", image: "axllent/mailpit", state: .running, status: "Up"),
    Container(id: "g", name: "blog-ghost-1", image: "ghost:5", state: .exited, status: "Exited (0)",
              composeProject: "blog", composeService: "ghost", composeConfigFile: "/code/blog/compose.yaml"),
]

@MainActor
@Suite struct ComposeGroupsTests {
    /// Searching by Compose service finds the container in the list view too, not only in the grouped view.
    @Test func listSearchAlsoMatchesTheComposeService() async {
        let web = Container(id: "f", name: "shop-1", image: "nginx", state: .running, status: "Up",
                            composeProject: "shop", composeService: "frontend", composeConfigFile: "/code/shop/compose.yaml")
        let model = ContainersViewModel(repository: FakeContainerRepository([web]))
        await model.refresh()
        model.viewMode = .list
        model.searchText = "frontend"
        #expect(model.visibleContainers.map(\.id) == ["f"])
    }

    @Test func composeGroupsIsTheDefaultView() {
        #expect(ContainersViewModel(repository: FakeContainerRepository(fleet)).viewMode == .compose)
    }

    @Test func groupsByProjectWithStandaloneLast() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(fleet))
        await model.refresh()

        let groups = model.composeGroups
        #expect(groups.map(\.name) == ["blog", "shop", "Standalone containers"])
        #expect(groups[1].configFile == "/code/shop/docker-compose.yml")
        #expect(groups[1].containers.map(\.composeService) == ["api", "worker"])
        #expect(groups[1].runningCount == 1)
        #expect(groups[2].isStandalone)
        #expect(groups[2].containers.map(\.name) == ["mailpit"])
    }

    @Test func searchHidesGroupsWithoutMatches() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(fleet))
        await model.refresh()

        model.searchText = "api"
        #expect(model.composeGroups.map(\.name) == ["shop"])
        #expect(model.composeGroups[0].containers.map(\.id) == ["a"])
    }

    @Test func groupsIgnoreTheStateFilterOfTheListView() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(fleet))
        await model.refresh()

        model.filter = .running
        #expect(model.composeGroups.flatMap(\.containers).count == 4)
    }

    @Test func stopAllStopsOnlyRunningMembers() async {
        let repository = FakeContainerRepository(fleet)
        let model = ContainersViewModel(repository: repository)
        await model.refresh()

        let shop = model.composeGroups[1]
        await model.perform(.stopAll, on: shop)
        #expect(repository.actions.filter { !$0.hasPrefix("stats") } == ["stop a"])
    }

    @Test func startAllStartsOnlyStoppedMembers() async {
        let repository = FakeContainerRepository(fleet)
        let model = ContainersViewModel(repository: repository)
        await model.refresh()

        await model.perform(.startAll, on: model.composeGroups[1])
        #expect(repository.actions.filter { !$0.hasPrefix("stats") } == ["start w"])
    }

    @Test func restartRestartsEveryMember() async {
        let repository = FakeContainerRepository(fleet)
        let model = ContainersViewModel(repository: repository)
        await model.refresh()

        await model.perform(.restart, on: model.composeGroups[1])
        #expect(Set(repository.actions.filter { !$0.hasPrefix("stats") }) == ["restart a", "restart w"])
    }

    @Test func togglingAGroupCollapsesAndExpandsIt() async {
        let model = ContainersViewModel(repository: FakeContainerRepository(fleet))
        await model.refresh()

        let id = model.composeGroups[0].id
        model.toggleGroup(id)
        #expect(model.collapsedGroups.contains(id))
        model.toggleGroup(id)
        #expect(!model.collapsedGroups.contains(id))
    }

    @Test func copyShowsAToastThatClears() async throws {
        let model = ContainersViewModel(repository: FakeContainerRepository(fleet), toastDuration: .milliseconds(20))
        model.showToast("Copied docker exec -it a sh")
        #expect(model.toast == "Copied docker exec -it a sh")
        // Wait for the clear instead of a fixed sleep: CI runners can be slower than 80 ms.
        let deadline = ContinuousClock.now + .seconds(2)
        while model.toast != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.toast == nil)
    }
}
