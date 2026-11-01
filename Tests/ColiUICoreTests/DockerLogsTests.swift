import Foundation
import Testing
@testable import ColiUICore

private func frame(_ stream: UInt8, _ text: String) -> Data {
    let payload = Data(text.utf8)
    var data = Data([stream, 0, 0, 0])
    withUnsafeBytes(of: UInt32(payload.count).bigEndian) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

@Suite struct ChunkedBodyDecoderTests {
    @Test func decodesChunksSplitAcrossReads() {
        var decoder = ChunkedBodyDecoder()
        var body = Data()
        body += decoder.feed(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel".utf8))
        body += decoder.feed(Data("lo\r\n6\r\n world\r\n".utf8))
        #expect(String(decoding: body, as: UTF8.self) == "hello world")
    }

    @Test func passesThroughNonChunkedBodies() {
        var decoder = ChunkedBodyDecoder()
        var body = decoder.feed(Data("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nab".utf8))
        body += decoder.feed(Data("cd".utf8))
        #expect(String(decoding: body, as: UTF8.self) == "abcd")
    }

    @Test func reportsHTTPErrorStatus() {
        var decoder = ChunkedBodyDecoder()
        _ = decoder.feed(Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".utf8))
        #expect(decoder.statusCode == 404)
    }
}

@Suite struct DockerLogDecoderTests {
    @Test func demultiplexesFramesSplitAcrossReads() {
        var decoder = DockerLogDecoder(multiplexed: true)
        let data = frame(1, "first line\nsecond ") + frame(2, "oops\n") + frame(1, "line\n")
        var lines: [RawLogLine] = []
        lines += decoder.feed(data.prefix(5))
        lines += decoder.feed(data.dropFirst(5).prefix(20))
        lines += decoder.feed(data.dropFirst(25))
        #expect(lines == [
            RawLogLine(stream: .stdout, text: "first line"),
            RawLogLine(stream: .stderr, text: "oops"),
            RawLogLine(stream: .stdout, text: "second line"),
        ])
    }

    @Test func rawTTYStreamSplitsOnNewlinesAndStripsCarriageReturns() {
        var decoder = DockerLogDecoder(multiplexed: false)
        var lines = decoder.feed(Data("one\r\ntw".utf8))
        lines += decoder.feed(Data("o\n".utf8))
        #expect(lines == [RawLogLine(stream: .stdout, text: "one"), RawLogLine(stream: .stdout, text: "two")])
    }

    @Test func flushReturnsTrailingPartialLine() {
        var decoder = DockerLogDecoder(multiplexed: false)
        #expect(decoder.feed(Data("tail".utf8)).isEmpty)
        #expect(decoder.flush() == [RawLogLine(stream: .stdout, text: "tail")])
    }
}

@Suite struct LogLineParserTests {
    @Test func parsesDockerTimestampAndLeadingLevel() throws {
        let parsed = LogLineParser.parse("2026-11-01T10:42:01.123456789Z INFO Starting server on :8080")
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-11-01T10:42:01Z"))
        #expect(abs(try #require(parsed.timestamp).timeIntervalSince(expected) - 0.123) < 0.001)
        #expect(parsed.level == .info)
        #expect(parsed.message == "Starting server on :8080")
    }

    @Test(arguments: [
        ("[WARN] Slow query", LogLevel.warn, "Slow query"),
        ("ERROR: Job queue timeout", LogLevel.error, "Job queue timeout"),
        ("debug loaded 14 routes", LogLevel.debug, "loaded 14 routes"),
        ("warning disk almost full", LogLevel.warn, "disk almost full"),
    ])
    func recognisesLeadingLevelTokens(raw: String, level: LogLevel, message: String) {
        let parsed = LogLineParser.parse("2026-11-01T10:42:01Z " + raw)
        #expect(parsed.level == level)
        #expect(parsed.message == message)
    }

    @Test func detectsKeyValueLevelWithoutStrippingTheMessage() {
        let parsed = LogLineParser.parse("2026-11-01T10:42:01Z time=x level=error msg=\"boom\"")
        #expect(parsed.level == .error)
        #expect(parsed.message == "time=x level=error msg=\"boom\"")
    }

    @Test func plainMessagesHaveNoLevel() {
        let parsed = LogLineParser.parse("2026-11-01T10:42:01Z Hello from Docker!")
        #expect(parsed.level == nil)
        #expect(parsed.message == "Hello from Docker!")
    }

    @Test func linesWithoutTimestampKeepTheirText() {
        let parsed = LogLineParser.parse("no timestamp here")
        #expect(parsed.timestamp == nil)
        #expect(parsed.message == "no timestamp here")
    }

    @Test func buildsLogsPath() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(DockerLogs.path(id: "abc", since: since, tail: 500, follow: true)
            == "/containers/abc/logs?follow=1&stdout=1&stderr=1&timestamps=1&tail=500&since=1700000000")
        #expect(DockerLogs.path(id: "abc", since: nil, tail: 100, follow: false)
            == "/containers/abc/logs?follow=0&stdout=1&stderr=1&timestamps=1&tail=100")
    }
}

@Suite struct ContainerDetailsTests {
    static let inspectJSON = """
    {"Id":"e81b3f0c55d2aaaa","Name":"/api-server","Created":"2026-11-01T05:42:45.92449876Z",
     "Config":{"Image":"myapp/api:latest","Tty":false,"Env":["PATH=/usr/bin","DATABASE_URL=postgres://x"]},
     "HostConfig":{"RestartPolicy":{"Name":"unless-stopped","MaximumRetryCount":0}},
     "NetworkSettings":{"Networks":{"bridge":{"IPAddress":"172.17.0.4"}}},
     "Mounts":[{"Type":"bind","Source":"/Users/me/code/src","Destination":"/app/src"},
               {"Type":"volume","Name":"api-data","Source":"/var/lib/docker/volumes/api-data/_data","Destination":"/var/lib/api"}]}
    """

    @Test func mapsInspectToDetails() async throws {
        let transport = FakeTransport(response: HTTPResponse(statusCode: 200, headers: [:], body: Data(Self.inspectJSON.utf8)))
        let details = try await DockerEngineRepository(transport: transport).details(id: "e81b3f0c55d2aaaa")

        #expect(transport.calls == [.init(method: "GET", path: "/containers/e81b3f0c55d2aaaa/json")])
        #expect(details.name == "api-server")
        #expect(details.image == "myapp/api:latest")
        #expect(details.restartPolicy == "unless-stopped")
        #expect(details.network == "bridge")
        #expect(details.ipAddress == "172.17.0.4")
        #expect(details.tty == false)
        #expect(details.environment == ["PATH=/usr/bin", "DATABASE_URL=postgres://x"])
        #expect(details.mounts == [
            ContainerMount(source: "/Users/me/code/src", destination: "/app/src"),
            ContainerMount(source: "api-data", destination: "/var/lib/api"),
        ])
        #expect(details.created != nil)
    }
}
