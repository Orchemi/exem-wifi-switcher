@preconcurrency import CoreLocation
import Foundation

/// 위치 권한의 현재 상태. 시스템 열거형을 그대로 들고 다니지 않고 세 갈래로 좁힌다.
enum LocationAuthorizationState: Equatable, Sendable {
    /// 아직 묻지 않았거나 사용자가 답하지 않았다
    case notDetermined
    /// 사용자가 거부했거나 관리 정책이 막았다 — 자동 전환이 성립하지 않는다
    case denied
    case granted
}

/// 위치 권한을 묻고, 그 상태를 지켜본다.
///
/// **왜 위치 권한인가**: macOS 는 Wi-Fi 이름(SSID)을 위치 정보로 취급한다. 권한이 없으면
/// `CWInterface.ssid()` 가 nil 을 돌려주고, 그러면 여기가 사내인지 밖인지 알 방법이 없다
/// (Phase 0 실증: `ipconfig`·`system_profiler` 는 `<redacted>` 만 준다).
///
/// 권한은 **번들 식별자에 귀속**되므로 한 번 승인하면 재빌드해도 유지된다.
@MainActor
final class LocationAuthority: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private(set) var state: LocationAuthorizationState
    /// 사용자가 승인 창에 답했을 때 불린다.
    var onChange: (@MainActor () -> Void)?

    override init() {
        state = LocationAuthority.map(manager.authorizationStatus)
        super.init()
        manager.delegate = self
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
