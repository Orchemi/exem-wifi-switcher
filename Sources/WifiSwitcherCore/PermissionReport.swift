import Foundation

/// 이 도구가 필요로 하는 권한 넷.
///
/// 넷을 한자리에 모으는 이유: 흩어져 있으면 **무엇이 막혀서 안 되는지** 를 사용자가 조립해야 한다.
/// 메뉴바 아이콘이 보이지 않는 환경에서는 설정 창이 사실상 유일한 출입구라 더 그렇다.
public enum PermissionSubject: String, CaseIterable, Sendable {
    /// `apply` + sudoers 무암호 규칙 — 없으면 전환 자체가 안 된다
    case switching
    /// `save-config` + 관리자 계정 — 없으면 값을 저장할 수 없다
    case saving
    /// 위치 권한 — 없으면 Wi-Fi 이름을 못 읽어 자동 전환이 성립하지 않는다
    case location
    /// 알림 권한 — 없어도 전환은 되지만 조용해진다
    case notification

    /// 화면에 적는 이름. 판정과 같은 자리에 둔다 — 화면이 제 나름의 이름을 붙이지 않게.
    public var title: String {
        switch self {
        case .switching: return "전환 권한"
        case .saving: return "설정 저장 권한"
        case .location: return "위치 권한"
        case .notification: return "알림 권한"
        }
    }

    /// 왜 이 권한이 필요한가. **설명 없는 권한 요구는 의심스럽게 보인다** —
    /// 특히 Wi-Fi 도구가 위치 권한을 달라고 할 때 그렇다.
    ///
    /// 판정이 아니라 주제의 성질이므로 상태와 무관하게 늘 같다.
    public var purpose: String {
        switch self {
        case .switching:
            return "IP 구성을 바꾸려면 관리자 권한이 필요합니다. 설치 때 등록한 규칙으로 전환할 때는 암호를 묻지 않습니다."
        case .saving:
            return "설정 파일은 root 소유라 저장할 때 관리자 인증을 한 번 받습니다. 전환할 때는 묻지 않습니다."
        case .location:
            return "macOS 는 Wi-Fi 이름을 위치 정보로 다룹니다. 이 권한이 없으면 사내인지 아닌지 판단하지 못합니다."
        case .notification:
            return "전환한 사실을 알립니다. 없어도 전환은 되지만 IP 가 언제 바뀌었는지 알 수 없습니다."
        }
    }
}

/// 한 항목의 판정.
public enum PermissionState: Equatable, Sendable {
    /// 갖춰졌다
    case satisfied
    /// 사용자가 무언가 해야 한다
    case actionNeeded
    /// 아직 정해지지 않았거나(승인 창을 아직 안 띄움) 여기서 확인할 수 없다.
    /// **문제로 세지 않는다** — 곧 정해질 상태를 경고로 칠하면 경고가 값싸진다
    case undetermined
}

/// 시스템 설정에서 열어야 하는 자리.
public enum SystemSettingsPane: Equatable, Sendable {
    case locationServices
    case notifications

    /// 해당 화면으로 바로 가는 딥링크.
    public var url: String {
        switch self {
        case .locationServices:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .notifications:
            return "x-apple.systempreferences:com.apple.preference.notifications"
        }
    }

    /// 딥링크가 열리지 않는 경우를 위해 글로도 적어 둔다.
    public var displayPath: String {
        switch self {
        case .locationServices: return "시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스"
        case .notifications: return "시스템 설정 > 알림"
        }
    }
}

/// 항목이 어긋났을 때 앱이 내놓을 수 있는 손잡이.
public enum PermissionRemedy: Equatable, Sendable {
    case none
    /// 앱 안에서 설치한다 — 무엇을 설치할지 먼저 보여주고, 관리자 인증을 받아
    /// **번들 안의 `install.sh` 를 그대로** 실행한다 (터미널로 하는 것과 같은 스크립트)
    case install
    /// 터미널에서 직접 실행해야 한다. 번들 안에 설치 스크립트가 없을 때의 길이다
    case runCommand(String)
    case openSettings(SystemSettingsPane)
}

/// 권한 한 줄.
public struct PermissionItem: Equatable, Sendable {
    public let subject: PermissionSubject
    public let state: PermissionState
    /// 지금 상태. 짧게 한 마디.
    public let status: String
    /// 무엇을 하면 되는가. 갖춰졌으면 nil.
    public let advice: String?
    public let remedy: PermissionRemedy

    /// 이름과 목적은 주제에서 파생한다 — 항목마다 다시 적지 않는다.
    public var title: String { subject.title }
    public var purpose: String { subject.purpose }

    /// 화면에 붙는 설명 한 줄 — 어긋났으면 조치를, 아니면 왜 필요한지를 적는다.
    /// 둘을 함께 쌓으면 네 항목이 여덟 줄이 된다.
    public var note: String { advice ?? purpose }

    /// `--diagnose` 한 줄. 화면과 **같은 판정에서** 나온다.
    public var diagnosticText: String {
        guard let advice else { return status }
        return "\(status) — \(advice)"
    }
}

/// 판정에 들어가는 관측값 전부. 시스템을 읽는 일은 이 구조체를 채우는 쪽(`PermissionProbe`)에 있다.
public struct PermissionInput: Equatable, Sendable {
    /// `apply` 스크립트가 실행 가능한 상태로 놓여 있는가
    public var applyInstalled: Bool
    /// sudoers 무암호 규칙 파일이 있는가. 스크립트만 있고 규칙이 없으면 전환할 때마다 암호를 묻는다
    public var sudoersInstalled: Bool
    public var saveConfigInstalled: Bool
    /// 지금 계정이 관리자 그룹인가. 아니면 설정 저장이 원리상 불가능하다
    public var isAdministrator: Bool
    /// 번들 안에 설치 스크립트가 있는가. 없으면(번들 밖 실행) 앱이 설치를 대신할 수 없다
    public var installerAvailable: Bool
    public var location: LocationAuthorizationState
    public var notifications: NotificationPermission

    public init(
        applyInstalled: Bool,
        sudoersInstalled: Bool,
        saveConfigInstalled: Bool,
        isAdministrator: Bool,
        installerAvailable: Bool,
        location: LocationAuthorizationState,
        notifications: NotificationPermission
    ) {
        self.applyInstalled = applyInstalled
        self.sudoersInstalled = sudoersInstalled
        self.saveConfigInstalled = saveConfigInstalled
        self.isAdministrator = isAdministrator
        self.installerAvailable = installerAvailable
        self.location = location
        self.notifications = notifications
    }
}

/// 권한 점검 결과 전부.
///
/// **판정은 여기 한 곳에만 있다.** 설정 창과 `--diagnose` 가 이 값을 나눠 쓴다 —
/// 두 곳이 각자 판단하면 같은 시스템을 두고 다른 답을 내놓는 날이 온다.
public struct PermissionReport: Equatable, Sendable {

    /// 번들 밖에서 실행 중일 때 안내하는 명령. 그때는 앱이 설치를 대신할 수 없다.
    public static let installCommand = "./scripts/install.sh"

    public let items: [PermissionItem]

    /// 앱이 제거를 대신할 수 있는 상태인가.
    ///
    /// 하나라도 설치돼 있으면 제거 대상이 있다는 뜻이다 — 반쯤 설치된 상태도 정리 대상이다.
    /// 설치 화면과 달리 항목별 조치가 아니라 섹션 전체에 붙는 손잡이라 여기서 따로 답한다.
    public let canUninstall: Bool

    public func item(_ subject: PermissionSubject) -> PermissionItem {
        // 항목은 항상 넷 다 만든다 — 없는 항목을 조회하는 경로가 생기지 않는다.
        items.first { $0.subject == subject }!
    }

    /// 사용자가 손봐야 할 것이 있는가. `undetermined` 는 세지 않는다.
    public var needsAttention: Bool {
        items.contains { $0.state == .actionNeeded }
    }

    public static func resolve(_ input: PermissionInput) -> PermissionReport {
        PermissionReport(
            items: [
                switching(input),
                saving(input),
                location(input),
                notification(input),
            ],
            canUninstall: input.installerAvailable
                && (input.applyInstalled || input.saveConfigInstalled || input.sudoersInstalled)
        )
    }

    /// 설치가 필요할 때 내놓을 손잡이와 그 설명.
    ///
    /// 앱이 설치할 수 있으면 버튼 하나로 끝난다. 번들 밖에서 돌고 있으면 그럴 수 없으므로
    /// 터미널 명령을 내민다 — **할 수 없는 것을 할 수 있는 척하지 않는다.**
    private static func installRemedy(_ input: PermissionInput) -> (advice: String, remedy: PermissionRemedy) {
        guard input.installerAvailable else {
            return (
                "터미널에서 \(installCommand) 를 실행하세요. (앱 번들 밖에서 실행 중이라 여기서 설치할 수 없습니다)",
                .runCommand(installCommand)
            )
        }
        // 이 문구는 설정 창과 `--diagnose` 가 함께 쓴다. 터미널에는 누를 버튼이 없으므로
        // "아래 버튼" 이 아니라 **버튼이 어디 있는지**를 적는다 — 두 자리에서 다 맞는 말이어야 한다.
        return (
            "설정 창의 [설치] 를 누르면, 무엇을 설치할지 보여주고 관리자 인증을 한 번 받습니다.",
            .install
        )
    }

    // MARK: - 전환 권한

    private static func switching(_ input: PermissionInput) -> PermissionItem {
        let install = installRemedy(input)
        guard input.applyInstalled else {
            return PermissionItem(
                subject: .switching,
                state: .actionNeeded,
                status: "설치되지 않음",
                advice: install.advice,
                remedy: install.remedy
            )
        }
        // 스크립트만 있고 규칙이 없으면 겉보기에는 설치된 상태다. 전환할 때마다 암호를 물어 실패한다.
        guard input.sudoersInstalled else {
            return PermissionItem(
                subject: .switching,
                state: .actionNeeded,
                status: "무암호 규칙 없음",
                advice: "전환 스크립트는 있지만 sudoers 규칙이 없어 전환이 실패합니다. " + install.advice,
                remedy: install.remedy
            )
        }
        return PermissionItem(
            subject: .switching,
            state: .satisfied,
            status: "설치됨",
            advice: nil,
            remedy: .none
        )
    }

    // MARK: - 설정 저장 권한

    private static func saving(_ input: PermissionInput) -> PermissionItem {
        guard input.saveConfigInstalled else {
            let install = installRemedy(input)
            return PermissionItem(
                subject: .saving,
                state: .actionNeeded,
                status: "설치되지 않음",
                advice: install.advice,
                remedy: install.remedy
            )
        }
        // 설치로 해결되지 않는 상태다. 실행해도 달라지지 않을 명령을 내밀지 않는다.
        guard input.isAdministrator else {
            return PermissionItem(
                subject: .saving,
                state: .actionNeeded,
                status: "이 계정으로는 저장 불가",
                advice: "지금 계정이 관리자 그룹이 아닙니다. 설치로는 해결되지 않습니다 — "
                    + "관리자 계정에서 값을 저장하세요.",
                remedy: .none
            )
        }
        return PermissionItem(
            subject: .saving,
            state: .satisfied,
            status: "설치됨",
            advice: nil,
            remedy: .none
        )
    }

    // MARK: - 위치 권한

    private static func location(_ input: PermissionInput) -> PermissionItem {
        switch input.location {
        case .granted:
            return PermissionItem(
                subject: .location,
                state: .satisfied,
                status: "허용됨",
                advice: nil,
                remedy: .none
            )
        case .denied:
            return PermissionItem(
                subject: .location,
                state: .actionNeeded,
                status: "거부됨",
                advice: "Wi-Fi 이름을 읽지 못해 자동 전환이 멈춰 있습니다. "
                    + "\(SystemSettingsPane.locationServices.displayPath)에서 허용하세요.",
                remedy: .openSettings(.locationServices)
            )
        case .notDetermined:
            return PermissionItem(
                subject: .location,
                state: .undetermined,
                status: "아직 묻지 않음",
                advice: "자동 전환을 켜면 승인 창이 뜹니다. 창을 닫았다면 "
                    + "\(SystemSettingsPane.locationServices.displayPath)에서 허용하세요.",
                remedy: .openSettings(.locationServices)
            )
        }
    }

    // MARK: - 알림 권한

    private static func notification(_ input: PermissionInput) -> PermissionItem {
        switch input.notifications {
        case .allowed:
            return PermissionItem(
                subject: .notification,
                state: .satisfied,
                status: "허용됨",
                advice: nil,
                remedy: .none
            )
        case .denied:
            return PermissionItem(
                subject: .notification,
                state: .actionNeeded,
                status: "거부됨",
                advice: "전환 알림이 뜨지 않아 전환 사실이 메뉴에만 남습니다. "
                    + "\(SystemSettingsPane.notifications.displayPath)에서 허용하세요.",
                remedy: .openSettings(.notifications)
            )
        case .pending:
            return PermissionItem(
                subject: .notification,
                state: .undetermined,
                status: "아직 묻지 않음",
                advice: "앱을 실행하면 승인 창이 뜹니다.",
                remedy: .none
            )
        case .unavailable:
            // 번들 밖에서 실행 중이다. 사용자가 할 수 있는 일이 없으므로 버튼을 내밀지 않는다.
            return PermissionItem(
                subject: .notification,
                state: .undetermined,
                status: "확인 불가",
                advice: "앱 번들 밖에서 실행 중입니다.",
                remedy: .none
            )
        }
    }
}
