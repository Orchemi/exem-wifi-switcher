import Foundation

/// 지금 접속한 Wi-Fi 이름을 읽으려 한 결과.
///
/// SSID 는 CoreWLAN 으로만 읽을 수 있고, macOS 는 그 값을 위치 정보로 취급해 **위치 권한**을 요구한다
/// (Phase 0 실증). 그래서 "못 읽었다" 는 상태가 여러 갈래로 갈리고, 갈래마다 사용자가 할 일이 다르다.
///
/// - 권한이 없어서 못 읽은 것과 Wi-Fi 가 꺼져서 못 읽은 것은 전혀 다른 문제다
/// - 어느 쪽이든 **못 읽었으면 구성을 바꾸지 않는다.** 어디에 있는지 모르는 채로 IP 를 갈아치우면
///   사내에서 인터넷이 끊기거나, 집에서 남의 대역을 쓰게 된다
public enum SSIDReading: Equatable, Sendable {

    /// 접속한 Wi-Fi 이름을 읽었다.
    case connected(String)
    /// Wi-Fi 는 켜져 있으나 어디에도 접속돼 있지 않다.
    case notAssociated
    /// Wi-Fi 가 꺼져 있다.
    case wifiOff
    /// 위치 권한을 아직 묻지 않았거나 사용자가 답하지 않았다.
    case permissionNotDetermined
    /// 사용자가 위치 권한을 거부했다. 자동 전환이 동작할 수 없다.
    case permissionDenied
    /// 그 밖의 이유로 읽지 못했다 (Wi-Fi 인터페이스가 없는 기기 등). 이유를 함께 들고 다닌다.
    case unavailable(String)

    /// 읽어낸 Wi-Fi 이름. 접속 상태일 때만 값이 있다.
    public var name: String? {
        if case .connected(let ssid) = self { return ssid }
        return nil
    }

    /// 위치 권한 때문에 막힌 상태인가. 사용자가 시스템 설정에서 풀어야 한다.
    public var isPermissionProblem: Bool {
        self == .permissionDenied || self == .permissionNotDetermined
    }

    /// 메뉴에 한 줄로 적을 수 있는 설명. 어떤 상태든 말없이 사라지지 않게 한다.
    public var statusText: String {
        switch self {
        case .connected(let ssid):
            return "Wi-Fi \(ssid)"
        case .notAssociated:
            return "Wi-Fi 에 접속돼 있지 않습니다"
        case .wifiOff:
            return "Wi-Fi 가 꺼져 있습니다"
        case .permissionNotDetermined:
            return "위치 권한을 승인해야 Wi-Fi 이름을 읽습니다"
        case .permissionDenied:
            return "위치 권한이 없어 Wi-Fi 이름을 읽지 못합니다"
        case .unavailable(let reason):
            return "Wi-Fi 이름을 읽지 못했습니다 — \(reason)"
        }
    }
}
