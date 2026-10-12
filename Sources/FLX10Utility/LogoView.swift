import FLX10Kit
import SwiftUI
import UniformTypeIdentifiers

struct LogoView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var isChoosingFile = false
    @State private var isConfirmingDelete = false

    private static let allowedTypes: [UTType] = LogoImageEncoder.supportedExtensions.compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        VStack(spacing: 16) {
            Text("Shows a custom image on the jog displays when DJ LOGO DISPLAY is enabled on the controller.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            dropZone

            if let progress = model.transferProgress {
                ProgressView(value: progress)
                    .frame(width: 240)
            }
            StatusText(status: model.logoStatus)
                .frame(minHeight: 20)

            HStack {
                Button("Choose Image…") { isChoosingFile = true }
                    .disabled(model.isLogoBusy)
                Spacer()
                Button("Delete Logo…", role: .destructive) { isConfirmingDelete = true }
                    .disabled(!model.canDelete)
                Button("Transfer") { model.transferLogo() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canTransfer)
            }

            if model.isConnected && !model.logoInterfaceAvailable {
                Text("The controller's logo interface is unavailable. Quit other DJ apps and reconnect the controller.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.allowedTypes) { result in
            if case .success(let url) = result { load(url) }
        }
        .confirmationDialog("Delete the image saved to the hardware?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { model.deleteLogo() }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
            if let preview = model.logoPreview {
                Image(decorative: preview, scale: 1)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: 240, height: 240)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                    Text("Drop an image file here.")
                    Text("BMP, JPG, PNG, GIF").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 240, height: 240)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isTargeted ? 3 : 1)
        )
        .overlay(alignment: .bottom) {
            if let name = model.logoFileName {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .onTapGesture { if !model.isLogoBusy { isChoosingFile = true } }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { load(url) }
            }
            return true
        }
        .help("Click to browse for a different file")
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        model.loadImage(from: url)
    }
}
