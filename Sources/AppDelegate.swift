import AppKit

// MARK: - アプリケーションのライフサイクル管理

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock に表示しない常駐アプリにする
        NSApp.setActivationPolicy(.accessory)
        let controller = StatusItemController()
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
