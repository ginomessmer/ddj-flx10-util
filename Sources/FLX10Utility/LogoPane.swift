import FLX10Kit
import SwiftUI

struct LogoPane: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            if model.logoPreview == nil {
                emptyState
            } else {
                preview
            }
            Spacer(minLength: 24)
            if model.isConnected && !model.logoInterfaceAvailable {
                interfaceNotice
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(12)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, LogoImageEncoder.isSupported(url) else { return false }
            model.loadImage(from: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.chooseImage()
                } label: {
                    Label("Choose Image", systemImage: "photo.badge.plus")
                }
                .help("Choose an image (⌘O)")
                .disabled(model.isLogoBusy)

                Button {
                    model.isConfirmingLogoRemoval = true
                } label: {
                    Label("Remove Logo from Controller", systemImage: "trash")
                }
                .help("Remove the logo stored on the \(DeviceIdentity.displayName)")
                .disabled(!model.canDeleteLogo)
            }
        }
        .confirmationDialog(
            "Remove the logo from the \(DeviceIdentity.displayName)?",
            isPresented: $model.isConfirmingLogoRemoval
        ) {
            Button("Remove Logo", role: .destructive) { model.deleteLogo() }
        } message: {
            Text("The image saved on the controller will be deleted.")
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add Your DJ Logo", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Drag an image here or choose one. It’s shown on the jog displays when DJ LOGO DISPLAY is turned on.")
        } actions: {
            Button("Choose Image…") { model.chooseImage() }
                .controlSize(.large)
        }
        .frame(maxWidth: 420)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 18) {
            ZStack {
                if let image = model.logoPreview {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                }
                activityOverlay
            }
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .contextMenu {
                Button("Choose Another Image…") { model.chooseImage() }
                Button("Clear") { model.clearImage() }
            }
            .accessibilityLabel("Logo preview")

            VStack(spacing: 3) {
                Text(model.logoFileName ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: 320)

            HStack(spacing: 10) {
                Button("Choose Another…") { model.chooseImage() }
                    .disabled(model.isLogoBusy)
                Button {
                    model.sendLogo()
                } label: {
                    Text("Send to \(DeviceIdentity.displayName)")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSendLogo)
            }
            .controlSize(.large)

            Text(model.isConnected ? " " : "Connect the \(DeviceIdentity.displayName) to send the logo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: model.logoActivity)
    }

    private var detailText: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.logoJPEG?.count ?? 0), countStyle: .file)
        return "\(LogoProtocol.displaySize) × \(LogoProtocol.displaySize) JPEG · \(size)"
    }

    @ViewBuilder
    private var activityOverlay: some View {
        switch model.logoActivity {
        case .idle:
            EmptyView()
        case .transferring(let progress):
            overlayCard {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                Text("Sending… \(Int(progress * 100))%")
                    .monospacedDigit()
            }
        case .deleting:
            overlayCard {
                ProgressView().controlSize(.large)
                Text("Removing…")
            }
        case .succeeded(let message):
            overlayCard {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: message)
                Text(message)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func overlayCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10, content: content)
            .font(.callout.weight(.medium))
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
    }

    private var interfaceNotice: some View {
        Label("The logo can’t be sent right now. Quit other DJ apps using the controller, then reconnect it.", systemImage: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.yellow.opacity(0.12))
    }
}

#Preview("Empty") {
    LogoPane()
        .environment(AppModel.preview())
        .frame(width: 560, height: 520)
}

#Preview("Ready to send") {
    LogoPane()
        .environment(AppModel.preview(withLogo: true))
        .frame(width: 560, height: 520)
}

#Preview("Sending") {
    LogoPane()
        .environment(AppModel.preview(withLogo: true).previewActivity(.transferring(progress: 0.42)))
        .frame(width: 560, height: 520)
}

#Preview("Sent") {
    LogoPane()
        .environment(AppModel.preview(withLogo: true).previewActivity(.succeeded("Sent to DDJ-FLX10")))
        .frame(width: 560, height: 520)
}

#Preview("Not connected") {
    LogoPane()
        .environment(AppModel.preview(connected: false, withLogo: true))
        .frame(width: 560, height: 520)
}
