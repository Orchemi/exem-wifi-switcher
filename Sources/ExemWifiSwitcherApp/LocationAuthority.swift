@preconcurrency import CoreLocation
import Foundation
import WifiSwitcherCore

/// 위치 권한을 묻고, 그 상태를 지켜본다.
///
/// 상태 자체(`LocationAuthorizationState`)는 코어에 있다 — SSID 판독과 권한 점검이 함께 쓴다.
/// 여기는 `CLLocationManager` 를 만지는 유일한 자리다.
///
/// 권한은 **번들 식별자에 귀속**되므로 한 번 승인하면 재빌드해도 유지된다.
@MainActor
final class LocationAuthority: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private(set) var state: LocationAuthorizationState
    /// 사용자가 승인 창에 답했을 때 불린다.
    var onChange: (@MainActor () -> Void)?

    /// 시스템이 권한 상태를 한 번이라도 알려줬는가.
    ///
    /// **`authorizationStatus` 는 만든 직후에 믿을 수 없다.** `CLLocationManager` 는 위치 데몬과
    /// 이야기한 뒤에야 실제 값을 갖고, 그 전에는 '아직 묻지 않음' 을 돌려준다. 실행 루프가 도는
    /// 앱에서는 곧 델리게이트가 메워 주지만, **한 번 찍고 끝나는 `--diagnose`** 에는 그 순간이 오지
    /// 않는다. 그래서 "이미 승인받아 Wi-Fi 이름을 읽고 있는데 권한은 아직 묻지 않음" 이 함께 찍혔다.
    private var hasSystemReported = false

    override init() {
        state = LocationAuthority.map(manager.authorizationStatus)
        super.init()
        manager.delegate = self
    }

    /// 시스템이 실제 권한 상태를 알려줄 때까지 잠깐 기다렸다가 답한다.
    ///
    /// 실행 루프를 직접 돌리는 이유: 델리게이트 호출은 메인 스레드로 오는데, 이 함수를 부르는
    /// `--diagnose` 는 아직 `NSApplication` 을 띄우지 않아 아무도 루프를 돌리지 않는다.
    /// 답이 오면 곧바로 빠져나온다. 다만 **아직 승인받은 적이 없는 앱에서는 아무 소식도 오지
    /// 않는 것을 실측했다** — 그때는 '아직 묻지 않음' 이 맞는 답이라 기다림이 헛돈다.
    /// 그래서 기다리는 시간을 짧게 잡고, 부르는 쪽은 **먼저 증거(Wi-Fi 이름)를 보고** 나서 부른다.
    func settledState(timeout: TimeInterval = 0.5) -> LocationAuthorizationState {
        let deadline = Date().addingTimeInterval(timeout)
        while !hasSystemReported, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return state
    }

    /// 아직 묻지 않았을 때만 승인 창을 띄운다. 거부한 사용자를 반복해서 괴롭히지 않는다
    /// (거부 이후에는 시스템 설정에서만 바꿀 수 있고, 앱은 그 경로를 안내한다).
    func requestIfNeeded() {
        guard state == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 값이 그대로여도 **알려줬다는 사실**은 남긴다 — 기다리는 쪽은 그 신호로 빠져나온다.
            self.hasSystemReported = true
            let next = LocationAuthority.map(status)
            guard next != self.state else { return }
            self.state = next
            self.onChange?()
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorizedAlways:
            return .granted
        @unknown default:
            // 모르는 상태를 '승인됨' 으로 낙관하지 않는다. 읽어보고 실패하면 그때 이유가 드러난다.
            return .notDetermined
        }
    }
}
