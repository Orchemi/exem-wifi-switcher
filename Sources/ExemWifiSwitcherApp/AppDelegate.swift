import AppKit
import WifiSwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 이미 떠 있는 앱에게 설정 창을 열어 달라고 부탁하는 신호.
    ///
    /// 메뉴바가 꽉 차 아이콘이 그려지지 않는 환경이 있다(노치 있는 Mac + 상태 항목 과다).
    /// 그런 상태에서 메뉴바가 유일한 출입구면 사용자는 앱에 손댈 방법이 없다.
    /// 그래서 **앱을 한 번 더 실행하는 것**을 비상구로 둔다 — 두 번째 실행은 이 신호만 보내고 물러난다.
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
