import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics

/// 列舉所有「可擷取(可 pin)」的真實視窗。
/// 用 ScreenCaptureKit 的 SCShareableContent 當權威來源:
///  - 跨所有 Space(不受目前哪個全螢幕 app 在前面影響 → 清單穩定,不會時多時少)
///  - 含被其他視窗遮住的(onScreenWindowsOnly: false)
///  - 不做 per-app 去重:同一個 app 的每個視窗都獨立列出(Chrome 幾個視窗就列幾個)
/// 過濾雜訊的判準(視窗切換器的標準做法):
///  - windowLayer == 0:只要正常視窗層
///  - 擁有它的 app 是「一般 app」(activationPolicy == .regular):踢掉選單列小工具/背景 agent
///    (Stats、WeatherMenu、CC Switch、Mole、autofill 彈窗、螢幕錄影警告…)
///  - 有標題:踢掉瀏覽器的無標題 UI 浮層(omnibox 建議、自動填寫彈窗)
func enumeratePinnableWindows() async -> [TargetWindowInfo] {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(
        true, onScreenWindowsOnly: false
    ) else {
        return []
    }

    let myPID = ProcessInfo.processInfo.processIdentifier
    var out: [TargetWindowInfo] = []

    for w in content.windows {
        guard let app = w.owningApplication else { continue }
        let pid = app.processID
        if pid == myPID { continue }
        if w.windowLayer != 0 { continue }

        let f = w.frame
        if f.width <= 100 || f.height <= 100 { continue }

        // 只留一般 app 的視窗(排除選單列 agent / 背景工具)
        if let running = NSRunningApplication(processIdentifier: pid),
           running.activationPolicy != .regular {
            continue
        }

        // 真實視窗都有標題;無標題多半是瀏覽器 UI 浮層或彈窗
        let title = w.title ?? ""
        if title.isEmpty { continue }

        let appName = app.applicationName.isEmpty
            ? (NSRunningApplication(processIdentifier: pid)?.localizedName ?? "App")
            : app.applicationName

        out.append(TargetWindowInfo(
            pid: pid,
            windowID: w.windowID,
            appName: appName,
            windowTitle: title,
            bounds: f
        ))
    }

    out.sort {
        let a = ($0.appName.lowercased(), ($0.windowTitle ?? "").lowercased())
        let b = ($1.appName.lowercased(), ($1.windowTitle ?? "").lowercased())
        return a < b
    }
    return out
}
