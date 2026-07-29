import AppKit
import WifiSwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 이미 떠 있는 앱에게 설정 창을 열어 달라고 부탁하는 신호.
    ///
    /// **다른 자리에 있는 사본**이 떴을 때만 쓰인다 — 같은 번들을 다시 여는 길은 아래
    /// `applicationShouldHandleReopen` 이 맡는다 (macOS 가 두 번째 프로세스를 띄우지 않기 때문이다).
    /// 사본은 macOS 에게 남남이라 실제로 프로세스가 하나 더 뜨고, 그것이 물러나며 이 신호를 남긴다.
    static let showSettingsRequest = Notification.Name("com.horbis.exem-wifi-switcher.showSettings")

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 로그인 항목(launchd)과 사용자의 직접 실행이 겹치면 메뉴바에 아이콘이 둘이 된다.
        // 먼저 뜬 쪽을 남기고 나중에 뜬 쪽이 조용히 물러난다.
        if AppDelegate.anotherInstanceIsRunning() {
            DistributedNotificationCenter.default().postNotificationName(
                AppDelegate.showSettingsRequest, object: nil, userInfo: nil, deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        let controller = StatusItemController()
        statusItemController = controller
        controller.start()
    }

    /// 창을 다 닫아도 앱은 남는다 — 메뉴바가 본체다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 이미 떠 있는 앱을 Spotlight·Finder 로 **다시 열면 설정 창을 연다.**
    ///
    /// 이 자리가 비어 있으면 다시 열기가 **아무 일도 하지 않는다.** `.accessory` 앱에는 띄울 창이
    /// 없어서 macOS 가 조용히 끝내기 때문이다. 메뉴 막대 아이콘이 노치에 가려진 사용자에게는
    /// 그 순간 마지막 문이 닫힌다 — 오너가 실제로 여기에 갇혔다
    /// ("응용프로그램에서 EXEM Wifi Switcher 쳐서 열려고 했는데도 안돼").
    ///
    /// **실측**(2026-07-29 · macOS 26.5 · `LSUIElement` 번들): 이미 떠 있는 앱을 다시 열면 macOS 는
    /// 두 번째 프로세스를 띄우지 않고 **같은 프로세스**에 이 신호를 보낸다
    /// (`hasVisibleWindows: false`, 직전에 `didBecomeActive`). 그래서 위의
    /// `anotherInstanceIsRunning()` 길은 같은 번들을 다시 여는 경우에는 **아예 돌지 않는다** —
    /// 그 길은 다른 자리에 있는 사본이 떴을 때만 쓰인다.
    ///
    /// 창이 이미 열려 있으면 `openSettings()` 가 그것을 앞으로 가져온다 — 새로 만들지 않는다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItemController?.openSettings()
        return true
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard Bundle.main.bundleIdentifier == InstallPaths.bundleIdentifier else { return false }
        let mine = NSRunningApplication.current
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: InstallPaths.bundleIdentifier)
            .contains { other in
                other.processIdentifier != mine.processIdentifier
                    && (other.launchDate ?? .distantPast) < (mine.launchDate ?? .distantFuture)
            }
    }
}
