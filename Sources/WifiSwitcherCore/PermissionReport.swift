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
    ///
    /// **여기 적는 것은 두 가지뿐이다 — 왜 필요한가, 그리고 무엇을 대가로 치르는가**
    /// (관리자 인증 한 번 · 위치 정보를 어디에 쓰는가). **앱이 어떻게 동작하는지는 적지 않는다.**
    /// 바로 옆에 [설치] 버튼이 있는데 "[설치] 를 누르면…" 이라고 적는 것은 화면이 제 이야기를
    /// 자기가 하는 꼴이다. 무엇을 설치하는지는 그 버튼을 눌렀을 때 계획 창이 전부 보여준다.
    public var purpose: String {
        switch self {
        case .switching:
            return "네트워크 구성을 바꾸려면 관리자 권한이 필요합니다. 설치할 때 관리자 인증을 한 번 받고, 이후 전환할 때는 묻지 않습니다."
        case .saving:
            return "입력한 값은 관리자 권한으로 실행되는 명령에 그대로 쓰이므로, 아무나 고칠 수 없는 자리에 둡니다. 저장할 때 관리자 인증을 한 번 받습니다."
        case .location:
            return "macOS 는 Wi-Fi 이름을 위치 정보로 다룹니다. 사내인지 아닌지는 이 이름으로만 알 수 있어, 자동 전환에는 이 권한이 필요합니다."
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
///
/// **주소는 여기 한 곳에만 있다.** 메뉴·설정 창·알림 문구가 모두 이 타입을 거친다 —
/// 같은 주소를 여러 자리에 적어 두면 한쪽만 고쳐진 채 조용히 갈라진다.
public enum SystemSettingsPane: Equatable, Sendable {
    case locationServices
    case notifications
    /// 로그인 시 자동 실행. 앱이 놓은 LaunchAgent 를 **macOS 가 여기서 꺼 버릴 수 있다.**
    case loginItems

    /// 해당 화면으로 바로 가는 딥링크.
    ///
    /// 권한 두 곳은 옛 환경설정 식별자(`com.apple.preference.*`)를 그대로 쓴다. 시스템 설정이
    /// 갈린 뒤에도 각 화면이 `legacyBundleIdentifier` 로 이 이름을 달고 있어 지금도 그대로 열린다.
    /// 로그인 항목은 옛 이름이 없어 새 확장 식별자를 쓴다.
    ///
    /// 셋 다 macOS 26.5 에서 창 제목으로 확인했다 —
    /// 알림 → '알림' · 위치 → '위치 서비스' · 로그인 항목 → '로그인 항목 및 확장 프로그램'.
    public var url: String {
        switch self {
        case .locationServices:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .notifications:
            return "x-apple.systempreferences:com.apple.preference.notifications"
        case .loginItems:
            return "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        }
    }

    /// 그 화면에서 **우리 앱을 바로 지목할 수 있는가.**
    ///
    /// 알림만 된다. 앱마다 자기 화면이 따로 있어 `?id=` 로 그 화면을 곧장 열 수 있다.
    /// 나머지 둘은 목록 하나가 화면 전체라 지목할 자리가 없다.
    public var revealsApp: Bool {
        if case .notifications = self { return true }
        return false
    }

    /// 우리 앱의 줄을 펴 놓고 여는 딥링크.
    ///
    /// **알림 화면은 설치된 앱이 전부 늘어선 긴 목록이다.** 거기에 떨어뜨려 놓고 이름을 찾아
    /// 스크롤하게 두면, 권한을 켜라고 안내해 놓고 정작 그 자리는 알아서 찾으라는 말이 된다.
    /// `?id=<번들 식별자>` 를 붙이면 그 앱의 화면이 바로 열린다 (macOS 26.5 에서 확인 —
    /// 창 제목이 앱 이름으로 바뀌고 목록을 스크롤하지 않아도 된다).
    ///
    /// **다른 화면에는 붙이지 않는다.** 위치 서비스에 질의를 덧붙이면 앵커가 깨져
    /// 상위 '개인정보 보호 및 보안' 으로 떨어지는 것을 실측했다 — 지금보다 나빠진다.
    /// 식별자를 모르는 경우(번들 밖 실행)에도 화면까지는 열어 준다.
    public func url(revealing bundleIdentifier: String?) -> String {
        guard revealsApp, let bundleIdentifier, !bundleIdentifier.isEmpty else { return url }
        return "\(url)?id=\(bundleIdentifier)"
    }

    /// 딥링크가 열리지 않는 경우를 위해 글로도 적어 둔다.
    public var displayPath: String {
        switch self {
        case .locationServices: return "시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스"
        case .notifications: return "시스템 설정 > 알림"
        case .loginItems: return "시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램"
        }
    }

    /// 목록이 늘어선 순서. 지목할 수 없는 화면에서 **사용자가 쓸 수 있는 단서는 이것뿐이다.**
    ///
    /// macOS 26.5 의 위치 서비스·로그인 항목 목록에서 확인했다 — 앱이 이름순으로 늘어선다.
    /// 어디쯤을 봐야 하는지를 알면 목록을 처음부터 훑지 않아도 된다.
    static let listOrder = "이름순"

    /// 목록만 열리는 화면에서 **무엇을 어디쯤에서 찾아야 하는지.**
    ///
    /// 지목할 수 없다는 사실을 인정하고, 대신 찾는 수고를 줄이는 사실을 준다.
    /// 목록 앞에 사용자를 세워 두고 아무 말도 하지 않는 것은 절반만 안내한 것이다.
    ///
    /// **이보다 더 해줄 방법이 없다는 것을 확인했다** (macOS 26.5). 다시 시도하지 않도록 적어 둔다.
    ///   - **한 줄을 지목·강조·깜빡이게 하는 공개 수단이 없다.** 이 화면에 질의를 덧붙이면
    ///     앵커가 깨져 상위 화면으로 떨어진다(실측). 시스템 설정이 여는 앵커는
    ///     `Privacy_LocationServices` 처럼 **서비스 단위**이고, 앱 단위 앵커는 존재하지 않는다
    ///   - **검색창으로도 목록이 좁혀지지 않는다.** 시스템 설정 검색은 각 설정 화면이 함께
    ///     들고 있는 **정적 색인**(`…/*.appex/Contents/Resources/*.lproj/*.searchTerms`)을 본다.
    ///     그 안에는 설정 항목의 제목과 키워드만 있고 목록에 뜨는 앱 이름은 없다 —
    ///     검색이 맞혀 봐야 도착지는 우리가 이미 여는 그 화면이다
    ///   - 그래서 **앱 이름을 클립보드에 복사해 두지 않는다.** 붙여넣을 자리가 없는데
    ///     사용자가 담아 둔 것만 덮게 된다
    ///   - 시스템 설정 UI 를 대신 조작하는 길(접근성·자동화)은 **쓰지 않는다.** 권한 하나를
    ///     편히 켜자고 '다른 앱을 제어할 권한' 을 더 받는 것은 앞뒤가 맞지 않는다
    public var listHint: String? {
        revealsApp ? nil : "\(Self.listOrder) 목록에서 '\(InstallPaths.appName)' 를 찾으세요"
    }

    /// "…에서 허용하세요" 한 마디. 지목할 수 없는 화면이면 찾을 이름까지 붙는다.
    ///
    /// 설정 창과 `--diagnose` 가 같은 문장을 쓴다 — 두 자리에서 다 맞는 말이어야 한다.
    public var openGuidance: String {
        guard let listHint else { return "\(displayPath)에서 허용하세요." }
        return "\(displayPath)에서 허용하세요 — \(listHint)."
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
    /// 앱이 위치 권한 승인 창을 띄운다.
    ///
    /// 아직 묻지 않은 상태에서만 쓴다. 이때는 **시스템 설정까지 보낼 이유가 없다** —
    /// 목록에서 우리 줄을 찾게 하는 대신 창 하나로 끝난다.
    /// (한 번 거부한 뒤에는 이 창이 다시 뜨지 않으므로 그때는 `openSettings` 다)
    case requestLocationPermission
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

    /// 화면에 붙는 설명 한 줄 — 조치가 따로 있으면 그것을, 아니면 왜 필요한지를 적는다.
    /// 둘을 함께 쌓으면 네 항목이 여덟 줄이 된다.
    ///
    /// **버튼이 대신 말하는 조치는 `advice` 에 넣지 않는다.** 옆에 [설치] 가 있는데
    /// "[설치] 를 누르면…" 이라고 적으면 같은 말이 두 번 있는 것이고, 정작 **왜 필요한지**를
    /// 적을 자리가 그 문장에 밀려 사라진다.
    public var note: String { advice ?? purpose }

    /// `--diagnose` 한 줄. 화면과 **같은 판정에서** 나온다.
    ///
    /// 터미널에는 누를 버튼이 없다 — 화면에서 버튼이 대신 말하던 몫까지 글로 적어야 하므로,
    /// 손볼 것이 있으면 화면과 같은 설명 줄(`note`)을 함께 싣는다.
    public var diagnosticText: String {
        guard state != .satisfied else { return status }
        return "\(status) — \(note)"
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
    /// 지금 Wi-Fi 이름을 실제로 읽고 있는가.
    ///
    /// **이것이 위치 권한의 물증이다.** `CLLocationManager` 는 만든 직후 아직 정해지지 않은 값을
    /// 돌려주고 실제 상태는 조금 뒤 델리게이트로 온다. 그 사이의 값을 그대로 옮기면
    /// "위치 권한 아직 묻지 않음" 과 "Wi-Fi 이름 읽음" 이 한 화면에 함께 찍힌다.
    /// 둘 중 하나는 틀렸고, 틀린 쪽은 권한 표시다.
    public var wifiNameVisible: Bool
    public var notifications: NotificationPermission

    public init(
        applyInstalled: Bool,
        sudoersInstalled: Bool,
        saveConfigInstalled: Bool,
        isAdministrator: Bool,
        installerAvailable: Bool,
        location: LocationAuthorizationState,
        wifiNameVisible: Bool,
        notifications: NotificationPermission
    ) {
        self.applyInstalled = applyInstalled
        self.sudoersInstalled = sudoersInstalled
        self.saveConfigInstalled = saveConfigInstalled
        self.isAdministrator = isAdministrator
        self.installerAvailable = installerAvailable
        self.location = location
        self.wifiNameVisible = wifiNameVisible
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
    ///
    /// 버튼을 내놓을 수 있는 쪽은 **설명을 달지 않는다**(`advice == nil`). 버튼이 곧 조치이고,
    /// 그 자리에 남는 한 줄은 "왜 이 권한이 필요한가"(`purpose`) 여야 한다.
    private static func installRemedy(_ input: PermissionInput) -> (advice: String?, remedy: PermissionRemedy) {
        guard input.installerAvailable else {
            return (
                "터미널에서 \(installCommand) 를 실행하세요. (앱 번들 밖에서 실행 중이라 여기서 설치할 수 없습니다)",
                .runCommand(installCommand)
            )
        }
        return (nil, .install)
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
        // 이쪽은 **상태만 봐서는 알 수 없는 사실**이라 한 줄을 남긴다 (설치 절차가 아니라 증상이다).
        guard input.sudoersInstalled else {
            return PermissionItem(
                subject: .switching,
                state: .actionNeeded,
                status: "무암호 규칙 없음",
                advice: [
                    "전환 스크립트는 있지만 무암호 규칙이 없어 전환할 때마다 암호를 물어 실패합니다.",
                    install.advice,
                ].compactMap { $0 }.joined(separator: " "),
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
        // 이름이 읽히고 있다면 권한은 있는 것이다. 관측된 사실이 아직 정해지지 않은 상태 값을 이긴다 —
        // **모순된 두 줄을 나란히 찍는 것보다 나쁜 표시는 없다.**
        if input.location == .notDetermined, input.wifiNameVisible {
            return PermissionItem(
                subject: .location,
                state: .satisfied,
                status: "허용됨",
                advice: nil,
                remedy: .none
            )
        }
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
                    + SystemSettingsPane.locationServices.openGuidance,
                remedy: .openSettings(.locationServices)
            )
        case .notDetermined:
            // 아직 묻지 않았으면 **묻는 것이 답이다.** 시스템 설정 목록으로 보내고 우리 줄을
            // 찾게 하는 것은, 창 하나면 끝날 일을 굳이 어렵게 만드는 것이다.
            return PermissionItem(
                subject: .location,
                state: .undetermined,
                status: "아직 묻지 않음",
                advice: nil,
                remedy: .requestLocationPermission
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
                    + SystemSettingsPane.notifications.openGuidance,
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
