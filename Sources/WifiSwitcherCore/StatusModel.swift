import Foundation

/// `AppConfig.inspect` 가 돌려주는 설정 파일 상태. 짧은 이름으로도 쓴다.
public typealias ConfigStatus = AppConfig.Status

/// 메뉴바 아이콘 3종. 파일 이름·SF Symbols 이름과 1:1 로 이어진다.
public enum MenuBarIcon: String, Equatable, Sendable {
    /// 고정 IP 프로필이 적용돼 있다
    case manual
    /// DHCP 로 돌고 있다
    case dhcp
    /// 손을 봐야 하는 상태 (미설치·설정 문제·전환 실패)
    case error
}

/// 앱이 지금 하고 있는 일. 관측된 상태보다 우선한다.
public enum ActionState: Equatable, Sendable {
    case idle
    case switching(profile: String)
    case failed(profile: String, message: String)
}

/// 상태 판정에 들어가는 관측값 전부. 시스템 호출은 이 구조체를 채우는 쪽에 있다.
public struct StatusInput: Equatable, Sendable {
    public var config: ConfigStatus
    /// 현재 IPv4 구성. 읽지 못했으면 nil.
    public var interface: InterfaceInfo?
    /// 읽지 못한 이유. 조용히 삼키지 않기 위해 함께 들고 다닌다.
    public var interfaceError: String?
    /// 권한 스크립트(`apply`)가 설치돼 있는가.
    public var helperInstalled: Bool
    /// 무암호 sudoers 규칙이 놓여 있는가.
    ///
    /// 스크립트만 있고 규칙이 없으면 겉보기에는 설치된 상태인데 전환할 때마다 암호를 물어 실패한다.
    /// 설정 창의 '전환 권한' 도 같은 기준으로 본다 (`PermissionReport.switching`).
    public var sudoersInstalled: Bool
    /// 설정 저장 스크립트(`save-config`)가 놓여 있는가. 없으면 값을 저장할 수 없어 설정을 끝낼 수 없다.
    public var saveConfigInstalled: Bool
    /// 위치 권한 상태. **초기 설정의 필수 항목이다** — 이것이 없으면 Wi-Fi 이름을 못 읽어
    /// 사용자가 사내 Wi-Fi 이름을 손으로 넣어야 한다 (`SetupChecklist` 주석).
    public var location: LocationAuthorizationState
    public var action: ActionState
    /// 자동 전환이 켜져 있는가.
    public var autoSwitchEnabled: Bool
    /// 마지막으로 읽은 Wi-Fi 이름. 아직 읽지 않았으면 nil.
    public var ssid: SSIDReading?
    /// 마지막 판정이 전환을 하지 않기로 한 이유. 메뉴에 한 줄로 남긴다.
    public var autoSwitchHold: AutoSwitchHold?
    /// 알림을 보낼 수 있는 상태인가. 막혀 있으면 메뉴가 유일한 통로가 되므로 그 사실을 적는다.
    public var notifications: NotificationPermission

    public init(
        config: ConfigStatus,
        interface: InterfaceInfo? = nil,
        interfaceError: String? = nil,
        helperInstalled: Bool = true,
        sudoersInstalled: Bool = true,
        saveConfigInstalled: Bool = true,
        location: LocationAuthorizationState = .granted,
        action: ActionState = .idle,
        autoSwitchEnabled: Bool = false,
        ssid: SSIDReading? = nil,
        autoSwitchHold: AutoSwitchHold? = nil,
        notifications: NotificationPermission = .allowed
    ) {
        self.config = config
        self.interface = interface
        self.interfaceError = interfaceError
        self.helperInstalled = helperInstalled
        self.sudoersInstalled = sudoersInstalled
        self.saveConfigInstalled = saveConfigInstalled
        self.location = location
        self.action = action
        self.autoSwitchEnabled = autoSwitchEnabled
        self.ssid = ssid
        self.autoSwitchHold = autoSwitchHold
        self.notifications = notifications
    }
}

/// 메뉴바가 그릴 것 전부. 여기까지 오면 AppKit 쪽에는 판단이 남아 있지 않다.
///
/// **메뉴는 문서가 아니다 — 그렇다고 아무 말도 하지 않으면 혼란이 남는다.**
/// 그래서 두 종류만 올린다.
///   - **주 항목**: 누를 수 있는 것 (프로필 · 자동 전환 · 설정 열기…) 과 지금 상태 한 마디
///   - **보조 줄**: 그 위 항목에 딸린 **짧은 명사구 하나** (`- ` 접두 · 흐린 색 · 작은 글자)
///
/// 보조 줄은 넣을지 말지를 **보수적으로** 고른다 — 없어도 사용자가 막히지 않으면 넣지 않는다.
/// 넣기로 했으면 문장이 아니라 한 구(句)로 줄인다. 긴 안내는 설정 창이 들고 있다.
public struct StatusModel: Equatable, Sendable {

    /// 보조 줄 한 줄이 넘지 않을 글자 수.
    ///
    /// 앱이 짓는 문구는 스무 자 안팎을 목표로 하고, 이 값은 **시스템이 준 원문**을 위한 상한이다
    /// (전환 실패 메시지·설정 파일 오류·구성 읽기 실패는 길이를 고를 수 없다).
    /// 그대로 실으면 그 한 줄이 메뉴 폭을 정하므로 자른다. 전문을 잃지는 않는다 —
    /// 전환 실패는 알림과 실패 창이, 설정 파일 오류는 설정 창이, 나머지는 `--diagnose` 가 들고 있다.
    ///
    /// 한글 명사구 스무 자보다 조금 넉넉한 것은 원문이 대개 영문이기 때문이다 —
    /// 흔한 실패 메시지(`sudo: a password is required`)가 통째로 들어가는 선에서 끊었다.
    public static let lineLimit = 30

    /// 보조 줄 접두. 주 항목과 딸린 줄을 눈으로 가르는 표시다.
    ///
    /// **위계를 만드는 것은 색과 크기이고**(흐린 색 + 작은 글자), 이 접두는 그것을 거드는 보조 장치다.
    /// 접두만으로 위계를 세우려 하면 색이 같아 결국 평평해 보인다.
    public static let secondaryPrefix = "- "

    /// 보조 줄로 그릴 때의 문자열. 접두를 한 자리에서만 붙인다.
    public static func secondaryLine(_ text: String) -> String { secondaryPrefix + text }

    /// 메뉴바 아이콘
    public let icon: MenuBarIcon
    /// 메뉴 첫 줄. 지금이 어떤 상태인가를 한 마디로.
    public let headline: String
    /// 머리말에 딸린 보조 줄. 현재 값 · 실패 이유 · 원인이 온다.
    ///
    /// **머리말이 이미 말한 것은 여기 오지 않는다.** 같은 말을 크기만 줄여 한 번 더 적으면
    /// 줄만 늘고 읽을 것은 늘지 않는다. 덧붙일 것이 없으면 `nil` 로 두고 줄을 만들지 않는다.
    public let detail: String?
    /// 목록에 보여줄 프로필. 설정을 못 읽으면 비어 있다.
    public let profiles: [NetworkProfile]
    /// 현재 구성과 일치하는 프로필 이름 (체크 표시)
    public let activeProfileName: String?
    /// 프로필을 눌러 전환할 수 있는 상태인가
    public let canSwitch: Bool
    /// 앱을 띄우자마자 **설정 창을 열어야** 하는 상태인가.
    ///
    /// 머리말이 '초기 설정하기' 인 것보다 **좁다.** 저 문구는 남은 일이 하나라도 있으면 나오지만,
    /// 창을 자동으로 여는 것은 아직 사용자의 값이 하나도 없을 때(파일 없음 · 예시 그대로)뿐이다.
    /// 권한 하나가 빠졌다는 이유로 로그인할 때마다 창이 튀어나오면 그것은 안내가 아니라 소음이다.
    public let needsSetup: Bool

    // 아래 세 값은 자동 전환(Phase 3)의 표시다. 위의 값들이 "지금 어떤 구성인가" 를 말한다면
    // 이 값들은 "누가 그렇게 만들고 있는가" 를 말한다.

    /// 자동 전환 토글에 딸린 보조 줄들. 지금 무엇을 보고 있고 왜 멈춰 있는지를 적는다.
    public private(set) var autoSwitchEnabled: Bool = false
    /// 토글 아래 보조 줄. 보통 한 줄이고, 알림까지 막혀 있으면 두 줄이다.
    ///
    /// **머리말이 이미 말한 것은 여기 오지 않는다** — 같은 말이 두 번 적히면 무엇이 상태이고
    /// 무엇이 조치인지 구분이 사라진다.
    public private(set) var autoSwitchNotes: [String] = []
    /// 자동 전환이 실패로 쉬거나 멈춰 있어, 지금 다시 시도할 손잡이를 내놓아야 하는가.
    ///
    /// 백오프·중단은 원래 **Wi-Fi 가 바뀌어야** 풀린다. 같은 자리에서 원인을 고친 사용자에게는
    /// 앱을 다시 띄우는 것 말고 길이 없다 — 그 막다른 골목을 여는 문이다.
    public private(set) var canRetryAutoSwitch: Bool = false
    /// 알림 설정을 열어달라는 항목을 보여야 하는가.
    ///
    /// 알림이 막히면 자동 전환은 완전히 무성이 된다. 그래서 상태(`- 알림 꺼짐`)와 조치를 함께 낸다.
    public private(set) var needsNotificationPermission: Bool = false

    /// 초기 설정에서 아직 남아 있는 것. 비어 있으면 사용자가 할 일이 없다.
    ///
    /// 비어 있지 않다고 늘 머리말이 '초기 설정하기' 인 것은 아니다 — 전환 중이거나 방금 실패했거나
    /// 설정 파일이 깨진 **문제 상황**은 그쪽이 먼저 말한다.
    public private(set) var setupGaps: [SetupGap] = []

    public static func resolve(_ input: StatusInput) -> StatusModel {
        let setupGaps = SetupChecklist.gaps(input)
        var model = resolveNetworkState(input, setupGaps: setupGaps)
        model.setupGaps = setupGaps
        model.autoSwitchEnabled = input.autoSwitchEnabled
        model.canRetryAutoSwitch = input.autoSwitchEnabled && isStalled(input.autoSwitchHold)
        model.needsNotificationPermission = input.autoSwitchEnabled && input.notifications == .denied
        model.autoSwitchNotes = menuNotes(input, model: model)
        return model
    }

    /// 자동 전환이 스스로 빠져나오지 못하는 상태인가.
    ///
    /// `ineffective` 도 포함한다. 적용은 되는데 구성이 따라오지 않는 상황은 사용자가 밖에서
    /// 손을 본 뒤(다른 도구 종료·시스템 설정 정리) 다시 눌러 볼 만한 자리다.
    private static func isStalled(_ hold: AutoSwitchHold?) -> Bool {
        switch hold {
        case .backoff?, .givenUp?, .ineffective?: return true
        default: return false
        }
    }

    private static func resolveNetworkState(_ input: StatusInput, setupGaps: [SetupGap]) -> StatusModel {
        let profiles: [NetworkProfile]
        if case .ready(let config) = input.config { profiles = config.profiles } else { profiles = [] }

        let active = activeProfile(config: input.config, interface: input.interface)
        let observedIcon = icon(for: input.interface, active: active)

        // 1) 진행 중이거나 방금 실패한 동작이 가장 먼저다.
        switch input.action {
        case .switching(let profile):
            return StatusModel(
                icon: observedIcon,
                headline: "\(displayName(of: profile, in: profiles)) 로 전환 중…",
                detail: nil,
                profiles: profiles,
                activeProfileName: active?.name,
                canSwitch: false,
                needsSetup: false
            )
        case .failed(let profile, let message):
            return StatusModel(
                icon: .error,
                headline: "전환 실패 — \(displayName(of: profile, in: profiles))",
                detail: clip(message),
                profiles: profiles,
                activeProfileName: active?.name,
                canSwitch: true,
                needsSetup: false
            )
        case .idle:
            break
        }

        // 2) 설정 파일이 깨진 것은 **초기 설정이 남은 것이 아니라 고장이다.**
        //    할 일을 적을 자리가 아니므로 먼저 답하고, 이유를 그대로 보여준다
        //    (전문은 설정 창이 들고, 여기는 한 줄까지만).
        if case .unusable(_, let reason) = input.config {
            return StatusModel(
                icon: .error, headline: "설정 파일 오류",
                detail: clip(reason),
                profiles: [], activeProfileName: nil, canSwitch: false, needsSetup: false
            )
        }

        // 3) 초기 설정이 아직 안 끝났다.
        //
        // 권한이 없어서 안 되는 것과 값이 없어서 안 되는 것은 앱에게는 다른 일이지만,
        // 사용자에게는 똑같이 "아직 내가 할 일이 남았다" 이다. **그래서 머리말 하나로 묶는다** —
        // 여기 무엇이 들어가는지는 `SetupChecklist` 한 자리가 정한다.
        //
        // 이 상태의 머리말은 **상태가 아니라 할 일**을 적는다. 메뉴의 첫 줄은 눌러서 설정 창을
        // 여는 자리인데(`MenuStyle.headline`), 상태만 적어 두면 그 줄이 문이라는 것이 읽히지 않는다.
        // 절차는 여기 적지 않는다 — 어떻게 하는지는 그 문을 열면 나오는 설정 창이 말한다.
        if !setupGaps.isEmpty {
            // 아이콘도 머리말과 같은 편에 선다. 메뉴를 열지 않아도 보이는 것이 아이콘이라,
            // 머리말이 '할 일이 남았다' 인 동안 아이콘만 정상으로 두면 두 표시가 어긋난다.
            //
            // 전환은 **눌러서 될 때만** 열어 둔다. 권한이 빠진 채로 열어 두면 누를 때마다 실패한다.
            // 반대로 Wi-Fi 이름만 없는 상태는 수동 전환에 아무 문제가 없다 — 그대로 열어 둔다.
            let canSwitch = !profiles.isEmpty && input.helperInstalled && input.sudoersInstalled
            return StatusModel(
                icon: .error,
                headline: "초기 설정하기",
                detail: SetupChecklist.shortfall(setupGaps, interface: input.interface),
                profiles: profiles,
                activeProfileName: active?.name,
                canSwitch: canSwitch,
                // 창을 자동으로 여는 것은 값이 아직 사용자의 것이 아닐 때뿐이다 (`needsSetup` 주석).
                needsSetup: setupGaps.contains(.profiles) || setupGaps.contains(.exampleProfiles)
            )
        }

        // 4) 현재 구성을 읽지 못한 경우. 전환 자체는 막지 않는다.
        guard let interface = input.interface else {
            return StatusModel(
                icon: .error,
                headline: "현재 구성 읽기 실패",
                detail: clip(input.interfaceError),
                profiles: profiles,
                activeProfileName: nil,
                canSwitch: true,
                needsSetup: false
            )
        }

        // 5) 정상 경로
        if let active {
            return StatusModel(
                icon: observedIcon,
                headline: "\(active.displayName) 적용 중",
                detail: summary(of: interface),
                profiles: profiles,
                activeProfileName: active.name,
                canSwitch: true,
                needsSetup: false
            )
        }
        return StatusModel(
            icon: observedIcon,
            headline: "프로필 없음 — \(methodText(interface.configMethod))",
            detail: summary(of: interface),
            profiles: profiles,
            activeProfileName: nil,
            canSwitch: true,
            needsSetup: false
        )
    }

    // MARK: - 자동 전환 표시

    /// 자동 전환 토글 아래에 실제로 **올릴** 보조 줄들.
    ///
    /// 자동 전환은 눈에 보이지 않게 일한다. 켜져 있는데 조용하면 사용자는 고장과 구분할 수 없다 —
    /// 그래서 평소에도 "지금 무엇을 보고 있는지" 한 줄은 남긴다.
    ///
    /// 다만 **머리말이 이미 말한 것은 여기 오지 않는다** (설정 필요 · 전환 권한 미설치).
    /// 같은 말이 두 번 적히면 무엇이 상태이고 무엇이 조치인지 구분이 사라진다.
    private static func menuNotes(_ input: StatusInput, model: StatusModel) -> [String] {
        guard input.autoSwitchEnabled else { return [] }

        var notes: [String] = []
        switch input.autoSwitchHold {
        case .configUnavailable?, .helperNotInstalled?:
            break  // 머리말과 그 보조 줄이 이미 말했다
        default:
            if let reason = autoSwitchReason(input.autoSwitchHold, ssid: input.ssid, profiles: model.profiles) {
                notes.append(reason)
            }
        }
        // 알림이 막히면 전환이 완전히 무성이 된다. 조치('알림 설정 열기…')만으로는
        // **지금 무슨 일이 일어나고 있는지**가 읽히지 않으므로 상태도 한 줄 남긴다.
        if model.needsNotificationPermission { notes.append("알림 꺼짐") }
        return notes.compactMap(clip)
    }

    /// 자동 전환이 지금 **무엇을 보고 있는가 · 왜 멈춰 있는가**. 짧은 명사구 하나.
    ///
    /// 메뉴와 `--diagnose` 가 이 한 자리를 나눠 쓴다. 메뉴는 다른 항목이 대신 말하는 것을
    /// 걷어내(`menuNote`) 쓰지만, 진단에는 전부 필요하다 — 거기서는 폭이 아니라 사실이 중요하다.
    public static func autoSwitchReason(
        _ hold: AutoSwitchHold?,
        ssid: SSIDReading?,
        profiles: [NetworkProfile]
    ) -> String? {
        func label(_ name: String) -> String { displayName(of: name, in: profiles) }

        switch hold {
        case .none, .busy?, .alreadyApplied?, .settling?:
            // 평소 상태. 무엇을 보고 있는지만 알려준다.
            return ssid?.statusText
        case .disabled?:
            return nil
        case .locationPermissionRequired?:
            return "위치 권한 미승인"
        case .locationPermissionDenied?:
            return "위치 권한 없음"
        case .wifiOff?:
            return "Wi-Fi 꺼짐"
        case .notAssociated?:
            return "Wi-Fi 미접속"
        case .ssidUnavailable?:
            return "Wi-Fi 이름 읽기 실패"
        case .configUnavailable?:
            return "설정 필요"
        case .helperNotInstalled?:
            return "전환 권한 미설치"
        case .noMatchingProfile?:
            return "일치하는 프로필 없음"
        case .manualOverride(let profile)?:
            return "\(label(profile)) 수동 선택 유지"
        case .ineffective(let profile)?:
            return "\(label(profile)) 적용 후에도 구성 그대로"
        case .backoff(_, let retryAt)?:
            return "재시도 \(clockText(retryAt))"
        case .givenUp(let profile, let failures)?:
            return "\(label(profile)) 전환 \(failures)회 실패 후 중단"
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // 초까지 적으면 그만큼 줄이 길어진다. 다시 시도할 시각은 분 단위면 충분하다.
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static func clockText(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    // MARK: - 조각

    private static func activeProfile(config: ConfigStatus, interface: InterfaceInfo?) -> NetworkProfile? {
        guard case .ready(let config) = config, let interface else { return nil }
        return config.profiles.first { interface.conforms(to: $0) }
    }

    private static func icon(for interface: InterfaceInfo?, active: NetworkProfile?) -> MenuBarIcon {
        if let active { return active.mode == .manual ? .manual : .dhcp }
        guard let interface else { return .error }
        switch interface.configMethod {
        case .manual, .manualWithDHCPRouter: return .manual
        case .dhcp, .bootp: return .dhcp
        case .unknown: return .error
        }
    }

    private static func displayName(of profileName: String, in profiles: [NetworkProfile]) -> String {
        profiles.first { $0.name == profileName }?.displayName ?? profileName
    }

    private static func methodText(_ method: IPv4ConfigMethod) -> String {
        switch method {
        case .manual: return "고정 IP"
        case .dhcp: return "DHCP"
        case .manualWithDHCPRouter: return "고정 IP + DHCP 라우터"
        case .bootp: return "BOOTP"
        case .unknown(let raw): return raw
        }
    }

    /// 둘째 줄에 쓰는 현재 값 요약. 자기 기기의 값이므로 그대로 보여준다.
    private static func summary(of interface: InterfaceInfo) -> String? {
        guard let ip = interface.ip else { return "IP 주소 없음" }
        guard let router = interface.router else { return ip.description }
        return "\(ip) → \(router)"
    }

    /// 시스템이 준 원문을 메뉴 한 줄에 맞게 줄인다.
    ///
    /// 자르는 것이 아깝지만, 자르지 않으면 **그 한 줄이 메뉴 전체 폭을 정한다.**
    /// 전문을 들고 있는 자리가 따로 있으므로(`lineLimit` 주석) 여기서 잃는 것은 없다.
    private static func clip(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard line.count > lineLimit else { return line }
        return line.prefix(lineLimit - 1) + "…"
    }
}
