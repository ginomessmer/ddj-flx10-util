import SwiftUI
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Image Playground integration (Apple Intelligence). Everything here hides itself on systems
/// older than macOS 15.1 or Macs where Image Playground isn't available.
extension View {
    func logoImagePlaygroundSheet(isPresented: Binding<Bool>, sourceImage: CGImage?, onCompletion: @escaping (URL) -> Void) -> some View {
        modifier(LogoImagePlaygroundSheet(isPresented: isPresented, sourceImage: sourceImage, onCompletion: onCompletion))
    }
}

/// Seed concept for the prompt; the user can edit it in the sheet.
private let logoConcept = "DJ logo"

private struct LogoImagePlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    let sourceImage: CGImage?
    let onCompletion: (URL) -> Void

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.4, *) {
            content
                .imagePlaygroundSheet(
                    isPresented: $isPresented,
                    concepts: [.text(logoConcept)],
                    sourceImage: sourceImage.map { Image(decorative: $0, scale: 1) },
                    onCompletion: onCompletion
                )
                .imagePlaygroundGenerationStyle(.illustration)
        } else if #available(macOS 15.1, *) {
            content
                .imagePlaygroundSheet(
                    isPresented: $isPresented,
                    concepts: [.text(logoConcept)],
                    sourceImage: sourceImage.map { Image(decorative: $0, scale: 1) },
                    onCompletion: onCompletion
                )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Shows its content only when Image Playground can be used on this Mac.
struct IfImagePlaygroundAvailable<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            SupportGate(content: content)
        }
        #endif
    }

    @available(macOS 15.1, *)
    private struct SupportGate: View {
        @Environment(\.supportsImagePlayground) private var supportsImagePlayground
        let content: Content

        var body: some View {
            if supportsImagePlayground { content }
        }
    }
}
