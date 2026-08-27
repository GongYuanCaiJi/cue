import AppKit

/// Manages the menu bar status item for the Agent application
@MainActor
final class StatusBarController {

    private var statusItem: NSStatusItem?
    private weak var stateMachine: AgentStateMachine?
    private var sparkleUpdater: SparkleUpdater?
    private var opacitySlider: NSSlider?

    init(stateMachine: AgentStateMachine, sparkleUpdater: SparkleUpdater?) {
        self.stateMachine = stateMachine
        self.sparkleUpdater = sparkleUpdater
        setupStatusItem()
        checkPermissions()
    }

    private func checkPermissions() {
        Task {
            let hasScreenRecording = await PermissionChecker.shared.checkScreenRecording()
            if !hasScreenRecording {
                print("Warning: Screen Recording permission not granted")
                PermissionChecker.shared.showScreenRecordingPermissionAlert()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pin")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateMenu()
    }

    @objc private func statusItemClicked() {
        updateMenu()
    }

    /// 狀態列按鈕在螢幕上的位置(Cocoa 座標,左下原點),給自動化測試定位用
    func buttonScreenFrame() -> CGRect? {
        guard let button = statusItem?.button, let win = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        return win.convertToScreen(inWindow)
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Status section
        let status = stateMachine?.getStatus()
        let isPinned = status?.pinned ?? false

        if isPinned {
            let statusItem = NSMenuItem(title: "📌 Pinned: \(status?.targetAppName ?? "Unknown")", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            if let title = status?.targetWindowTitle {
                let titleItem = NSMenuItem(title: "   \(title)", action: nil, keyEquivalent: "")
                titleItem.isEnabled = false
                menu.addItem(titleItem)
            }

            menu.addItem(NSMenuItem.separator())

            let unpinItem = NSMenuItem(title: "Unpin", action: #selector(unpinWindow), keyEquivalent: "u")
            unpinItem.target = self
            menu.addItem(unpinItem)

            menu.addItem(NSMenuItem.separator())

            // Opacity slider
            let opacityItem = createOpacityMenuItem()
            menu.addItem(opacityItem)
        } else {
            // Window selection submenu (ピンされていない場合のみ表示)
            let windowsMenu = NSMenu()
            let windowsItem = NSMenuItem(title: "Pin Window...", action: nil, keyEquivalent: "")
            windowsItem.submenu = windowsMenu

            // Get available windows
            if let windows = getAvailableWindows() {
                for window in windows {
                    let title = "\(window.appName): \(window.windowTitle ?? "Untitled")"
                    let item = NSMenuItem(title: title, action: #selector(pinSelectedWindow(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = window
                    windowsMenu.addItem(item)
                }

                if windows.isEmpty {
                    let noWindowsItem = NSMenuItem(title: "(No windows available)", action: nil, keyEquivalent: "")
                    noWindowsItem.isEnabled = false
                    windowsMenu.addItem(noWindowsItem)
                }
            }

            menu.addItem(windowsItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Actions

    @objc private func pinSelectedWindow(_ sender: NSMenuItem) {
        guard let windowInfo = sender.representedObject as? TargetWindowInfo else { return }

        Task {
            do {
                try await stateMachine?.pinWindow(windowInfo)
                print("Pinned window: \(windowInfo.appName)")
            } catch {
                print("Failed to pin window: \(error)")
                // Check if it's a Screen Recording permission error
                if Self.isScreenRecordingPermissionError(error) {
                    PermissionChecker.shared.showScreenRecordingPermissionAlert()
                } else {
                    showAlert(title: "Failed to Pin", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func unpinWindow() {
        stateMachine?.unpin()
        print("Window unpinned")
    }

    @objc private func checkForUpdates() {
        sparkleUpdater?.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Opacity Slider

    private func createOpacityMenuItem() -> NSMenuItem {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        // Label
        let label = NSTextField(labelWithString: "Opacity")
        label.frame = NSRect(x: 14, y: 5, width: 50, height: 20)
        label.font = NSFont.menuFont(ofSize: 13)
        containerView.addSubview(label)

        // Slider (10% - 100%)
        let slider = NSSlider(value: Double(stateMachine?.mirrorOpacity ?? 1.0),
                              minValue: 0.1,
                              maxValue: 1.0,
                              target: self,
                              action: #selector(opacitySliderChanged(_:)))
        slider.frame = NSRect(x: 68, y: 5, width: 116, height: 20)
        slider.isContinuous = true
        containerView.addSubview(slider)
        self.opacitySlider = slider

        let menuItem = NSMenuItem()
        menuItem.view = containerView
        return menuItem
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        let opacity = Float(sender.doubleValue)
        stateMachine?.setMirrorOpacity(opacity)
    }

    // MARK: - Helpers

    private func getAvailableWindows() -> [TargetWindowInfo]? {
        // 用 SCShareableContent 當權威來源(跨 Space、含遮住的、不去重)。
        // 它是 async,選單同步建,所以在背景執行緒跑再用 semaphore 等結果(不會卡死主執行緒:
        // SCShareableContent 在自己的 executor 執行,不回主執行緒)。
        let sem = DispatchSemaphore(value: 0)
        var result: [TargetWindowInfo] = []
        Task.detached {
            result = await enumeratePinnableWindows()
            sem.signal()
        }
        // 最多等 3 秒,避免萬一卡住讓選單永久打不開
        _ = sem.wait(timeout: .now() + 3)
        return result
    }

    private static func isScreenRecordingPermissionError(_ error: Error) -> Bool {
        let description = error.localizedDescription
        // TCC error (Screen Recording permission denied)
        return description.contains("TCCs") || description.contains("TCC")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
