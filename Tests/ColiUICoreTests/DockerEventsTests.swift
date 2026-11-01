import Foundation
import Testing
@testable import ColiUICore

@Suite struct DockerEventDecoderTests {
    @Test func skipsHeadersAndCountsOneEventPerJSONLine() {
        var decoder = DockerEventDecoder()
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
        #expect(decoder.feed(Data(head.utf8)) == 0)
        let chunk = "5a\r\n{\"Type\":\"container\",\"Action\":\"start\",\"id\":\"abc\"}\n\r\n"
        #expect(decoder.feed(Data(chunk.utf8)) == 1)
    }

    @Test func handlesEventsSplitAcrossReads() {
        var decoder = DockerEventDecoder()
        _ = decoder.feed(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        #expect(decoder.feed(Data("40\r\n{\"Type\":\"cont".utf8)) == 0)
        #expect(decoder.feed(Data("ainer\",\"Action\":\"die\"}\n\r\n40\r\n{\"Type\":\"container\"}\n\r\n".utf8)) == 2)
    }

    @Test func headersSplitAcrossReadsAreStillSkipped() {
        var decoder = DockerEventDecoder()
        #expect(decoder.feed(Data("HTTP/1.1 200 OK\r\nTransfer-Enc".utf8)) == 0)
        #expect(decoder.feed(Data("oding: chunked\r\n\r\n{\"Type\":\"container\"}\n".utf8)) == 1)
    }

    @Test func eventsPathFiltersContainerEvents() {
        #expect(DockerEvents.containerEventsPath == "/events?filters=%7B%22type%22%3A%5B%22container%22%5D%7D")
    }
}
