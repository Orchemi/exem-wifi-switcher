import Foundation
import UserNotifications
import WifiSwitcherCore

/// 자동 전환이 한 일을 사용자에게 알린다.
///
/// 자동 전환의 대가는 **모르는 사이에 IP 가 바뀌는 것**이다. 알림은 그 대가를 갚는 장치다.
/// 문구는 `SwitchAnnouncement` 가 만든다 — 여기서는 전달만 한다.
///
/// 알림을 못 쓰는 상황(권한 거부·번들 밖 실행)에서도 앱은 그대로 동작한다.
/// 무슨 일이 있었는지는 메뉴에도 남으므로, 알림은 유일한 통로가 아니다.
@MainActor
final class SwitchNotifier {

    private let center: UNUserNotificationCenter?

    /// 알림을 보낼 수 있는 상태인가. **메뉴가 이 값을 그대로 적는다** —
    /// 거부된 사실을 앱 안에서 말하지 않으면 사용자는 알림이 없는 것과 기능이 죽은 것을 구분할 수 없다.
    private(set) var permission: NotificationPermission

    /// 권한 답을 기다리는 동안 쌓아 둔 알림.
    ///
    /// 승인 답은 비동기로 늦게 온다. 그 사이에 첫 전환이 일어나면(로그인 직후가 정확히 그렇다)
    /// 그냥 버릴 경우 **가장 알려야 할 첫 전환이 통째로 조용해진다.**
    private var deferred: [SwitchAnnouncement.Message] = []
    /// 답이 끝내 오지 않아도 무한정 쌓이지 않게 한다. 기동 직후 몇 건이면 충분하다.
    private static let deferredLimit = 3

    /// 권한 상태가 정해지면 불린다 (메뉴를 다시 그리기 위해).
    var onPermissionChange: (@MainActor () -> Void)?

    init() {
        // `UNUserNotificationCenter.current()` 는 번들 밖(맨 실행 파일)에서 부르면 프로세스가 죽는다.
        // 개발 중 `swift run` 으로 띄우는 경우가 있으므로 번들일 때만 붙잡는다.
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") {
            center = UNUserNotificationCenter.current()
            permission = .pending
        } else {
            center = nil
            // 번들 밖에서는 사용자가 할 수 있는 일이 없다. 재촉하지 않는다.
            permission = .unavailable
        }
    }

    /// 알림 권한을 한 번 요청한다. 거부하면 다시 묻지 않는다.
    ///
    /// **완료 핸들러 방식을 쓰지 않는다.** `@MainActor` 인 이 타입 안에서 만든 클로저는 메인 액터에
    /// 격리된 것으로 추론되는데, UserNotifications 는 그 클로저를 자기 큐에서 부른다.
    /// 그러면 Swift 런타임의 격리 검사에 걸려 **앱이 그 자리에서 죽는다.** async 로 받으면 이 문제가 없다.
    func prepare() {
        guard let center else { return }
        Task { @MainActor in
            // 알림이 아예 허용되지 않는 앱이면 오류가 난다. 그때는 알림 없이 동작하되, 그 사실을 남긴다.
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            permission = granted ? .allowed : .denied
            flushDeferred()
            onPermissionChange?()
        }
    }

    func post(_ message: SwitchAnnouncement.Message) {
        switch permission {
        case .pending:
            // 아직 답을 받지 못했다. 버리지 말고 들고 있다가 승인되면 그때 보낸다.
            if deferred.count < Self.deferredLimit { deferred.append(message) }
        case .allowed:
            deliver(message)
        case .denied, .unavailable:
            break
        }
    }

    private func flushDeferred() {
        let pending = deferred
        deferred = []
        guard permission == .allowed else { return }
        for message in pending { deliver(message) }
    }

    private func deliver(_ message: SwitchAnnouncement.Message) {
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body

        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
