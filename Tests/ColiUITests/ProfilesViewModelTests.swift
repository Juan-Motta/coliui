import ColiUICore
import Foundation
import Testing
@testable import ColiUI

private let defaultSettings = ColimaProfileSettings(
    cpus: 4, memoryGiB: 8, diskGiB: 60, vmType: "vz", mountType: "virtiofs", rosetta: true, runtime: "docker"
)
private let workSettings = ColimaProfileSettings(
    cpus: 6, memoryGiB: 12, diskGiB: 100, vmType: "vz", mountType: "virtiofs", rosetta: false, runtime: "docker"
)

@MainActor
private func makeModel() -> (ProfilesViewModel, FakeColimaRuntime) {
    let runtime = FakeColimaRuntime([
        ColimaInstance(name: "work", status: .stopped, arch: "aarch64", cpus: 6, memoryBytes: 12 << 30, diskBytes: 100 << 30, runtime: "docker"),
        ColimaInstance(name: "default", status: .running, arch: "aarch64", cpus: 4, memoryBytes: 8 << 30, diskBytes: 60 << 30, runtime: "docker", vmType: "vz"),
    ])
    runtime.settingsByProfile = ["default": defaultSettings, "work": workSettings]
    return (ProfilesViewModel(runtime: runtime, activeProfile: "default"), runtime)
}

@MainActor
@Suite struct ProfilesViewModelTests {
    @Test func loadListsActiveFirstAndSelectsIt() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.profiles.map(\.name) == ["default", "work"])
        #expect(model.selectedName == "default")
        #expect(model.draft == defaultSettings)
        #expect(model.runningCount == 1)
        #expect(!model.isDirty)
    }

    @Test func editingMarksDirtyAndRevertRestores() async {
        let (model, _) = makeModel()
        await model.load()
        model.draft.cpus = 6
        #expect(model.isDirty)
        model.revert()
        #expect(model.draft == defaultSettings)
        #expect(!model.isDirty)
    }

    @Test func diskCanOnlyGrow() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.minimumDisk == 60)
        model.startNewProfile()
        #expect(model.minimumDisk == 20)
    }

    @Test func applyingARunningProfileAsksFirst() async {
        let (model, runtime) = makeModel()
        await model.load()
        model.draft.cpus = 6

        await model.requestApply()
        #expect(model.confirmingApply)
        #expect(runtime.commands.isEmpty)

        await model.apply()
        #expect(runtime.commands == ["apply default cpus=6 running=true"])
        #expect(model.operation == nil)
    }

    @Test func applyingAStoppedProfileRunsRightAway() async {
        let (model, runtime) = makeModel()
        await model.load()
        await model.select("work")
        model.draft.cpus = 8

        await model.requestApply()
        #expect(!model.confirmingApply)
        #expect(runtime.commands == ["apply work cpus=8 running=false"])
    }

    @Test(arguments: [
        ("", "Enter a name."),
        ("Bad Name", "Use lowercase letters, digits and “-”."),
        ("work", "A profile named “work” already exists."),
    ])
    func newProfileNamesAreValidated(name: String, message: String) async {
        let (model, runtime) = makeModel()
        await model.load()
        model.startNewProfile()
        model.newName = name
        #expect(model.nameError == message)
        await model.create()
        #expect(runtime.commands.isEmpty)
    }

    @Test func createsAProfileWithTheChosenVMType() async {
        let (model, runtime) = makeModel()
        await model.load()
        model.startNewProfile()
        model.newName = "x86-legacy"
        model.draft.vmType = "qemu"
        await model.create()
        #expect(runtime.commands == ["create x86-legacy qemu"])
        #expect(!model.isCreating)
    }

    @Test func deleteRemovesTheProfile() async {
        let (model, runtime) = makeModel()
        await model.load()
        await model.select("work")
        await model.delete()
        #expect(runtime.commands == ["delete work"])
    }

    @Test func commandFailuresAreShown() async {
        let (model, runtime) = makeModel()
        runtime.commandError = ColimaError.commandFailed("error starting vm: insufficient memory")
        await model.load()
        await model.select("work")
        await model.apply()
        #expect(model.errorMessage == "error starting vm: insufficient memory")
        #expect(model.operation == nil)
    }
}
