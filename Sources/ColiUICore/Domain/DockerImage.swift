import Foundation

/// One row of `docker images`: an image under one of its tags, or an untagged (dangling) image.
public struct DockerImage: Identifiable, Sendable, Equatable {
    public let imageID: String
    /// `<none>` when dangling.
    public let repository: String
    public let tag: String
    public let created: Date
    public let size: Int64

    public init(imageID: String, repository: String, tag: String, created: Date, size: Int64) {
        self.imageID = imageID
        self.repository = repository
        self.tag = tag
        self.created = created
        self.size = size
    }

    public var id: String { "\(imageID) \(repository):\(tag)" }
    public var isDangling: Bool { repository == "<none>" }
    /// "sha256:4be1c0", like the designs.
    public var shortID: String { "sha256:" + hex.prefix(6) }
    /// What `docker rmi` takes: the tag, so other tags of the same image survive; the ID when untagged.
    public var reference: String { isDangling ? hex : "\(repository):\(tag)" }

    private var hex: String { imageID.hasPrefix("sha256:") ? String(imageID.dropFirst(7)) : imageID }
}

public struct PullProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case waiting, downloading, extracting, done }

    public let phase: Phase
    /// 0...1 across every layer of the current phase; nil before sizes are known.
    public let fraction: Double?

    public init(phase: Phase, fraction: Double?) {
        self.phase = phase
        self.fraction = fraction
    }

    public var title: String {
        let percent = fraction.map { " \(Int(($0 * 100).rounded()))%" } ?? ""
        return switch phase {
        case .waiting: "Pulling…"
        case .downloading: "Downloading" + percent
        case .extracting: "Extracting" + percent
        case .done: "Pulled"
        }
    }
}

/// Folds the JSON lines of `POST /images/create` into one overall progress value.
public struct PullProgressTracker {
    private struct Layer { var current: Int64 = 0; var total: Int64 = 0 }
    private var downloads: [String: Layer] = [:]
    private var extracts: [String: Layer] = [:]
    private var phase = PullProgress.Phase.waiting

    public init() {}

    public mutating func feed(_ line: String) throws -> PullProgress {
        guard let event = try? JSONDecoder().decode(PullEventDTO.self, from: Data(line.utf8)) else {
            return current
        }
        if let error = event.error {
            throw DockerError.requestFailed(status: 200, message: error)
        }
        let status = event.status ?? ""
        let layerID = event.id ?? ""
        let detail = event.progressDetail
        switch status {
        case "Downloading":
            if let total = detail?.total, total > 0 {
                downloads[layerID] = Layer(current: detail?.current ?? 0, total: total)
            }
            if phase == .waiting { phase = .downloading }
        case "Download complete", "Verifying Checksum":
            if var layer = downloads[layerID] { layer.current = layer.total; downloads[layerID] = layer }
        case "Extracting":
            if let total = detail?.total, total > 0 {
                extracts[layerID] = Layer(current: detail?.current ?? 0, total: total)
            }
            phase = .extracting
        case "Pull complete":
            if var layer = extracts[layerID] { layer.current = layer.total; extracts[layerID] = layer }
        default:
            // "Status: Downloaded newer image for …" / "Status: Image is up to date for …"
            if status.hasPrefix("Status:") { phase = .done }
        }
        return current
    }

    private var current: PullProgress {
        let layers = phase == .extracting ? extracts : downloads
        let total = layers.values.reduce(0) { $0 + $1.total }
        let done = layers.values.reduce(0) { $0 + $1.current }
        let fraction = phase == .done ? 1 : total > 0 ? Double(done) / Double(total) : nil
        return PullProgress(phase: phase, fraction: fraction)
    }
}

private struct PullEventDTO: Decodable {
    struct Detail: Decodable { let current: Int64?; let total: Int64? }
    let status: String?
    let id: String?
    let progressDetail: Detail?
    let error: String?
}

/// "12 min ago", "2 hours ago", "3 weeks ago" — the CREATED column.
public enum ImageAge {
    public static func text(for date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        let days = seconds / 86_400
        func plural(_ value: Int, _ unit: String) -> String { "\(value) \(unit)\(value == 1 ? "" : "s") ago" }
        return switch seconds {
        case ..<60: "just now"
        case ..<3600: "\(seconds / 60) min ago"
        case ..<86_400: plural(seconds / 3600, "hour")
        case _ where days < 7: plural(days, "day")
        case _ where days < 30: plural(days / 7, "week")
        case _ where days < 365: plural(days / 30, "month")
        default: plural(days / 365, "year")
        }
    }
}
