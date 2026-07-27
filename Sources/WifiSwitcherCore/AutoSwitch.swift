import Foundation

/// 자동 전환 판정에 들어가는 관측값 전부. 시스템 호출은 이 값을 채우는 쪽(앱)에 있다.
public struct AutoSwitchContext: Equatable, Sendable {

    /// 사용자가 자동 전환을 켜 두었는가.
    public var isEnabled: Bool
    public var config: ConfigStatus
    /// 권한 스크립트(`apply`)가 설치돼 있는가.
    public var helperInstalled: Bool
    public var ssid: SSIDReading
    /// 지금의 IPv4 구성. 읽지 못했으면 nil.
    public var interface: InterfaceInfo?
    /// 지금 걸려 있는 DNS. **구성의 일부다** — IP 만 맞고 DNS 가 다른 상태를
    /// "이미 적용됨" 으로 넘기면 도달할 수 없는 resolver 를 물고 도는 일이 생긴다.
    /// 읽지 못했으면 그 사실 그대로 넣는다 (판정에서 빠진다).
    public var dns: DNSReading
    /// 이미 전환이 진행 중인가.
    public var isBusy: Bool

    public init(
        isEnabled: Bool,
        config: ConfigStatus,
        helperInstalled: Bool,
        ssid: SSIDReading,
        interface: InterfaceInfo?,
        dns: DNSReading,
        isBusy: Bool
    ) {
        self.isEnabled = isEnabled
        self.config = config
        self.helperInstalled = helperInstalled
        self.ssid = ssid
        self.interface = interface
        self.dns = dns
        self.isBusy = isBusy
    }
}

/// 자동 전환을 하지 않은 이유. 전부 이름을 붙여 둔다 — 이름 없는 "아무 일도 없음" 은
/// 고장과 구분되지 않는다.
public enum AutoSwitchHold: Equatable, Sendable {
    /// 사용자가 자동 전환을 껐다
    case disabled
    /// 다른 전환이 진행 중이다
    case busy
    /// 위치 권한을 아직 승인받지 못했다
    case locationPermissionRequired
    /// 사용자가 위치 권한을 거부했다
    case locationPermissionDenied
    case wifiOff
    case notAssociated
    /// 그 밖의 이유로 SSID 를 읽지 못했다
    case ssidUnavailable(String)
    /// 설정이 없거나 쓸 수 없다
    case configUnavailable
    case helperNotInstalled
    /// 걸리는 프로필도 기본 프로필도 없다
    case noMatchingProfile(ssid: String)
    /// 이미 목표 구성이다 — 평소 상태
    case alreadyApplied(profile: String)
    /// 사용자가 이 Wi-Fi 에서 직접 다른 프로필을 골랐다
    case manualOverride(profile: String)
    /// 방금 적용했고 구성이 따라올 시간을 주는 중이다
    case settling(profile: String)
    /// 적용은 성공했다는데 구성이 끝내 바뀌지 않았다
    case ineffective(profile: String)
    /// 실패해서 쉬는 중이다
    case backoff(profile: String, retryAt: Date)
    /// 연속 실패가 한도에 이르러 멈췄다
    case givenUp(profile: String, failures: Int)
}

/// 자동 전환 판정 결과.
public enum AutoSwitchDecision: Equatable, Sendable {
    case apply(profile: String)
    case hold(AutoSwitchHold)

    /// 적용할 프로필 이름. 하지 않기로 했으면 nil.
    public var profileToApply: String? {
        if case .apply(let profile) = self { return profile }
        return nil
    }

    public var hold: AutoSwitchHold? {
        if case .hold(let reason) = self { return reason }
        return nil
    }
}

/// 지금까지 자동 전환이 무엇을 시도했는지에 대한 기록.
///
/// **이 기록이 무한 루프를 막는 장치다.** 전환은 네트워크 변경 이벤트를 낳고, 그 이벤트가
/// 다시 판정을 부른다. 기록이 없으면 같은 전환을 영원히 되풀이할 수 있다.
///
/// 기록의 유효 범위는 **하나의 Wi-Fi 에 머무는 동안**이다. 다른 Wi-Fi 로 옮기면
/// (`adopt(ssid:)`) 전부 잊는다.
///
/// 다만 그 문이 **유일한 출구여서는 안 된다.** 기록은 두 가지 방법으로도 정리된다.
///   - `recordSettled(profile:at:)` — 구성이 목표와 같아진 것을 관측했다. 시도가 끝났으므로 정산한다
///   - `clearAttempts()` — 사용자가 원인을 고치고 다시 시도하겠다고 했다 (토글 · "지금 다시 시도")
/// 이 둘이 없으면 한 번 굳은 자동 전환은 Wi-Fi 를 갈아타거나 앱을 다시 띄우기 전까지 살아나지 않는다.
public struct AutoSwitchState: Equatable, Sendable {

    /// 이 기록이 속한 Wi-Fi 이름. nil 은 접속돼 있지 않은 상태.
    public private(set) var ssid: String?
    /// 마지막으로 적용을 시도한 프로필 이름.
    public private(set) var attemptedProfile: String?
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastSuccessAt: Date?
    /// 구성이 목표와 같아진 것을 **실제로 관측한** 마지막 시각.
    ///
    /// 성공 응답(`lastSuccessAt`)과 다른 사실이다. 스크립트가 0 을 돌려준 것과, 그 뒤 구성이
    /// 정말 목표대로 됐는지는 별개다. 이 값이 있으면 그 뒤의 어긋남은 "효과가 없었다" 가 아니라
    /// **정착한 뒤 풀린 것**이므로 다시 적용해야 한다.
    public private(set) var lastSettledAt: Date?
    public private(set) var lastFailureMessage: String?
    /// 이 Wi-Fi 에서 사용자가 직접 고른 프로필. 자동 전환은 이 선택을 덮지 않는다.
    public private(set) var manualChoice: String?

    public init() {}

    /// 지금 보고 있는 Wi-Fi 를 알린다. **다른 Wi-Fi 로 바뀌었을 때만** 이전 기록을 잊는다.
    ///
    /// 이름을 모르는 상태(접속 끊김·권한 없음)로는 기록을 지우지 않는다. 지우면
    /// "끊김 → 재접속" 이 반복될 때마다 백오프가 초기화돼, 실패하는 전환을 몇 초 간격으로
    /// 영원히 되풀이하게 된다. 모르는 것은 잊을 근거가 되지 못한다.
    public mutating func adopt(ssid: String?) {
        guard let ssid, ssid != self.ssid else { return }
        self = AutoSwitchState(ssid: ssid)
    }

    private init(ssid: String?) {
        self.ssid = ssid
    }

    public mutating func recordAttempt(profile: String, at date: Date) {
        if attemptedProfile != profile {
            // 목표가 바뀌었으면 이전 목표의 실패·정착 기록은 의미가 없다.
            consecutiveFailures = 0
            lastFailureMessage = nil
            lastSuccessAt = nil
            lastSettledAt = nil
        }
        attemptedProfile = profile
        lastAttemptAt = date
    }

    public mutating func recordSuccess(at date: Date) {
        consecutiveFailures = 0
        lastFailureMessage = nil
        lastSuccessAt = date
    }

    public mutating func recordFailure(message: String, at date: Date) {
        consecutiveFailures += 1
        lastFailureMessage = message
        lastSuccessAt = nil
        lastAttemptAt = date
    }

    /// 구성이 목표와 같아진 것을 관측했다 — **시도는 여기서 끝난다(정산).**
    ///
    /// 이 정산이 없으면 성공 기록이 그 Wi-Fi 를 떠날 때까지 남아, 나중에 구성이 풀렸을 때
    /// "적용했지만 효과가 없다" 로 굳는다. 적용은 됐었고 나중에 풀린 것이므로 사실이 아니고,
    /// 그 상태에서 자동 전환은 SSID 가 바뀌기 전까지 아무것도 하지 않는다.
    public mutating func recordSettled(profile: String, at date: Date) {
        clearAttempts()
        attemptedProfile = profile
        lastSettledAt = date
    }

    /// 시도 기록을 지운다 — 실패 횟수·백오프·성공/정착 기록이 전부 사라진다.
    ///
    /// 사용자가 원인을 고친 뒤(권한 재설치 등) **같은 Wi-Fi 에서** 다시 시도할 수 있어야 한다.
    /// 자동 전환을 껐다 켜거나 메뉴에서 "지금 다시 시도" 를 누르는 것이 그 문이다.
    /// 수동 선택(`manualChoice`)은 사용자의 뜻이므로 여기서 건드리지 않는다.
    public mutating func clearAttempts() {
        attemptedProfile = nil
        consecutiveFailures = 0
        lastFailureMessage = nil
        lastAttemptAt = nil
        lastSuccessAt = nil
        lastSettledAt = nil
    }

    /// 사용자가 메뉴에서 직접 프로필을 골랐다. 자동 전환은 이 Wi-Fi 에 있는 동안 그 선택을 존중한다.
    public mutating func recordManualChoice(profile: String) {
        clearAttempts()
        manualChoice = profile
    }

    /// 수동 선택을 거둔다 (자동 전환을 다시 켰을 때 등).
    public mutating func clearManualChoice() {
        manualChoice = nil
    }
}

/// 자동 전환 판정. 시스템을 건드리지 않는 순수 계산이다.
public enum AutoSwitchPolicy {

    /// 전환 직후 `networksetup -getinfo` 가 새 값을 보여줄 때까지 기다리는 시간.
    /// 이 시간 동안은 같은 전환을 다시 걸지 않는다.
    public static let settleInterval: TimeInterval = 8

    /// 연속 실패가 이 횟수에 이르면 그 Wi-Fi 에서는 더 시도하지 않는다.
    public static let failureLimit = 5

    /// 실패 후 대기 시간의 상한.
    ///
    /// `failureLimit` 에 맞춰 둔다. 마지막 재시도는 4회 실패 뒤(270초)에 오고 5회째에 멈추므로,
    /// 그보다 큰 상한은 **어디에도 쓰이지 않는 숫자**다 (문서와 코드가 갈라지는 자리가 된다).
    public static let maximumBackoff: TimeInterval = 270

    /// 연속 실패 횟수에 따른 대기 시간 (10초 → 30초 → 90초 → 270초 = 상한).
    public static func backoffInterval(consecutiveFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let seconds = 10 * pow(3, Double(failures - 1))
        return min(seconds, maximumBackoff)
    }

    /// 지금 전환할 것인가. 하지 않는다면 왜인가.
    ///
    /// 호출 전에 `state.adopt(ssid:)` 로 지금 보고 있는 Wi-Fi 를 알려야 한다
    /// (Wi-Fi 가 바뀌었는데 옛 기록으로 판정하면 자동 전환이 굳는다).
    public static func decide(_ context: AutoSwitchContext, state: AutoSwitchState, now: Date) -> AutoSwitchDecision {
        guard context.isEnabled else { return .hold(.disabled) }
        guard !context.isBusy else { return .hold(.busy) }

        // 1) 전환할 대상 자체가 준비돼 있는가
        guard case .ready(let config) = context.config else { return .hold(.configUnavailable) }
        guard context.helperInstalled else { return .hold(.helperNotInstalled) }

        // 2) 어디에 있는지 알아야 판단할 수 있다. 모르면 **아무것도 바꾸지 않는다.**
        let ssid: String
        switch context.ssid {
        case .connected(let name): ssid = name
        case .notAssociated: return .hold(.notAssociated)
        case .wifiOff: return .hold(.wifiOff)
        case .permissionDenied: return .hold(.locationPermissionDenied)
        case .permissionNotDetermined: return .hold(.locationPermissionRequired)
        case .unavailable(let reason): return .hold(.ssidUnavailable(reason))
        }

        guard let target = config.profile(forSSID: ssid) else {
            return .hold(.noMatchingProfile(ssid: ssid))
        }

        // 3) 사용자가 이 Wi-Fi 에서 직접 다른 것을 골랐다면 그 손을 밀어내지 않는다.
        if let choice = state.manualChoice, choice != target.name {
            return .hold(.manualOverride(profile: choice))
        }

        // 4) 이미 목표와 같으면 아무것도 하지 않는다 — 자동 전환이 스스로를 부르지 않게 하는 첫 관문이다.
        //
        //    **IP 만 보지 않는다.** DNS 도 프로필이 정하는 값이라, IP·서브넷·라우터만 맞는 상태를
        //    통과시키면 사내 DNS 를 문 채 집에서 도는 구성(부분 적용·이전 프로필의 잔재)이 굳는다.
        //    다만 DNS 를 **읽지 못한 것**은 '다르다' 가 아니다 — 그렇게 다루면 조회가 실패할 때마다
        //    같은 프로필을 무한히 다시 적용하게 된다. 판정할 수 없으면 판정에서 뺀다.
        if let interface = context.interface, interface.conforms(to: target) {
            switch context.dns.conformance(to: target) {
            case .matches, .undecidable:
                return .hold(.alreadyApplied(profile: target.name))
            case .differs:
                break
            }
        }

        // 5) 같은 목표를 이미 시도했다면, 그 결과에 따라 쉬거나 멈춘다.
        //
        //    **시도했다는 기록이 있는데 결과가 없는 경우까지 여기서 받는다.** 어느 층에서도 잡히지
        //    않으면 판정마다 같은 명령을 다시 걸어 무한 재시도가 된다.
        if state.attemptedProfile == target.name {
            if state.consecutiveFailures >= failureLimit {
                return .hold(.givenUp(profile: target.name, failures: state.consecutiveFailures))
            }
            if state.consecutiveFailures > 0, let lastAttempt = state.lastAttemptAt {
                let retryAt = lastAttempt.addingTimeInterval(
                    backoffInterval(consecutiveFailures: state.consecutiveFailures)
                )
                if now < retryAt {
                    return .hold(.backoff(profile: target.name, retryAt: retryAt))
                }
            } else if let lastSuccess = state.lastSuccessAt {
                // 성공했는데 4) 를 통과했다는 것은 구성이 아직(또는 끝내) 목표와 다르다는 뜻이다.
                if now < lastSuccess.addingTimeInterval(settleInterval) {
                    return .hold(.settling(profile: target.name))
                }
                // 성공 이후 **한 번도** 목표 구성을 관측하지 못했다. 같은 명령을 또 걸어도 결과는 같다.
                return .hold(.ineffective(profile: target.name))
            } else if let settledAt = state.lastSettledAt {
                // 한 번 정착한 뒤 구성이 다시 어긋났다. 이것은 '효과 없음' 이 아니라 **풀린 것**이므로
                // 다시 적용한다. 다만 정착을 본 직후의 어긋남은 낡은 관측일 수 있어 잠깐만 기다린다
                // (다른 도구와 서로 되돌리는 싸움이 붙어도 초당 몇 번씩 명령을 내지 않게 하는 고삐이기도 하다).
                if now < settledAt.addingTimeInterval(settleInterval) {
                    return .hold(.settling(profile: target.name))
                }
            } else if let lastAttempt = state.lastAttemptAt {
                // 시도는 했는데 성공도 실패도 기록되지 않았다. 결과를 모르는 채로 곧바로 다시 걸지 않는다.
                if now < lastAttempt.addingTimeInterval(settleInterval) {
                    return .hold(.settling(profile: target.name))
                }
            }
        }

        return .apply(profile: target.name)
    }
}
