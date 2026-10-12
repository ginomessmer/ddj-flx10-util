#if DEBUG
import AppKit

/// Development aid: `FLX10_SNAPSHOT_DIR=/path swift run FLX10Utility` renders every pane of the
/// main window to PNG files, then quits. Uses the view hierarchy, so no screen-recording
/// permission is needed.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(model: AppModel) {
        guard let directory = ProcessInfo.processInfo.environment["FLX10_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let image = ProcessInfo.processInfo.environment["FLX10_SNAPSHOT_IMAGE"] {
            model.loadImage(from: URL(fileURLWithPath: image))
        }
        capture(Pane.allCases, model: model, into: url)
    }

    private static func capture(_ panes: [Pane], model: AppModel, into directory: URL) {
        guard let pane = panes.first else {
            NSApp.terminate(nil)
            return
        }
        model.selectedPane = pane
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
               let view = window.contentView?.superview ?? window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("\(pane.rawValue).png"))
            }
            capture(Array(panes.dropFirst()), model: model, into: directory)
        }
    }
}
#endif
