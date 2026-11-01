import Foundation

public struct ContainerMount: Sendable, Hashable {
    public let source: String
    public let destination: String

    public init(source: String, destination: String) {
        self.source = source
        self.destination = destination
    }
}

/// What `docker inspect` adds on top of the list entry.
public struct ContainerDetails: Sendable, Equatable {
    public let id: String
    public let name: String
    public let image: String
    public let created: Date?
    public let restartPolicy: String
    public let network: String?
    public let ipAddress: String?
    public let mounts: [ContainerMount]
    public let environment: [String]
    /// TTY containers stream raw logs; the rest use the multiplexed format.
    public let tty: Bool

    public init(
        id: String, name: String, image: String, created: Date?, restartPolicy: String,
        network: String?, ipAddress: String?, mounts: [ContainerMount], environment: [String], tty: Bool
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.created = created
        self.restartPolicy = restartPolicy
        self.network = network
        self.ipAddress = ipAddress
        self.mounts = mounts
        self.environment = environment
        self.tty = tty
    }
}

public enum LogLevel: String, Sendable, Equatable {
    case debug, info, warn, error
}

public enum LogStreamKind: Sendable, Equatable {
    case stdout, stderr
}

public struct LogLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let timestamp: Date?
    public let level: LogLevel?
    public let message: String
    public let stream: LogStreamKind

    public init(id: Int, timestamp: Date?, level: LogLevel?, message: String, stream: LogStreamKind) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.stream = stream
    }
}
