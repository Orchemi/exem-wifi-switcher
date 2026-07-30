import Foundation

/// 설정 창의 **DNS 서버 칸**이 무엇을 들고, 그 값이 어디서 왔는지.
///
/// 이 칸에는 출처가 다른 두 값이 들어올 수 있다. **화면에서는 똑같아 보인다.**
///
///   - `networksetup -getdnsservers` 가 돌려준 **수동 지정 값**. 사용자가 정한 값이다
///   - `scutil --dns` 가 보여주는 **지금 쓰이는 리졸버**. 앱이 제안하는 값이다
///
/// 둘을 가르지 않으면 제안한 값을 "원래 내 설정" 으로 알고 저장하게 된다. 그래서 값과 함께
/// **그 값이 어디서 왔는지 한 줄로 말하는 것까지** 이 타입이 정한다.
///
/// 왜 제안이 필요한가. `-getdnsservers` 는 수동 지정 값만 돌려주고, 이 도구는 DHCP 프로필을
/// 걸 때마다 그 수동 지정을 지운다 (`scripts/apply`). 사외에 다녀오면 사내 DNS 는 남아 있지
/// 않고, 사용자는 무엇을 넣어야 하는지 알 방법이 없다. 실제로 그 자리에서 막혔다 (2026-07-30).
public enum DNSFieldState: Equatable, Sendable {

    /// 수동 지정된 값을 읽었다. **사용자가 정한 값이므로 그대로 쓴다.**
    case configured([String])

    /// 수동 지정이 없어 **지금 쓰이는 리졸버를 제안한다.** 확인이 필요한 값이다.
    case suggested([String])

    /// 수동 지정도 없고 쓰이는 값도 읽지 못했다. 직접 입력을 받는다.
    /// `reason` 은 `networksetup` 이 실패한 사유이고, 없을 수도 있다.
    case unavailable(reason: String?)

    /// 칸 아래에 남길 한 줄.
    public struct Notice: Equatable, Sendable {
        public let text: String
        /// 빨간 글씨로 낼 것인가. **제안은 오류가 아니다** — 값이 들어와 있는데 빨갛게 쓰면
        /// 고장으로 읽힌다.
        public let isError: Bool

        public init(text: String, isError: Bool) {
            self.text = text
            self.isError = isError
        }
    }

    /// 두 창을 함께 보고 칸의 상태를 정한다.
    ///
    /// - Parameters:
    ///   - manual: `networksetup -getdnsservers` 결과. **값이 있으면 언제나 이긴다.**
    ///   - activeResolvers: `scutil --dns` 에서 골라낸 지금 쓰이는 IPv4 리졸버
    ///     (`ScutilDNSOutput.activeResolvers`).
    public static func resolve(manual: DNSReading, activeResolvers: [String]) -> DNSFieldState {
        if case .servers(let servers) = manual, !servers.isEmpty {
            return .configured(servers)
        }
        if !activeResolvers.isEmpty {
            return .suggested(activeResolvers)
        }
        return .unavailable(reason: manual.failureReason)
    }

    /// 칸에 넣을 값. 저장할 때 쓰는 것과 같은 구분자(쉼표+공백)로 잇는다.
    public var fieldText: String {
        servers.joined(separator: ", ")
    }

    public var servers: [String] {
        switch self {
        case .configured(let servers), .suggested(let servers): return servers
        case .unavailable: return []
        }
    }

    /// 칸 아래 한 줄. 수동 지정 값을 읽었을 때는 할 말이 없으므로 nil 이다.
    public var notice: Notice? {
        switch self {
        case .configured:
            return nil
        case .suggested:
            return Notice(text: DNSFieldState.suggestionNotice, isError: false)
        case .unavailable(let reason):
            guard let reason, !reason.isEmpty else {
                return Notice(text: DNSFieldState.unknownNotice, isError: true)
            }
            return Notice(text: "현재 DNS 를 읽지 못함 (\(reason)) · 사내 DNS 서버 주소를 직접 입력하세요", isError: true)
        }
    }

    /// 제안일 때 하는 말.
    ///
    /// 세 가지를 한 줄에 담는다. **저장된 값이 아니라는 것 · 어디서 읽었는지 · 확인하고 저장하라는 것.**
    /// 마지막이 빠지면 사용자는 앱이 알아서 넣어 준 값으로 알고 지나간다.
    static let suggestionNotice =
        "지금 이 기기가 쓰고 있는 DNS 입니다 (scutil --dns 로 읽음) · 수동 지정된 값이 아니므로 "
        + "사내 값이 맞는지 확인하고 저장하세요"

    /// 두 창 모두 답을 주지 못했을 때. 사유가 없으므로 무엇을 하면 되는지만 말한다.
    static let unknownNotice =
        "수동 지정된 DNS 가 없고 지금 쓰이는 값도 읽지 못함 · 사내 DNS 서버 주소를 직접 입력하세요"
}
