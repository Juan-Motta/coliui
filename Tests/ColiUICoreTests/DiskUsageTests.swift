import Foundation
import Testing
@testable import ColiUICore

@Suite struct DiskUsageTests {
    static let dfWithUsage = """
    {"LayersSize":10301019904,
     "Images":[{"Id":"sha256:aaaaaaaaaaaa1111","RepoTags":["ksg-cx-frontend:latest"],"Size":118667740,"SharedSize":93172486,"Containers":1},
               {"Id":"sha256:bbbbbbbbbbbb2222","RepoTags":["old/tool:1.0"],"Size":500,"SharedSize":100,"Containers":0},
               {"Id":"sha256:cccccccccccc3333","RepoTags":[],"Size":300,"SharedSize":-1,"Containers":0}],
     "Containers":[{"Names":["/api"],"State":"running","SizeRw":16384},
                   {"Names":["/worker"],"State":"exited","SizeRw":4096}],
     "Volumes":[{"Name":"pgdata","UsageData":{"RefCount":1,"Size":741952795}},
                {"Name":"orphan","UsageData":{"RefCount":0,"Size":2048}}],
     "BuildCache":[{"ID":"x1","Size":1000,"InUse":false},{"ID":"x2","Size":50,"InUse":true}],
     "ImageUsage":{"TotalSize":10301019904,"Reclaimable":1744512302,"TotalCount":3,"ActiveCount":1},
     "ContainerUsage":{"TotalSize":156471296,"Reclaimable":4096,"TotalCount":2,"ActiveCount":1},
     "VolumeUsage":{"TotalSize":2023629409,"TotalCount":2,"ActiveCount":1},
     "BuildCacheUsage":{}}
    """

    static let dfLegacy = """
    {"LayersSize":900,
     "Images":[{"Id":"sha256:bbbbbbbbbbbb2222","RepoTags":["old/tool:1.0"],"Size":500,"SharedSize":100,"Containers":0}],
     "Containers":[{"Names":["/worker"],"State":"exited","SizeRw":4096}],
     "Volumes":[{"Name":"orphan","UsageData":{"RefCount":0,"Size":2048}}],
     "BuildCache":null}
    """

    private func repository(_ body: String) -> (DockerEngineRepository, FakeTransport) {
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8)))
        return (DockerEngineRepository(transport: transport), transport)
    }

    @Test func prefersTheEngineUsageTotals() async throws {
        let (repo, transport) = repository(Self.dfWithUsage)
        let usage = try await repo.diskUsage()

        #expect(transport.calls == [.init(method: "GET", path: "/system/df")])
        #expect(usage.images.totalBytes == 10_301_019_904)
        #expect(usage.images.reclaimableBytes == 1_744_512_302)
        #expect(usage.images.reclaimableItems == ["old/tool:1.0", "<none> cccccccccccc"])
        #expect(usage.containers.reclaimableBytes == 4096)
        #expect(usage.containers.reclaimableItems == ["worker"])
        #expect(usage.volumes.totalBytes == 2_023_629_409)
        #expect(usage.volumes.reclaimableBytes == 2048)
        #expect(usage.volumes.reclaimableItems == ["orphan"])
        #expect(usage.buildCache.totalBytes == 1050)
        #expect(usage.buildCache.reclaimableBytes == 1000)
        #expect(usage.buildCache.reclaimableItems.count == 1)
    }

    @Test func computesTotalsWhenTheEngineOmitsThem() async throws {
        let (repo, _) = repository(Self.dfLegacy)
        let usage = try await repo.diskUsage()

        #expect(usage.images.totalBytes == 900)
        #expect(usage.images.reclaimableBytes == 400)
        #expect(usage.containers.totalBytes == 4096)
        #expect(usage.containers.reclaimableBytes == 4096)
        #expect(usage.volumes.reclaimableBytes == 2048)
        #expect(usage.buildCache == DiskCategory(totalBytes: 0, reclaimableBytes: 0, reclaimableItems: []))
        #expect(usage.totalBytes == 900 + 4096 + 2048)
    }

    @Test(arguments: [
        (PruneTarget.images, "/images/prune?filters=%7B%22dangling%22%3A%5B%22false%22%5D%7D"),
        (PruneTarget.containers, "/containers/prune"),
        (PruneTarget.volumes, "/volumes/prune?filters=%7B%22all%22%3A%5B%22true%22%5D%7D"),
        (PruneTarget.buildCache, "/build/prune?all=1"),
    ])
    func prunesWithTheRightEndpoint(target: PruneTarget, path: String) async throws {
        let (repo, transport) = repository(#"{"SpaceReclaimed":12345,"ImagesDeleted":null}"#)
        let freed = try await repo.prune(target)
        #expect(transport.calls == [.init(method: "POST", path: path)])
        #expect(freed == 12345)
    }

    @Test func formatsByteCounts() {
        #expect(ByteFormat.short(0) == "0 B")
        #expect(ByteFormat.short(4096) == "4 KB")
        #expect(ByteFormat.short(1_744_512_302) == "1.7 GB")
        #expect(ByteFormat.short(120_000_000) == "120 MB")
    }
}
