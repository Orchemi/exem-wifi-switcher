@preconcurrency import CoreLocation
import CoreWLAN
import Foundation
import WifiSwitcherCore

/// 지금 접속한 Wi-Fi 이름을 읽는다.
///
/// **CoreWLAN 만 쓴다.** Phase 0 에서 `ipconfig getsummary` · `system_profiler` 는 권한과 무관하게
/// `<redacted>` 를 돌려주는 것이 확인됐다. 남은 경로는 `CWInterface.ssid()` 하나뿐이고,
/// 그것은 `.app` 번들 + 위치 권한을 요구한다.
///
/// 읽지 못했을 때 **왜 못 읽었는지 갈래를 나누는 것**이 이 타입의 일이다.
/// "그냥 nil" 은 사용자에게 아무 말도 해주지 못한다.
struct WiFiSSIDReader: Sendable {

    /// - Parameter authorization: `LocationAuthority` 가 본 위치 권한 상태.
    ///   여기서 다시 `CLLocationManager` 를 만들지 않는다 — 그 객체는 메인 스레드의 것이고,
    ///   이 함수는 백그라운드에서 불린다.
    func read(authorization: LocationAuthorizationState) -> SSIDReading {
        guard let interface = CWWiFiClient.shared().interface() else {
            return .unavailable("Wi-Fi 인터페이스를 찾지 못했습니다")
        }
        guard interface.powerOn() else { return .wifiOff }

        if let ssid = interface.ssid(), !ssid.isEmpty {
            return .connected(ssid)
        }

        // 이름이 비어 있다. 접속을 안 한 것인지, 권한이 없어 가려진 것인지 구분한다.
        switch authorization {
        case .notDetermined:
            return .permissionNotDetermined
        case .denied:
            return .permissionDenied
        case .granted:
            // 앱은 승인받았는데도 안 보이면 시스템 전체 위치 서비스가 꺼져 있는 경우다.
            // (이 호출은 메인 스레드에서 하면 경고가 난다 — 그래서 백그라운드 전용인 이 자리에 둔다)
            guard CLLocationManager.locationServicesEnabled() else {
                return .unavailable("시스템 위치 서비스가 꺼져 있습니다")
            }
            return .notAssociated
        }
    }
}
