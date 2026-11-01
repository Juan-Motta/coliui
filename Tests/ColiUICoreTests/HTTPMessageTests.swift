import Foundation
import Testing
@testable import ColiUICore

@Suite struct HTTPMessageTests {
    @Test func buildsRequestWithCloseAndContentLength() {
        let raw = HTTPMessage.request(method: "POST", path: "/containers/abc/start", body: Data("{}".utf8))
        let text = String(decoding: raw, as: UTF8.self)
        #expect(text.hasPrefix("POST /containers/abc/start HTTP/1.1\r\n"))
        #expect(text.contains("Host: localhost\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{}"))
    }

    @Test func buildsBodylessRequestWithZeroLength() {
        let text = String(decoding: HTTPMessage.request(method: "GET", path: "/version", body: nil), as: UTF8.self)
        #expect(text.contains("Content-Length: 0\r\n"))
        #expect(!text.contains("Content-Type"))
    }

    @Test func parsesContentLengthResponse() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n[]trailing".utf8)
        let response = try HTTPMessage.parseResponse(raw)
        #expect(response.statusCode == 200)
        #expect(response.headers["content-type"] == "application/json")
        #expect(response.body == Data("[]".utf8))
    }

    @Test func parsesChunkedResponse() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n".utf8)
        let response = try HTTPMessage.parseResponse(raw)
        #expect(String(decoding: response.body, as: UTF8.self) == "Wikipedia")
    }

    @Test func parsesNoContentResponse() throws {
        let response = try HTTPMessage.parseResponse(Data("HTTP/1.1 204 No Content\r\n\r\n".utf8))
        #expect(response.statusCode == 204)
        #expect(response.body.isEmpty)
    }

    @Test func rejectsMalformedResponse() {
        #expect(throws: DockerError.malformedResponse) {
            try HTTPMessage.parseResponse(Data("garbage".utf8))
        }
        #expect(throws: DockerError.malformedResponse) {
            try HTTPMessage.parseResponse(Data("HTTP/1.1 abc\r\n\r\n".utf8))
        }
    }
}
