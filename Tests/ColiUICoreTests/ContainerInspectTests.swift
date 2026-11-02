import Foundation
import Testing
@testable import ColiUICore

private func response(_ status: Int, _ body: String = "") -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

@Suite struct JSONValueTests {
    @Test func keepsKeyOrderAndTypes() throws {
        let value = try JSONValue.parse(Data(#"{"Id":"abc","State":{"Running":true,"Pid":42,"Error":null},"Args":["a",1.5,-2e3]}"#.utf8))

        #expect(value == .object([
            JSONMember(key: "Id", value: .string("abc")),
            JSONMember(key: "State", value: .object([
                JSONMember(key: "Running", value: .bool(true)),
                JSONMember(key: "Pid", value: .number("42")),
                JSONMember(key: "Error", value: .null),
            ])),
            JSONMember(key: "Args", value: .array([.string("a"), .number("1.5"), .number("-2e3")])),
        ]))
    }

    @Test func decodesEscapes() throws {
        let value = try JSONValue.parse(Data(#"["a\"b\\c\/d\n\té😀"]"#.utf8))
        #expect(value == .array([.string("a\"b\\c/d\n\té😀")]))
    }

    @Test(arguments: ["", "{", #"{"a" 1}"#, "[1,]", "tru", #""open"#, "[1] 2"])
    func rejectsMalformedJSON(_ text: String) {
        #expect(throws: DockerError.malformedResponse) { try JSONValue.parse(Data(text.utf8)) }
    }

    @Test func printsLikeDockerInspect() throws {
        let value = try JSONValue.parse(Data(#"{"Id":"a\"b","Args":[],"Labels":{},"Ports":{"80/tcp":[{"HostPort":"8080"}]},"Tty":false,"Pid":7,"X":null}"#.utf8))
        #expect(value.prettyPrinted() == """
        {
          "Id": "a\\"b",
          "Args": [],
          "Labels": {},
          "Ports": {
            "80/tcp": [
              {
                "HostPort": "8080"
              }
            ]
          },
          "Tty": false,
          "Pid": 7,
          "X": null
        }
        """)
    }
}

@Suite struct SecretMaskTests {
    @Test(arguments: ["DATABASE_PASSWORD", "MYSQL_ROOT_PASSWD", "api_secret", "GITHUB_TOKEN", "AWS_ACCESS_KEY_ID",
                      "GOOGLE_APPLICATION_CREDENTIALS", "BASIC_AUTH", "PRIVATE_KEY_PEM"])
    func masksSecretNames(_ name: String) {
        #expect(SecretMask.masked("\(name)=hunter2") == "\(name)=••••••")
    }

    @Test(arguments: ["PATH=/usr/bin", "NODE_ENV=production", "PORT=8080", "HOSTNAME=web"])
    func keepsOrdinaryValues(_ entry: String) {
        #expect(SecretMask.masked(entry) == entry)
    }

    @Test func masksURLsWithAPassword() {
        #expect(SecretMask.masked("DATABASE_URL=postgres://app:s3cret@db:5432/shop") == "DATABASE_URL=••••••")
        #expect(SecretMask.masked("REDIS_URL=redis://cache:6379") == "REDIS_URL=redis://cache:6379")
    }

    @Test func leavesEntriesWithoutAValueAlone() {
        #expect(SecretMask.masked("API_TOKEN") == "API_TOKEN")
        #expect(SecretMask.masked("API_TOKEN=") == "API_TOKEN=")
    }
}

@Suite struct ContainerInspectTests {
    @Test func inspectsAndMasksEnvSecrets() async throws {
        let body = #"{"Id":"c1","Config":{"Env":["PATH=/bin","DB_PASSWORD=x"],"Image":"web"},"Env":["TOKEN=keep-outside-config"]}"#
        let transport = FakeTransport(response: response(200, body))
        let value = try await DockerEngineRepository(transport: transport).inspect(id: "c1")

        #expect(transport.calls == [.init(method: "GET", path: "/containers/c1/json")])
        #expect(value == .object([
            JSONMember(key: "Id", value: .string("c1")),
            JSONMember(key: "Config", value: .object([
                JSONMember(key: "Env", value: .array([.string("PATH=/bin"), .string("DB_PASSWORD=••••••")])),
                JSONMember(key: "Image", value: .string("web")),
            ])),
            JSONMember(key: "Env", value: .array([.string("TOKEN=keep-outside-config")])),
        ]))
    }

    @Test func surfacesEngineErrors() async {
        let transport = FakeTransport(response: response(404, #"{"message":"No such container: c1"}"#))
        await #expect(throws: DockerError.requestFailed(status: 404, message: "No such container: c1")) {
            try await DockerEngineRepository(transport: transport).inspect(id: "c1")
        }
    }

    @Test func refusesUnsafeIDs() async {
        await #expect(throws: DockerError.invalidContainerID) {
            try await DockerEngineRepository(transport: FakeTransport(response: response(200, "{}"))).inspect(id: "../x")
        }
    }
}
