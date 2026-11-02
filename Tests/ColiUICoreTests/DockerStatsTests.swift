import Foundation
import Testing
@testable import ColiUICore

@Suite struct DockerStatsTests {
    static let statsJSON = """
    {"cpu_stats":{"cpu_usage":{"total_usage":2000000000},"system_cpu_usage":110000000000,"online_cpus":4},
     "precpu_stats":{"cpu_usage":{"total_usage":1900000000},"system_cpu_usage":100000000000},
     "memory_stats":{"usage":104857600,"stats":{"inactive_file":14680064}}}
    """

    @Test func computesCPUAndMemoryLikeTheDockerCLI() async throws {
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(Self.statsJSON.utf8)))
        let stats = try await DockerEngineRepository(transport: transport).stats(id: "abc123")

        #expect(transport.calls == [.init(method: "GET", path: "/containers/abc123/stats?stream=false")])
        // (0.1e9 / 10e9) * 4 cores * 100 = 4 %
        #expect(abs(stats.cpuPercent - 4.0) < 0.0001)
        // usage minus inactive page cache: 100 MiB - 14 MiB
        #expect(stats.memoryBytes == 90_177_536)
        #expect(stats.cpuDisplay == "4.0%")
        #expect(stats.memoryDisplay == "86 MiB")
    }

    @Test func readsLimitsAndIOTotals() async throws {
        let json = """
        {"read":"2026-11-02T10:00:02.123456789Z",
         "cpu_stats":{"cpu_usage":{"total_usage":2},"system_cpu_usage":4,"online_cpus":4},
         "precpu_stats":{"cpu_usage":{"total_usage":1},"system_cpu_usage":2},
         "memory_stats":{"usage":2048,"limit":1073741824},
         "networks":{"eth0":{"rx_bytes":1000,"tx_bytes":400},"eth1":{"rx_bytes":24,"tx_bytes":6}},
         "blkio_stats":{"io_service_bytes_recursive":[
           {"major":254,"minor":0,"op":"read","value":5000},{"major":254,"minor":0,"op":"write","value":700},
           {"major":254,"minor":16,"op":"Read","value":100},{"major":254,"minor":0,"op":"discard","value":9}]}}
        """
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let stats = try await DockerEngineRepository(transport: transport).stats(id: "abc")
        #expect(stats.onlineCPUs == 4)
        #expect(stats.memoryLimit == 1_073_741_824)
        #expect(stats.networkReceived == 1024)
        #expect(stats.networkSent == 406)
        #expect(stats.blockRead == 5100)
        #expect(stats.blockWritten == 700)
        let expected = ISO8601DateFormatter().date(from: "2026-11-02T10:00:02Z")!.addingTimeInterval(0.123)
        #expect(abs((stats.sampledAt ?? .distantPast).timeIntervalSince(expected)) < 0.001)
    }

    @Test func missingIOSectionsReadAsZero() async throws {
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(Self.statsJSON.utf8)))
        let stats = try await DockerEngineRepository(transport: transport).stats(id: "abc")
        #expect(stats.networkReceived == 0)
        #expect(stats.blockRead == 0)
        #expect(stats.memoryLimit == nil)
        #expect(stats.sampledAt == nil)
    }

    @Test func idleContainerReportsZeroCPU() async throws {
        let json = """
        {"cpu_stats":{"cpu_usage":{"total_usage":5},"system_cpu_usage":10,"online_cpus":2},
         "precpu_stats":{"cpu_usage":{"total_usage":5},"system_cpu_usage":10},
         "memory_stats":{"usage":2048}}
        """
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8)))
        let stats = try await DockerEngineRepository(transport: transport).stats(id: "abc")
        #expect(stats.cpuPercent == 0)
        #expect(stats.memoryBytes == 2048)
    }

    @Test func formatsLargeMemoryInGiB() {
        #expect(ContainerStats(cpuPercent: 12.345, memoryBytes: 1_610_612_736).memoryDisplay == "1.5 GiB")
        #expect(ContainerStats(cpuPercent: 12.345, memoryBytes: 0).cpuDisplay == "12.3%")
    }
}

@Suite struct DockerSummaryTests {
    final class RoutingTransport: HTTPTransport, @unchecked Sendable {
        let routes: [String: String]
        init(_ routes: [String: String]) { self.routes = routes }
        func send(method: String, path: String, body: Data?) async throws -> HTTPResponse {
            HTTPResponse(statusCode: 200, headers: [:], body: Data((routes[path] ?? "").utf8))
        }
    }

    @Test func countsImagesVolumesAndNetworks() async throws {
        let transport = RoutingTransport([
            "/images/json": #"[{"Id":"a"},{"Id":"b"},{"Id":"c"}]"#,
            "/volumes": #"{"Volumes":[{"Name":"pgdata"}],"Warnings":null}"#,
            "/networks": #"[{"Name":"bridge"},{"Name":"host"}]"#,
        ])
        let summary = try await DockerEngineRepository(transport: transport).summary()
        #expect(summary == DockerSummary(images: 3, volumes: 1, networks: 2))
    }

    @Test func nullVolumesListCountsAsZero() async throws {
        let transport = RoutingTransport([
            "/images/json": "[]",
            "/volumes": #"{"Volumes":null,"Warnings":null}"#,
            "/networks": "[]",
        ])
        #expect(try await DockerEngineRepository(transport: transport).summary() == DockerSummary(images: 0, volumes: 0, networks: 0))
    }
}
