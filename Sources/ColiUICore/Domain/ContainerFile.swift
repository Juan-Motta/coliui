import Foundation

/// One entry of a folder inside a container.
public struct ContainerFile: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case directory, file, symlink, other
    }

    public let name: String
    public let kind: Kind
    public let size: Int64
    public let modified: Date
    /// `drwxr-xr-x`, as `ls -l` shows it.
    public let mode: String
    /// `user:group`.
    public let owner: String
    public let linkTarget: String?

    public var id: String { name }
    public var isHidden: Bool { name.hasPrefix(".") }

    public init(name: String, kind: Kind, size: Int64, modified: Date, mode: String, owner: String, linkTarget: String? = nil) {
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.mode = mode
        self.owner = owner
        self.linkTarget = linkTarget
    }

    /// Lines of `stat -c '%A\t%s\t%Y\t%U:%G\t%F\t%n\t%N'`; folders first, then by name. Unreadable lines are skipped.
    public static func parse(statOutput: String) -> [ContainerFile] {
        statOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let size = Int64(fields[1]), let seconds = TimeInterval(fields[2]), !fields[5].isEmpty else {
                return nil
            }
            let kind: Kind = switch fields[4] {
            case "directory": .directory
            case "symbolic link": .symlink
            case let type where type.hasSuffix("file"): .file
            default: .other
            }
            var target: String?
            if kind == .symlink, let arrow = fields[6].range(of: " -> ") {
                target = fields[6][arrow.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "'\"‘’`"))
            }
            // `find` prints `./name`.
            let name = fields[5].hasPrefix("./") ? String(fields[5].dropFirst(2)) : fields[5]
            return ContainerFile(name: name, kind: kind, size: size, modified: Date(timeIntervalSince1970: seconds),
                                 mode: fields[0], owner: fields[3], linkTarget: target)
        }
        .sorted { lhs, rhs in
            if (lhs.kind == .directory) != (rhs.kind == .directory) { return lhs.kind == .directory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Absolute POSIX paths inside a container.
public enum ContainerPath {
    public static func child(of folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    public static func parent(of path: String) -> String {
        let parts = components(of: path)
        return parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
    }

    public static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}

public enum ContainerFilesError: Error, Equatable, LocalizedError {
    case invalidPath
    /// Distroless and scratch images: nothing to list with.
    case noShell
    case cannotOpen(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath: "That isn't an absolute path."
        case .noShell: "This container has no shell (sh) or stat command, so its files can't be listed."
        case .cannotOpen(let path, let reason): reason.isEmpty ? "Can't open \(path)." : "Can't open \(path): \(reason)"
        }
    }
}
