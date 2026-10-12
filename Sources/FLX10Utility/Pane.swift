import SwiftUI

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case general
    case logo
    case jogDisplay
    case performance
    case recording

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .logo: return "DJ Logo"
        case .jogDisplay: return "Jog Display"
        case .performance: return "Performance"
        case .recording: return "Recording"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .logo: return "photo.fill"
        case .jogDisplay: return "smallcircle.filled.circle.fill"
        case .performance: return "slider.horizontal.3"
        case .recording: return "record.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .logo: return .blue
        case .jogDisplay: return .orange
        case .performance: return .purple
        case .recording: return .red
        }
    }

    /// Panes whose options are written to the controller over USB.
    var isControllerSettings: Bool {
        switch self {
        case .jogDisplay, .performance, .recording: return true
        case .general, .logo: return false
        }
    }
}

/// A System Settings–style icon: a white glyph on a tinted rounded square.
struct PaneIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Pane icons") {
    HStack(spacing: 12) {
        ForEach(Pane.allCases) { pane in
            PaneIcon(symbol: pane.symbol, tint: pane.tint, size: 32)
        }
    }
    .padding()
}
