import Foundation

/// 알림을 보낼 수 있는 상태인가.
///
/// **거부를 조용히 넘기면 자동 전환이 완전히 무성이 된다.** 메뉴바 아이콘까지 보이지 않는 환경이면
/// (이 앱에서 실제로 일어난다) IP 가 바뀐 사실을 알 통로가 하나도 남지 않는다. 그래서 상태를
/// 이름 붙여 들고 다니며 메뉴에 상시 적는다.
public enum NotificationPermission: Equatable, Sendable {
    /// 아직 답을 받지 못했다 (기동 직후). 거부로 단정하지 않는다
    case pending
    case allowed
    case denied
    /// 알림 자체를 쓸 수 없는 실행 형태 (번들 밖). 사용자가 할 수 있는 일이 없으므로 재촉하지 않는다
    case unavailable
}

/// 자동 전환이 사용자에게 건네는 말.
///
/// 자동 전환의 대가는 **모르는 사이에 IP 가 바뀌는 것**이다. 그래서 바뀌면 알린다.
/// 다만 알림은 일하다 끊기는 자리에 뜬다 — 무슨 일이 왜 일어났는지 사실만 짧게 적는다.
/// 느낌표·사과·과장은 쓰지 않는다.
public enum SwitchAnnouncement {

    public struct Message: Equatable, Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// 알림 본문 길이 상한. 넘치면 시스템이 잘라 보여주므로 우리가 먼저 줄인다.
    public static let bodyLengthLimit = 160

    /// 전환에 성공했다.
    public static func applied(profile: NetworkProfile, ssid: String?) -> Message {
        var parts: [String] = []
        if let ssid, !ssid.isEmpty { parts.append("Wi-Fi \(ssid)") }
        switch profile.mode {
        case .manual:
            parts.append(profile.ip.map { "고정 IP \($0)" } ?? "고정 IP")
        case .dhcp:
            parts.append("자동 구성(DHCP)")
        }
        return Message(title: "\(profile.displayName) 적용", body: shorten(parts.joined(separator: " · ")))
    }

    /// 전환에 실패했다. 이유는 원문을 살리되 길이는 줄인다.
    public static func failed(profile: NetworkProfile, ssid: String?, reason: String) -> Message {
        let where_ = (ssid.map { "Wi-Fi \($0) 에서 " } ?? "")
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return Message(
            title: "전환 실패 — \(profile.displayName)",
            body: shorten(where_ + (reason.isEmpty ? "이유를 알 수 없습니다." : reason))
        )
    }

    /// 연속 실패로 자동 전환을 멈췄다. 다시 시도하는 조건까지 적는다.
    public static func stopped(profile: NetworkProfile, failures: Int) -> Message {
        Message(
            title: "자동 전환 중단",
            body: shorten("\(profile.displayName) 적용이 \(failures)회 연속 실패했습니다. Wi-Fi 가 바뀌면 다시 시도합니다.")
        )
    }

    /// 위치 권한이 없어 자동 전환이 성립하지 않는다. 조용히 멈춰 있는 것이 가장 나쁘다.
    public static func locationPermissionNeeded() -> Message {
        Message(
            title: "위치 권한 필요",
            body: "Wi-Fi 이름을 읽지 못해 자동 전환이 멈춰 있습니다. "
                + "시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스에서 허용하세요."
        )
    }

    private static func shorten(_ text: String) -> String {
        guard text.count > bodyLengthLimit else { return text }
        return String(text.prefix(bodyLengthLimit - 1)) + "…"
    }
}
