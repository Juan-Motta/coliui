import SwiftUI

extension View {
    /// RunContainer.dc.html dialog: frosted near-white card, 26 pt corners, deep shadow.
    func modalSurface() -> some View {
        background(Palette.modalSurface, in: .rect(cornerRadius: 26))
            .clipShape(.rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.glassBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 35, y: 15)
    }
}

/// A create modal: title and one-line help, its fields, then Cancel / the primary action.
struct ModalPanel<Fields: View, Actions: View>: View {
    let title: String
    let lede: String
    var width: CGFloat = 460
    @ViewBuilder let fields: Fields
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(17, .semibold))
                Text(lede).font(.ui(12)).foregroundStyle(Palette.secondary)
            }
            fields
            HStack(spacing: 8) {
                Spacer()
                actions
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(width: width)
        .modalSurface()
    }
}

/// `.lbl` + `.in.mono`: a caption over a 30 pt monospaced field.
struct ModalTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.ui(12)).foregroundStyle(Palette.tertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.mono(12))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Palette.field, in: .rect(cornerRadius: 10))
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .onAppear { focused = true }
    }
}

/// Shows the open modal (a create form or the update) over the whole window (sidebar included); a click outside closes it.
struct ModalHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let modal = model.presentedModal {
            ZStack(alignment: .top) {
                Palette.modalBackdrop
                    .contentShape(.rect)
                    .onTapGesture { model.dismissModal() }
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                Group {
                    switch modal {
                    case .run(let form): RunContainerSheet(form: form).modalSurface()
                    case .pullImage: PullImageModal()
                    case .newVolume: NewVolumeModal()
                    case .newNetwork: NewNetworkModal()
                    case .newProfile: NewProfileModal()
                    case .update: UpdateModal()
                    }
                }
                .padding(.top, modal.isTall ? 28 : 110)
                .padding(.horizontal, 16)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .ignoresSafeArea()
        }
    }
}
