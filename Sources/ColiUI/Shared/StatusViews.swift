import ColiUICore
import SwiftUI

struct StatusBadge: View {
    let title: String
    let tint: Color
    var isBusy = false

    var body: some View {
        HStack(spacing: 5) {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isBusy ? .secondary : tint)
    }
}

extension ColimaViewModel {
    var statusTitle: String {
        if let pendingAction { return pendingAction.progressTitle }
        guard let instance else { return "Unavailable" }
        return switch instance.status {
        case .running: "Running"
        case .stopped: "Stopped"
        case .other(let raw): raw.capitalized
        }
    }

    var statusTint: Color { isRunning ? Palette.greenDot : Palette.grayDot }
}

extension Container {
    private var failed: Bool {
        switch state {
        case .restarting, .dead: true
        case .exited: !status.contains("(0)")
        default: false
        }
    }

    /// Dot colour: green running, orange failed exit, grey otherwise.
    var statusTint: Color {
        isRunning ? Palette.greenDot : failed ? Palette.orangeDot : Palette.grayDot
    }

    var statusTextColor: Color {
        isRunning ? Palette.greenText : failed ? Palette.orangeText : Palette.secondary
    }
}

struct ContainerStatusLabel: View {
    let container: Container

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(container.statusTint).frame(width: 8, height: 8)
            Text(container.status)
                .foregroundStyle(container.statusTextColor)
                .lineLimit(1)
        }
        .font(.ui(12, .medium))
    }
}
