import Foundation

/// 위치 권한의 현재 상태. 시스템 열거형(`CLAuthorizationStatus`)을 그대로 들고 다니지 않고 세 갈래로 좁힌다.
///
/// **왜 위치 권한인가**: macOS 는 Wi-Fi 이름(SSID)을 위치 정보로 취급한다. 권한이 없으면
/// `CWInterface.ssid()` 가 nil 을 돌려주고, 그러면 여기가 사내인지 밖인지 알 방법이 없다
/// (Phase 0 실증: `ipconfig`·`system_profiler` 는 `<redacted>` 만 준다).
///
/// **코어에 두는 이유**: 이 값이 SSID 판독(`SSIDReading`)과 권한 점검(`PermissionReport`) 두 판정의
/// 입력이다. `CLLocationManager` 를 만지는 자리(`LocationAuthority`)는 앱에 그대로 남는다 —
/// 여기 있는 것은 시스템 호출 없는 세 갈래뿐이다.
public enum LocationAuthorizationState: Equatable, Sendable {
    /// 아직 묻지 않았거나 사용자가 답하지 않았다
    case notDetermined
    /// 사용자가 거부했거나 관리 정책이 막았다 — 자동 전환이 성립하지 않는다
    case denied
    case granted
}
