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
