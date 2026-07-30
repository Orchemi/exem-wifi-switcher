import AppKit
import WifiSwitcherCore

/// 설정 창. 첫 실행의 온보딩과 나중의 값 수정이 같은 창이다.
///
/// 창을 두 개로 나눌 이유가 없었다 — 첫 실행에서 하는 일(고정 IP 값을 적는다)과
/// 나중에 하는 일이 같기 때문이다. 다른 것은 맨 위의 안내 한 줄뿐이다.
///
/// 검증은 이 파일에 없다. `ManualProfileDraft` 가 판단하고, 여기서는 그 결과를
/// 해당하는 칸 아래에 옮겨 적기만 한다.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    private let onSaved: () -> Void
    /// 위치 권한 상태를 가진 쪽(`LocationAuthority`)에 그때그때 물어본다.
    /// 값을 복사해 두면 시스템 설정에 다녀온 뒤에도 옛 답을 보여준다.
    private let locationAuthorization: @MainActor () -> LocationAuthorizationState
    /// 위치 권한 승인 창을 띄워 달라고 부탁하는 길. `CLLocationManager` 는 앱에 하나뿐이라
    /// (`LocationAuthority`) 여기서 새로 만들지 않고 그 자리에 부탁한다.
    private let requestLocationPermission: @MainActor () -> Void

    private let introLabel = SettingsWindowController.makeWrappingLabel(
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )
    private let servicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ipField = SettingsWindowController.makeField(placeholder: "192.0.2.10")
    private let subnetField = SettingsWindowController.makeField(placeholder: "255.255.255.0")
    private let routerField = SettingsWindowController.makeField(placeholder: "192.0.2.1")
    // 이 창이 편집하는 것은 **고정 IP(office) 프로필**이다. 거기에는 DNS 를 알려줄 DHCP 가 없으므로
    // 비워 두면 이름 해석이 통째로 끊긴다 — 안내 문구가 비우도록 유도하면 안 된다.
    private let dnsField = SettingsWindowController.makeField(placeholder: "필수 · 쉼표로 구분 (예: 192.0.2.53, 192.0.2.54)")
    // **이 칸이 자동 전환의 방아쇠다.** 여기 적힌 이름의 Wi-Fi 에 붙으면 위 값들이 적용된다.
    // 비워 두면 값이 다 맞아도 자동 전환은 이 프로필을 고르지 못한다 — 그 사실을 자리표시자에 적는다.
    private let ssidField = SettingsWindowController.makeField(
        placeholder: "비우면 자동 전환 안 함"
    )
    /// 이 칸을 **채울 수 있게 만드는** 버튼. 위치 권한이 없으면 나타난다.
    ///
    /// 예전에는 이 자리에 "권한이 없어 읽지 못했습니다… 직접 입력해도 됩니다" 라는 안내가 붙었다.
    /// 위치 권한이 필수가 된 지금 그 문장은 틀린 길을 알려주는 것이고, 맞는 길(권한을 받는 것)은
    /// 아래 권한 섹션까지 내려가야 있었다. **그 길을 이 칸 옆으로 가져온다** — 안내 문장 대신
    /// 누르면 되는 것을 둔다. 무엇을 해야 하는지는 버튼 이름이 말한다.
    private let ssidPermissionButton = NSButton(title: "", target: nil, action: nil)

    private var errorLabels: [DraftField: NSTextField] = [:]
    private var errorRows: [DraftField: NSGridRow] = [:]
    /// 네트워크 서비스 줄. **평소에는 숨어 있다** — 이 도구는 Wi-Fi 이름으로 판단하므로
    /// 고를 이유가 없다. Wi-Fi 서비스를 못 찾은 기기에서만 드러난다.
    private var serviceRow: NSGridRow?
    /// Wi-Fi 이름 칸이 지금 편집 가능한가. **판단은 `SSIDFieldState` 가 한다** —
    /// 여기서는 그 답을 화면에 옮기기만 한다 (잠그는 조건과 그 이유는 그 타입에 적혀 있다).
    private var isSSIDEditable = true
    /// Wi-Fi 이름 칸이 놓인 줄. 잠기면 칸의 테두리를 지우므로, 테두리가 차지하던 자리를
    /// 이 줄의 여백으로 대신 채운다 (`lockedFieldInsets`).
    private var ssidRow: NSStackView?
    /// 테두리가 글자 둘레에 두던 여백. 테두리를 지운 자리에 그대로 돌려준다.
    ///
    /// **테두리를 지운 것이 자리에는 아무 영향도 주지 않아야 한다** — 값의 왼쪽 끝도,
    /// 글자가 앉는 높이도, 줄의 높이도 편집 가능할 때와 같아야 한다. 한쪽만 맞추면
    /// 이 줄만 낮아져 아래 칸들과의 간격이 어긋난다.
    ///
    /// 숫자로 박지 않고 **테두리가 있는 동안 칸에게 물어** 잰다 (지운 뒤에는 잴 수 없다).
    private var lockedFieldInsets = NSEdgeInsets()
    /// Wi-Fi 서비스를 못 찾았을 때만 남는 안내. 저장 실패 문구와 같은 줄을 쓰므로
    /// 상태로 들고 있다가 그 문구를 지울 때 되돌린다.
    private var serviceNotice: String?

    /// **빈 칸이 있으면 누를 수 없다.** 아직 아무것도 적지 않은 사람에게 칸마다 오류를 붙이는 것은
    /// 틀린 값을 적었을 때 할 말이지 지금 할 말이 아니다 (`ManualProfileDraft.hasRequiredValues`).
    private let saveButton = NSButton(title: "저장", target: nil, action: nil)

    private let loginItemCheckbox = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)
    /// 체크상자를 누른 결과. **자리는 늘 잡혀 있고 글자만 들고 난다** (`showLoginItemStatus`).
    private let loginItemStatusLabel = SettingsWindowController.makeWrappingLabel(
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )
    /// 잠깐 띄운 글자를 지울 일. 다시 누르면 앞의 것을 걷어낸다 — 남아 있으면 새로 띄운 글자를 지운다.
    private var loginItemStatusDismissal: Task<Void, Never>?
    /// 로그인 항목 화면으로 가는 손잡이. macOS 가 이 항목을 껐는지 확인하고 되돌릴 수 있는 유일한 자리다.
    private let loginItemSettingsButton = NSButton(title: "로그인 항목 열기…", target: nil, action: nil)
    private let noticeLabel = SettingsWindowController.makeWrappingLabel(
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )

    private let permissionGrid = NSGridView(views: [])
    /// 항목마다 같은 뷰를 계속 쓴다 — 갱신할 때마다 새로 만들면 열 너비가 그때그때 달라진다.
    private var permissionRows: [PermissionSubject: PermissionRowViews] = [:]
    /// 설명 줄. **갖춰진 항목에서는 통째로 숨긴다** — 빈 줄로 두면 그만큼 여백만 남는다.
    private var permissionNoteRows: [PermissionSubject: NSGridRow] = [:]
    /// 지금 화면에 그려진 판정. 버튼이 무엇을 해야 하는지 여기서 찾는다.
    private var permissionReport: PermissionReport?
    /// 마지막으로 시작한 권한 읽기. 겹쳐 들어온 읽기 중 이 번호의 결과만 화면에 옮긴다.
    private var permissionReadToken = 0
    /// 설치한 것을 되돌리고 **앱 번들까지 휴지통으로 보내는** 손잡이.
    ///
    /// 권한 머리말 옆의 작은 [제거…] 였을 때는 하는 일이 설치물 정리뿐이었고, 누른 사람에게
    /// 앱을 지웠다는 느낌이 남지 않았다. 이름을 키운 만큼 하는 일도 키웠으므로
    /// (`AppRemoval`) 자리도 창 전체에 걸리는 파괴적 동작의 자리, 곧 **아래쪽 왼편**으로 옮긴다.
    /// 보이는 조건은 그대로다 (설치된 것이 있을 때만).
    private let removeAppButton = NSButton(title: AppRemoval.footerButtonTitle, target: nil, action: nil)
    /// 설치·제거가 도는 동안 같은 일을 두 번 걸지 않는다.
    private var isRunningInstaller = false

    private var observation = Observation.pending
    private var hasBeenShown = false
    /// 시스템 설정으로 보냈다가 돌아오는 길. 되돌릴 자리인지 판단하는 것은 이쪽이다
    /// (`SystemSettingsTrip` — 조건과 그 이유가 거기 적혀 있다).
    private var systemSettingsTrip = SystemSettingsTrip()
    /// 이번 닫기는 미저장을 묻지 않는다 ([취소] · 저장 직후).
    private var skipsUnsavedPrompt = false
    /// 방금 저장한 내용. **설정 파일을 다시 읽기 전까지의 기준**이다 —
    /// 저장하자마자 [저장] 이 죽어야 하는데, 그때 관측은 아직 옛 파일을 들고 있다.
    /// 파일이 따라잡으면 스스로 내려놓는다 (`populate`).
    private var justSaved: (draft: ManualProfileDraft, service: String)?

    /// 창 너비와 라벨 열 너비를 못박는다.
    ///
    /// 열 너비를 내용에 맡기면, 오류 문구가 나타나는 순간 그 문구의 길이가 열 너비를 밀어
    /// 라벨·입력 칸이 통째로 움직인다. 값이 틀렸다는 것을 알려주면서 화면이 흔들릴 이유는 없다.
    private static let windowWidth: CGFloat = 460
    private static let margin: CGFloat = 20
    private static let labelColumnWidth: CGFloat = 116
    private static let columnSpacing: CGFloat = 10
    private static var fieldColumnWidth: CGFloat {
        windowWidth - margin * 2 - labelColumnWidth - columnSpacing
    }
    /// 권한 설명이 줄바꿈되는 폭. 입력 칸과 같은 열에 놓이므로 같은 값이다.
    fileprivate static var noteWidth: CGFloat { fieldColumnWidth }

    init(
        locationAuthorization: @escaping @MainActor () -> LocationAuthorizationState,
        requestLocationPermission: @escaping @MainActor () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.locationAuthorization = locationAuthorization
        self.requestLocationPermission = requestLocationPermission
        self.onSaved = onSaved

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowController.windowWidth, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(InstallPaths.appName) 설정"
        window.isReleasedWhenClosed = false
        // 창 높이(`level`)는 보통 창 그대로 둔다. 다른 앱이 이 창을 덮는 것은 정상이고,
        // 특히 우리가 열어 준 시스템 설정을 이 창이 가리고 서면 안 된다 (2026-07-29 실기에서
        // `.floating` 이 거부된 자리다). 덮인 뒤에 돌아오는 길은 `observeSystemSettingsReturn` 이 맡는다.
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        observeApplicationActivation()
        observeSystemSettingsReturn()
    }

    /// 시스템 설정에 다녀와 앱으로 돌아오면 권한과 로그인 항목을 다시 확인한다.
    ///
    /// 이것이 없으면 사용자가 권한을 허용하고 돌아와도 창은 "거부됨" 을 계속 보여준다 —
    /// 고친 사람에게 안 고쳐졌다고 말하는 셈이다. **로그인 항목도 같은 성질이다** —
    /// [로그인 항목 열기…] 로 나가서 켜고 돌아오는 길이 있고, 그때 "macOS 가 꺼 두었습니다" 가
    /// 남아 있으면 방금 켠 사람에게 아직 꺼져 있다고 말하게 된다.
    ///
    /// 이 컨트롤러는 앱이 살아 있는 동안 유지되므로 관찰을 따로 떼지 않는다.
    private func observeApplicationActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.window?.isVisible == true else { return }
                self.refreshPermissions()
                self.showLoginItemState()
            }
        }
    }

    /// 우리가 보낸 시스템 설정이 사라지면 설정 창을 그 자리로 되돌린다.
    ///
    /// 이 앱은 `.accessory` 라 Dock 아이콘이 없다. 설정 창이 시스템 설정 뒤로 밀린 뒤 시스템 설정이
    /// 닫히면, macOS 는 **그 다음 앱**을 앞세울 뿐 우리를 불러 주지 않는다 — 설정 창은 뒤에 묻힌 채
    /// 남고, 사용자에게는 창이 꺼진 것처럼 보인다. 실기에서 나온 말이 그것이다:
    /// "로그인 항목 설정창을 끄면 그대로 다시 앱 설정창이 보여야지".
    ///
    /// 신호는 **종료**다. 시스템 설정은 창을 닫으면 프로세스가 끝난다 (macOS 26.5 실측 —
    /// 창을 닫자 `didDeactivate` 뒤 60ms 안에 `didTerminate` 가 왔다). 비활성화를 신호로 삼으면
    /// 사용자가 다른 앱으로 잠깐 옮기기만 해도 창이 앞으로 튀어나온다.
    ///
    /// **되돌릴지 말지는 코어가 정한다** (`SystemSettingsTrip`) — 우리가 보낸 길인가, 창이 아직
    /// 열려 있는가, 이미 한 번 돌아왔는가. 여기서는 그 답을 창에 옮기기만 한다.
    private func observeSystemSettingsReturn() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = application?.bundleIdentifier
            Task { @MainActor in
                guard let self else { return }
                guard self.systemSettingsTrip.shouldBringWindowBack(
                    terminatedApp: bundleIdentifier,
                    isWindowOpen: self.window?.isVisible == true
                ) else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("스토리보드를 쓰지 않는다")
    }

    // MARK: - 표시

    func present(observation: Observation) {
        self.observation = observation
        // 이 창은 닫아도 살아 있다 (`isReleasedWhenClosed = false`). 지난번에 내려 둔
        // '묻지 않기' 를 그대로 물려받으면 다음 사람이 조용히 값을 잃는다.
        skipsUnsavedPrompt = false
        populate()
        // 창을 열 때마다 다시 확인한다 — 사용자가 시스템 설정에 다녀왔을 수 있다.
        refreshPermissions()
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: Self.windowWidth, height: 320))
        // 사용자가 옮겨 둔 창을 다시 가운데로 끌어오지 않는다.
        if !hasBeenShown {
            window?.center()
            hasBeenShown = true
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeFirstResponder(ipField)
    }

    private func populate() {
        // 설정 파일이 방금 저장한 것을 따라잡았으면 임시 기준을 내려놓는다.
        // 계속 들고 있으면 파일이 바깥에서 바뀌어도(CLI 로 고치는 길이 있다) 옛 기준으로 견주게 된다.
        if let justSaved, savedOfficeDraft?.matches(justSaved.draft) == true,
           observation.readyConfig?.service == justSaved.service {
            self.justSaved = nil
        }

        // 네트워크 서비스
        let services = observation.services.isEmpty ? ["Wi-Fi"] : observation.services
        servicePopUp.removeAllItems()
        servicePopUp.addItems(withTitles: services)
        let currentService = observation.readyConfig?.service ?? SystemProbe.preferredService(among: services)
        let serviceFound = services.contains(currentService)
        if serviceFound { servicePopUp.selectItem(withTitle: currentService) }
        // 이 도구는 Wi-Fi 이름으로 판단한다 — 서비스를 고를 이유가 없으므로 평소에는 감춘다.
        // 다만 그 서비스를 못 찾은 기기에서까지 감추면 손쓸 방법이 사라지므로 그때만 드러낸다.
        serviceRow?.isHidden = serviceFound

        // 값 — 이미 저장된 프로필이 있으면 그 값을, 없으면 현재 구성에서 제안한다.
        //
        // **저장된 값과 지금 구성을 읽어 채운 값은 화면에서 같아 보인다.** 사내에서 창을 열면
        // 다섯 칸이 저절로 차는데, 그것은 아직 `config.json` 에 없는 값이다 — 실기에서
        // 그 화면을 보고 설정이 끝난 줄 알았고 메뉴만 계속 '초기 설정하기' 였다.
        // 둘을 가르는 것은 머리말이 맡는다 (`SettingsIntro`).
        if let saved = savedOfficeDraft {
            // 저장해 둔 값이 언제나 이긴다 — 사용자가 고쳐 둔 Wi-Fi 이름을 지금 붙어 있는 이름으로 덮지 않는다.
            fill(saved)
        } else {
            fill(currentConfigurationDraft ?? ManualProfileDraft())
        }
        refreshIntro()
        updateSaveAvailability()

        showLoginItemState()

        // 설치 안내와 '저장할 때 인증을 받는다' 는 이제 아래 권한 섹션이 말한다.
        // 같은 말을 두 자리에서 하면 어느 쪽이 최신인지 알 수 없게 된다.
        resolveSSIDField()

        serviceNotice = serviceFound ? nil : "Wi-Fi 서비스 없음 · 위에서 사용할 서비스 선택"

        clearIssues()
        showDNSReadFailureIfNeeded()
    }

    /// 저장된 사내 프로필의 값. **세 값이 다 있어야** 그 프로필을 보고 있다고 말할 수 있다.
    private var savedOfficeDraft: ManualProfileDraft? {
        guard let office = observation.readyConfig?.profiles.first(where: { $0.mode == .manual }),
              let ip = office.ip, let subnet = office.subnet, let router = office.router
        else { return nil }
        return ManualProfileDraft(
            ip: ip, subnet: subnet, router: router,
            dns: office.dns.joined(separator: ", "),
            ssids: office.ssids.joined(separator: ", ")
        )
    }

    /// 지금 시스템 구성에서 읽어낸 값. 고정 IP 로 돌고 있을 때만 나온다.
    private var currentConfigurationDraft: ManualProfileDraft? {
        observation.interface.flatMap {
            ManualProfileDraft.from($0, dns: observation.dnsServers, ssid: observation.ssid)
        }
    }

    /// 머리말을 지금 상태에 맞춘다. **저장 전인지 후인지가 여기서 갈린다.**
    private func refreshIntro() {
        var configFailure: String?
        if case .unusable(_, let reason) = observation.config { configFailure = reason }
        introLabel.stringValue = SettingsIntro.resolve(
            hasSavedProfile: savedOfficeDraft != nil,
            isOfficeConfiguration: observation.interface?.isManual == true,
            hasValues: !draft.isEmpty,
            configFailure: configFailure
        ).text
    }

    /// 지금 관측으로 Wi-Fi 이름 칸의 값과 잠금을 다시 정한다.
    ///
    /// **한 번만 정하면 안 된다.** 첫 실행에서는 창이 열리는 순간 위치 권한이 아직 없어
    /// 이름을 못 읽고, 이름은 사용자가 권한을 허용한 **뒤에** 들어온다. 그때 다시 정하지
    /// 않으면 자동으로 채워진 이름이 편집 가능한 채로 남는다.
    private func resolveSSIDField() {
        let state = SSIDFieldState.resolve(
            typed: ssidField.stringValue,
            reading: observation.ssid,
            interface: observation.interface
        )
        ssidField.stringValue = state.name
        isSSIDEditable = state.isEditable
        applySSIDLock()
    }

    /// 잠금 상태를 칸에 반영한다.
    ///
    /// **잠겼다는 것이 보여야 한다.** 글자색만 흐리게 하면 편집 가능한 칸과 구분되지 않아
    /// (실기에서 확인했다) 눌러도 아무 일 없는 고장으로 읽힌다. 그래서 테두리를 지운다 —
    /// **'적는 칸' 이 아니라 '적힌 값' 으로 보이게** 하는 것이 이 칸의 사실에 맞다.
    /// 모양이 그것을 말하므로 아래에 설명 줄을 따로 두지 않는다.
    ///
    /// 지운 테두리의 자리는 여백으로 그대로 채운다 — 잠겼다고 줄이 낮아지거나 값이 옆으로
    /// 밀리면, 잠금과 상관없는 어긋남이 하나 생긴다.
    private func applySSIDLock() {
        ssidField.isEditable = isSSIDEditable
        ssidField.isSelectable = true
        ssidField.isBezeled = isSSIDEditable
        if isSSIDEditable { ssidField.bezelStyle = .roundedBezel }
        ssidField.textColor = isSSIDEditable ? .labelColor : .secondaryLabelColor
        ssidRow?.edgeInsets = isSSIDEditable ? NSEdgeInsets() : lockedFieldInsets
    }

    /// 창이 열려 있는 동안 새 관측이 왔을 때 화면을 맞춘다.
    ///
    /// **위치 권한을 방금 허용한 순간이 이 경로의 이유다.** 그때 Wi-Fi 이름이 처음으로 읽히는데,
    /// 창을 다시 열기 전에는 칸이 빈 채로 남아 있었다 — 권한을 받아 놓고도 손으로 넣게 되는 셈이다.
    ///
    /// **사용자가 적어 둔 것은 건드리지 않는다.** 비어 있는 칸만, 그것도 **고정 IP 로 돌고
    /// 있을 때만** 채우고(사외에서 읽은 이름은 집·카페 이름이다), 채운 다음 **잠금을 다시
    /// 정한다** — 이 경로로 들어온 이름이 잠기지 않은 채 남는 것이 실기에서 나온 고장이다.
    /// 두 규칙 모두 `SSIDFieldState` 가 들고 있다.
    ///
    /// 다만 **사람이 적고 있는 중에는 손대지 않는다.** 적는 도중에 칸이 잠기면 그것이
    /// 곧 고장이다 (사내인데 권한이 없어 이름을 손으로 넣는 자리에서 벌어진다).
    /// 다 적고 칸을 떠나면 다음 관측이 잠근다.
    func update(observation: Observation) {
        self.observation = observation
        // 사내 Wi-Fi 에 붙는 순간이 이 경로다. **다섯 칸이 함께 찬다** — 이름만 채우고 나머지를
        // 두면 값을 손으로 옮겨 적게 된다 (창을 닫았다 다시 열어야 채워지던 것이 그 상태다).
        adoptCurrentConfiguration()
        if ssidField.currentEditor() == nil { resolveSSIDField() }
        // 값이 들어왔으면 머리말도, 저장 버튼도 따라가야 한다 —
        // '채울 것이 없음' 이 '아직 저장 안 됨' 이 되고, 못 누르던 [저장] 이 살아난다.
        refreshIntro()
        updateSaveAvailability()
        refreshPermissions()
    }

    /// 지금 시스템 구성으로 **비어 있는 칸만** 채운다.
    ///
    /// 고정 IP 로 돌고 있을 때만 값이 나온다(`ManualProfileDraft.from`) — 사외에서 읽은 값을
    /// 사내 프로필에 넣으면 그 자리에서 사내 고정 IP 가 걸린다.
    /// (Wi-Fi 이름 칸은 잠금까지 함께 정해야 해서 `resolveSSIDField()` 가 맡는다)
    ///
    /// **사람이 적어 둔 것은 초안이 지켜 준다** — 비어 있지 않은 칸은 `adopting` 이 그대로
    /// 돌려주므로 값이 같아 다시 쓰지 않는다. 그래서 여기서는 커서가 어디 있는지 보지 않는다.
    /// 창을 열면 IP 칸에 커서가 가 있어서(`present`), 커서를 기준으로 막으면 **정작 그 칸만
    /// 안 채워진다** — 미리보기에서 사외→사내 전환을 돌려 보고 잡았다.
    private func adoptCurrentConfiguration() {
        guard let current = currentConfigurationDraft else { return }
        let merged = draft.adopting(current)
        adopt(merged.ip, into: ipField)
        adopt(merged.subnet, into: subnetField)
        adopt(merged.router, into: routerField)
        adopt(merged.dns, into: dnsField)
    }

    private func adopt(_ value: String, into field: NSTextField) {
        guard field.stringValue != value else { return }
        field.stringValue = value
    }

    /// 저장할 수 있는 상태인지 버튼에 반영한다. 판단은 `canSave` 한 자리가 한다.
    private func updateSaveAvailability() {
        saveButton.isEnabled = canSave
    }

    /// 현재 DNS 설정을 **읽지 못했으면** 그 사실을 DNS 칸에 남긴다.
    ///
    /// 읽지 못한 것을 빈 칸으로 두면 사용자가 "원래 없구나" 로 읽는다. 고정 IP 프로필에서
    /// 그렇게 저장하면 이름 해석이 끊긴다. 조용히 넘어가지 않는다.
    private func showDNSReadFailureIfNeeded() {
        guard let reason = observation.dnsServers.failureReason,
              dnsField.stringValue.isEmpty,
              let label = errorLabels[.dns]
        else { return }
        label.textColor = .systemRed
        label.stringValue = "현재 DNS 를 읽지 못함 (\(reason)) · 직접 입력"
        errorRows[.dns]?.isHidden = false
    }

    private func fill(_ draft: ManualProfileDraft) {
        ipField.stringValue = draft.ip
        subnetField.stringValue = draft.subnet
        routerField.stringValue = draft.router
        dnsField.stringValue = draft.dns
        ssidField.stringValue = draft.ssids
    }

    private var draft: ManualProfileDraft {
        ManualProfileDraft(
            ip: ipField.stringValue,
            subnet: subnetField.stringValue,
            router: routerField.stringValue,
            dns: dnsField.stringValue,
            ssids: ssidField.stringValue
        )
    }

    // MARK: - 권한 점검

    /// 지금 상태를 다시 읽어 권한 섹션을 새로 그린다.
    ///
    /// 읽기는 백그라운드에서 한다 — 파일 확인과 `id -Gn` 이 메인 스레드를 잡으면 창이 굳는다.
    /// **판정은 하지 않는다.** 읽은 값을 `PermissionReport` 에 넘기고 결과만 옮겨 적는다
    /// (`--diagnose` 가 쓰는 것과 같은 판정이다).
    ///
    /// 창 밖에서도 부른다 — 위치 권한 답이 늦게 오면(`LocationAuthority`) 그때 다시 그려야
    /// 창에 낡은 판정이 남지 않는다.
    func refreshPermissions() {
        permissionReadToken += 1
        let token = permissionReadToken
        let location = locationAuthorization()
        // Wi-Fi 이름이 읽히고 있다는 것은 위치 권한이 있다는 물증이다. 판정에 함께 넘긴다.
        let wifiNameVisible = observation.ssid.name != nil
        Task { @MainActor in
            let report = PermissionReport.resolve(
                await PermissionProbe.read(location: location, wifiNameVisible: wifiNameVisible)
            )
            // 창을 여는 순간은 활성화되는 순간이기도 해서 읽기가 겹친다. 늦게 시작한 쪽이 먼저 끝나면
            // 낡은 답이 새 답을 덮으므로, 마지막으로 시작한 읽기만 화면에 옮긴다.
            guard token == permissionReadToken else { return }
            render(report)
        }
    }

    private func render(_ report: PermissionReport) {
        permissionReport = report
        for (index, item) in report.items.enumerated() {
            guard let row = permissionRows[item.subject] else { continue }
            row.status.stringValue = item.status
            // 색은 문제가 있을 때만 쓴다. 다 갖춰진 화면을 초록으로 도배하지 않는다.
            row.status.textColor = item.state == .actionNeeded ? .systemOrange : .labelColor
            // 갖춰진 항목에는 설명이 없다 — 이미 해결된 일을 계속 읽힐 이유가 없다.
            row.note.stringValue = item.note ?? ""
            permissionNoteRows[item.subject]?.isHidden = item.note == nil

            switch item.remedy {
            case .none:
                row.button.isHidden = true
            case .install:
                row.button.isHidden = false
                row.button.title = "설치"
            case .openSettings:
                row.button.isHidden = false
                row.button.title = "설정 열기"
            case .runCommand(let command):
                row.button.isHidden = false
                row.button.title = "명령 복사"
                row.note.stringValue = Self.keepingWhole(command, in: item.note ?? "")
            case .requestLocationPermission:
                row.button.isHidden = false
                row.button.title = "허용 요청"
            }
            row.button.isEnabled = !isRunningInstaller
            row.button.tag = index
        }
        renderSSIDPermissionButton(report.item(.location))
        // 지울 것이 있을 때만 선다. 판정은 권한 표와 같은 자리에서 온다 (`canUninstall`).
        removeAppButton.isHidden = !report.canUninstall
        setRemoveAppButtonEnabled(!isRunningInstaller)
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: Self.windowWidth, height: 320))
    }

    /// 빨간 글자는 직접 칠한 것이라 **꺼졌을 때 흐려지는 것도 직접 해야 한다** —
    /// 그러지 않으면 누를 수 없는 동안에도 평소와 똑같이 선명하게 서 있다.
    private func setRemoveAppButtonEnabled(_ enabled: Bool) {
        removeAppButton.isEnabled = enabled
        applyRemoveAppButtonTitle(enabled: enabled)
    }

    private func applyRemoveAppButtonTitle(enabled: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        removeAppButton.attributedTitle = NSAttributedString(
            string: AppRemoval.footerButtonTitle,
            attributes: [
                .foregroundColor: enabled ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .paragraphStyle: paragraph,
            ]
        )
    }

    /// Wi-Fi 이름 칸 옆의 권한 버튼. **판정은 권한 표에서 그대로 가져온다** —
    /// 여기서 상태를 다시 읽으면 같은 화면 안에서 두 자리가 어긋날 수 있다.
    ///
    /// 아직 묻지 않았으면 승인 창을, 거부했으면 시스템 설정을 연다. 허용돼 있으면 버튼이 사라진다 —
    /// 할 일이 없는 자리에 버튼을 남겨 두면 무언가 덜 된 것처럼 보인다.
    private func renderSSIDPermissionButton(_ location: PermissionItem) {
        switch location.remedy {
        case .requestLocationPermission:
            ssidPermissionButton.isHidden = false
            ssidPermissionButton.title = "위치 권한 허용"
        case .openSettings:
            ssidPermissionButton.isHidden = false
            ssidPermissionButton.title = "위치 권한 열기…"
        case .none, .install, .runCommand:
            ssidPermissionButton.isHidden = true
        }
        ssidPermissionButton.toolTip = ssidPermissionButton.isHidden ? nil : (location.details ?? location.note)
    }

    /// 칸 옆 버튼이 하는 일도 권한 표의 조치 그대로다.
    @objc private func performSSIDPermissionAction() {
        guard let remedy = permissionReport?.item(.location).remedy else { return }
        perform(remedy)
    }

    /// 명령이 줄 끝에서 잘리지 않게 한다.
    ///
    /// 자동 줄바꿈은 `/` 와 `.` 에서 줄을 끊는다. 그러면 `./scripts/` 와 `install.sh` 가 따로 놓여
    /// **명령이 두 조각으로 읽힌다.** 사용자가 그대로 옮겨 적어야 하는 문자열이므로 붙여 둔다.
    /// 화면에만 넣는 표시이고, 복사 버튼은 원래 문자열을 그대로 넘긴다.
    private static func keepingWhole(_ command: String, in text: String) -> String {
        let joiner = "\u{2060}"  // WORD JOINER — 폭이 없고 줄바꿈만 막는다
        let unbreakable = command
            .replacingOccurrences(of: "/", with: joiner + "/" + joiner)
            .replacingOccurrences(of: ".", with: joiner + "." + joiner)
        return text.replacingOccurrences(of: command, with: unbreakable)
    }

    /// 항목이 내놓은 손잡이를 그대로 실행한다.
    @objc private func performPermissionAction(_ sender: NSButton) {
        guard let report = permissionReport, report.items.indices.contains(sender.tag) else { return }
        perform(report.items[sender.tag].remedy, confirmingOn: sender)
    }

    private func perform(_ remedy: PermissionRemedy, confirmingOn button: NSButton? = nil) {
        switch remedy {
        case .none:
            break
        case .install:
            beginInstaller(.install)
        case .openSettings(let pane):
            open(pane)
        case .runCommand(let command):
            guard let button else { return }
            copyToPasteboard(command, confirmingOn: button)
        case .requestLocationPermission:
            // 답이 오면 `LocationAuthority` 가 알려주고, 그 길로 이 창이 다시 그려진다
            // (`update(observation:)` — 그때 Wi-Fi 이름 칸도 채워진다).
            requestLocationPermission()
        }
    }

    @objc private func performAppRemoval() {
        beginInstaller(.uninstall)
    }

    @objc private func openLoginItemsSettings() {
        open(.loginItems)
    }

    /// 시스템 설정의 해당 화면을 연다.
    ///
    /// 알림은 우리 앱의 줄을 편 채로 열린다 (`url(revealing:)`). 나머지는 목록이 열리므로,
    /// 무엇을 찾아야 하는지는 각 항목의 안내 문구(`openGuidance`)가 미리 말해 둔다.
    ///
    /// **여기가 이 창에서 시스템 설정으로 나가는 유일한 문이다** — [로그인 항목 열기…] ·
    /// 권한 표의 [설정 열기] · Wi-Fi 이름 칸 옆의 [위치 권한 열기…] 가 모두 이 자리를 지난다.
    /// 그래서 보냈다는 사실도 여기서 적어 둔다 — 셋 다 같은 길이기 때문이다:
    /// **이 창에서 나가 시스템 설정에서 무언가 켜고, 이 창으로 돌아온다.**
    private func open(_ pane: SystemSettingsPane) {
        guard let url = URL(string: pane.url(revealing: Bundle.main.bundleIdentifier)) else { return }
        guard NSWorkspace.shared.open(url) else { return }
        systemSettingsTrip.didOpenSystemSettings()
    }

    /// 복사는 눈에 보이는 변화가 없다. 눌렀는데 아무 일도 없으면 안 된 줄 안다.
    private func copyToPasteboard(_ text: String, confirmingOn button: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let previousTitle = button.title
        button.title = "복사됨"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard button.title == "복사됨" else { return }
            button.title = previousTitle
        }
    }

    // MARK: - 앱 안에서 설치·제거

    /// 무엇을 할지 먼저 보여주고 확인을 받은 다음에야 관리자 인증으로 넘어간다.
    ///
    /// 계획은 앱이 지어내지 않는다 — 실행할 바로 그 스크립트의 `--dry-run` 출력이다.
    private func beginInstaller(_ operation: BundledInstaller.Operation) {
        guard !isRunningInstaller else { return }
        isRunningInstaller = true
        setInstallerControlsEnabled(false)

        Task { @MainActor in
            let outcome = await InstallerService.preview(operation)
            switch outcome {
            case .failure(let failure):
                isRunningInstaller = false
                setInstallerControlsEnabled(true)
                present(failure, operation: operation)
            case .success(let preview):
                confirm(preview, operation: operation)
            }
        }
    }

    private func confirm(_ preview: InstallerService.Preview, operation: BundledInstaller.Operation) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = operation == .install
            ? "전환 권한을 설치합니다"
            : AppRemoval.confirmationTitle
        alert.informativeText = operation == .install
            ? "관리자 인증을 한 번 받습니다. 아래가 설치할 내용 전부입니다."
            : AppRemoval.confirmationBody
        // 제거 계획에는 앱이 한 줄을 덧붙인다. 스크립트는 "앱 번들은 직접 지우세요" 라고 적는데,
        // 이 창에서 부르는 길에서는 앱이 번들까지 휴지통으로 옮기므로 그 말이 거짓이 된다
        // (`AppRemoval.planAddendum` — 스크립트는 고치지 않는다. 터미널에서는 여전히 참이다).
        alert.accessoryView = InstallPlanView.make(
            operation == .install ? preview.plan : AppRemoval.plan(preview.plan)
        )

        let confirmButton = alert.addButton(
            withTitle: operation == .install ? operation.title : AppRemoval.confirmButtonTitle
        )
        if operation == .uninstall { confirmButton.hasDestructiveAction = true }
        alert.addButton(withTitle: "취소")
        // 앱에서 하는 설치가 막혔을 때의 출구. 기본 동선은 위 버튼이다.
        alert.addButton(withTitle: "터미널 명령 복사")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.runInstaller(operation)
            case .alertThirdButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(preview.terminalCommand, forType: .string)
                self.finishInstaller()
            default:
                self.finishInstaller()
            }
        }
    }

    private func runInstaller(_ operation: BundledInstaller.Operation) {
        // 인증 창이 뜨는 동안 메인 스레드가 멈춘다 (설정 저장과 같은 경로다).
        let result = InstallerService.run(operation)
        finishInstaller()
        refreshPermissions()

        // 삭제는 스크립트가 끝난 뒤에도 할 일이 남는다 (번들을 휴지통으로 옮기고 종료한다).
        if operation == .uninstall {
            completeAppRemoval(result)
            return
        }

        switch result {
        case .success:
            presentInstallSuccess()
        case .cancelled:
            // 취소는 실패가 아니다. 아무것도 바뀌지 않았다는 사실만 알린다.
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "인증을 취소해서 \(operation.title)하지 않았습니다"
            alert.informativeText = "시스템은 그대로입니다."
            alert.addButton(withTitle: "확인")
            show(alert)
        case .failed(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "\(operation.title)하지 못했습니다"
            alert.informativeText = message
            alert.addButton(withTitle: "확인")
            alert.addButton(withTitle: "터미널 명령 복사")
            let command = BundledInstaller.terminalCommand(
                scriptPath: InstallerService.scriptPath(for: operation)
            )
            show(alert) { response in
                guard response == .alertSecondButtonReturn else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
    }

    /// 설치가 끝났을 때. **삭제는 여기로 오지 않는다** (`completeAppRemoval`).
    private func presentInstallSuccess() {
        // **권한을 다 갖춘 이 순간이 사람을 놓치는 자리다.** 설치가 끝나면 끝난 것처럼 느껴지는데
        // 값은 아직 설정 파일에 없다 (사내에서는 칸이 저절로 차 있어 더 그렇게 보인다).
        // 그래서 여기서 남은 한 걸음을 말하고, **그 자리에서 저장까지 갈 수 있게** 한다.
        if canSave {
            offerSaveAfterInstall()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "설치했습니다"
        alert.informativeText = "이제 프로필을 전환할 때 암호를 묻지 않습니다. "
            + "설정 값을 저장할 때는 관리자 인증을 한 번 받습니다."
        alert.addButton(withTitle: "확인")
        show(alert)
    }

    // MARK: - 앱 삭제

    /// 제거 스크립트가 끝난 뒤. **여기서 앱이 자기 번들을 처분한다.**
    ///
    /// 설치물을 지우는 것은 전부 `scripts/uninstall.sh` 가 한다 (그 절차를 여기서 흉내 내지
    /// 않는다). 스크립트가 할 수 없는 것이 하나 남는데, 사용자가 둔 자리에 있는 앱 번들이다.
    /// 그 하나만 앱이 맡는다 — 옮기는 것도 지우는 것이 아니라 **휴지통으로 보내는 것**이라
    /// 잘못 눌러도 되돌릴 수 있다.
    ///
    /// 무엇을 말할지는 `AppRemoval` 이 정한다. 두 단계가 각각 실패할 수 있어
    /// **한 일과 다른 말을 하기 가장 쉬운 자리**이기 때문이다.
    private func completeAppRemoval(_ result: ConfigInstaller.AuthorizationResult) {
        switch result {
        case .cancelled:
            present(AppRemoval.message(for: .cancelled))
        case .failed(let message):
            // 스크립트가 멈춘 자리다. 번들은 건드리지 않는다.
            present(AppRemoval.message(for: .scriptFailed(reason: message)))
        case .success:
            // 로그인 항목은 macOS 가 들고 있어 셸 스크립트가 끌 수 없다 (파일이 아니다).
            // 번들을 지우면 macOS 가 함께 정리하지만, 휴지통 이동이 실패해 앱이 남는 길도 있다.
            // 그때 다음 로그인에 다시 뜨지 않도록 **여기서 먼저 끈다.**
            try? LoginItem.disable()
            showLoginItemState()
            moveAppBundleToTrash()
        }
    }

    /// 실행 중인 자기 번들을 휴지통으로 옮긴다.
    ///
    /// 경로는 `Bundle.main.bundleURL` 에서 온다 — 문자열로 조립하지 않는다.
    /// `rm` 을 쓰지 않는 이유는 하나다: 되돌릴 수 없다.
    private func moveAppBundleToTrash() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundleURL]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // 읽기 전용 볼륨·남의 계정 소유·`/Applications` 권한 등. 삼키지 않는다.
                    self.present(AppRemoval.message(for: .appBundleRemains(
                        path: PathDisplay.abbreviate(bundleURL.path),
                        reason: error.localizedDescription
                    )), revealing: bundleURL)
                    return
                }
                self.present(AppRemoval.message(for: .removed))
            }
        }
    }

    /// 삭제 결과를 옮겨 적는다. 어떤 버튼을 둘지도 `AppRemoval.Message` 가 이미 답해 두었다.
    private func present(_ message: AppRemoval.Message, revealing bundleURL: URL? = nil) {
        let alert = NSAlert()
        alert.alertStyle = message.isWarning ? .warning : .informational
        alert.messageText = message.title
        alert.informativeText = message.body
        alert.addButton(withTitle: "확인")
        if message.offersFinderReveal { alert.addButton(withTitle: "Finder 에서 보기") }
        if message.offersTerminalCommand { alert.addButton(withTitle: "터미널 명령 복사") }

        let terminalCommand = BundledInstaller.terminalCommand(
            scriptPath: InstallerService.scriptPath(for: .uninstall)
        )
        show(alert) { [weak self] response in
            if response == .alertSecondButtonReturn {
                if message.offersFinderReveal, let bundleURL {
                    NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                } else if message.offersTerminalCommand {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(terminalCommand, forType: .string)
                }
                return
            }
            guard message.quitsAfterConfirmation else { return }
            // 앱을 지웠다고 말한 뒤에도 창이 남아 있으면 지운 것이 아니게 된다.
            // 나가는 길에 "저장하지 않고 닫을까요" 를 묻지 않는다 (저장할 자리를 방금 지웠다).
            self?.skipsUnsavedPrompt = true
            NSApp.terminate(nil)
        }
    }

    /// 설치 직후, 아직 저장되지 않은 값이 화면에 있을 때.
    ///
    /// 인증을 한 번 더 받는 값을 치르지만 **묻지 않고 대신 저장해 주지는 않는다** — 이 저장은
    /// root 소유 파일을 갈아 끼우는 일이라 누른 적 없는 사람에게 일어나면 안 된다.
    /// 대신 기본 버튼이 그 일을 하도록 두어 [Enter] 한 번으로 끝나게 한다.
    private func offerSaveAfterInstall() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "설치했습니다 · 한 걸음 남았습니다"
        alert.informativeText = "화면의 값은 아직 저장되지 않았습니다. 저장해야 사내 프로필이 되고 "
            + "자동 전환에 쓰입니다. 저장할 때 관리자 인증을 한 번 더 받습니다."
        alert.addButton(withTitle: "값 저장")
        alert.addButton(withTitle: "나중에")
        show(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.save()
        }
    }

    /// 계획을 못 받아 온 이유를 그대로 옮긴다. 사유마다 할 수 있는 일이 다르다.
    private func present(_ failure: InstallerService.PreviewFailure, operation: BundledInstaller.Operation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch failure {
        case .unavailable(let reason):
            alert.messageText = "앱에서 \(operation.title)할 수 없습니다"
            alert.informativeText = "\(reason)\n터미널에서 \(BundledInstaller.repositoryCommand(for: operation)) 를 실행하세요."
        case .altered(let reason):
            alert.messageText = "앱이 서명된 뒤 바뀌었습니다"
            alert.informativeText = "이 상태에서는 관리자 권한으로 실행하지 않습니다. "
                + "앱을 다시 내려받거나 다시 빌드하세요.\n\n\(reason)"
        case .refused(let reason):
            alert.messageText = "\(operation.title)할 수 없는 상태입니다"
            alert.informativeText = reason
        }
        alert.addButton(withTitle: "확인")
        show(alert)
    }

    private func finishInstaller() {
        isRunningInstaller = false
        setInstallerControlsEnabled(true)
    }

    private func setInstallerControlsEnabled(_ enabled: Bool) {
        setRemoveAppButtonEnabled(enabled)
        for row in permissionRows.values { row.button.isEnabled = enabled }
    }

    private func show(_ alert: NSAlert, then handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in handler?(response) }
    }

    // MARK: - 저장

    /// 칸이 바뀌면 저장 버튼도 따라간다.
    func controlTextDidChange(_ obj: Notification) {
        updateSaveAvailability()
    }

    @objc private func fieldChanged() {
        updateSaveAvailability()
    }

    @objc private func save() {
        clearIssues()

        let existing = observation.readyConfig
        // Wi-Fi 이름은 칸에 적힌 것만 쓴다 — 지운 이름이 옛 설정에서 되살아나지 않게.
        let result = draft.makeProfile(
            name: OnboardingSetup.officeProfileName,
            label: OnboardingSetup.officeProfileLabel
        )

        let office: NetworkProfile
        switch result {
        case .success(let profile):
            office = profile
        case .failure(let failure):
            show(failure)
            return
        }

        let service = servicePopUp.titleOfSelectedItem ?? "Wi-Fi"
        let config = OnboardingSetup.makeConfig(service: service, office: office, existing: existing)

        // 설정 파일은 root:wheel 0644 다. 저장은 관리자 인증을 한 번 받아 권한 스크립트가 처리한다.
        // (전환은 그대로 무암호다 — 인증을 받는 자리는 여기 하나뿐이다)
        do {
            try ConfigInstaller().save(config)
        } catch {
            presentSaveFailure(error)
            return
        }

        // 방금 저장한 것이 이제 기준이다. 관측(설정 파일 다시 읽기)이 도착하기 전까지
        // 이 값이 없으면 저장 직후에도 [저장] 이 살아 있고 닫을 때 '저장 안 했다' 고 묻는다.
        justSaved = (draft: draft, service: service)
        updateSaveAvailability()

        onSaved()
        closeWithoutAsking()
    }

    /// 지금 저장할 것이 있는가. **[저장] 버튼도, 닫을 때의 확인도 이 하나를 본다** —
    /// 두 자리가 다른 기준을 쓰면 저장할 것이 없는데 "저장하지 않고 닫습니다" 를 묻게 된다.
    ///
    /// 둘을 함께 만족해야 한다.
    ///   - **빈 칸이 없다** — 저장할 수 없는 상태에서는 놓칠 것도 없다
    ///   - **저장된 값과 다르다** — 방금 저장하고도 버튼이 살아 있으면, 무엇이 남았는지
    ///     버튼으로는 알 수 없게 된다
    private var canSave: Bool {
        draft.hasRequiredValues && (draft.isDirty(comparedTo: savedBaseline) || isServiceChanged)
    }

    /// 견줄 기준. 원칙은 **설정 파일에 있는 값**이고, 방금 저장한 값은 파일을 다시 읽기
    /// 전까지의 기준이다 (저장하자마자 버튼이 죽어야 한다).
    private var savedBaseline: ManualProfileDraft? {
        justSaved?.draft ?? savedOfficeDraft
    }

    /// 네트워크 서비스도 저장되는 값이다(`AppConfig.service`). 평소에는 감춰져 있지만
    /// Wi-Fi 서비스를 못 찾은 기기에서는 이 줄만 고치고 저장하는 일이 실제로 있다.
    ///
    /// 저장된 것이 아직 없으면 목록의 기본 선택은 사람이 고른 것이 아니므로 바뀐 것으로 보지 않는다.
    private var isServiceChanged: Bool {
        guard let saved = justSaved?.service ?? observation.readyConfig?.service else { return false }
        return (servicePopUp.titleOfSelectedItem ?? saved) != saved
    }

    private func closeWithoutAsking() {
        skipsUnsavedPrompt = true
        close()
    }

    /// 창을 닫으려 할 때 마지막으로 한 번 잡는다.
    ///
    /// [취소] 와 저장 직후는 묻지 않는다 — 버리겠다고 누른 사람에게 다시 묻는 것은 방해다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard canSave, !skipsUnsavedPrompt else { return true }
        confirmClosingWithUnsavedValues()
        return false
    }

    /// 창을 닫으면 시스템 설정에 다녀오던 길도 접는다.
    ///
    /// 창이 없으면 되돌릴 자리도 없다. 표식을 남겨 두면 나중에 창을 다시 연 뒤,
    /// 사용자가 직접 열어 본 시스템 설정을 닫을 때 창이 튀어나온다.
    func windowWillClose(_ notification: Notification) {
        systemSettingsTrip.didCloseWindow()
    }

    private func confirmClosingWithUnsavedValues() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "저장하지 않고 닫습니다"
        alert.informativeText = "화면의 값은 아직 설정 파일에 없습니다. "
            + "저장해야 사내 프로필이 되고 자동 전환에 쓰입니다."
        alert.addButton(withTitle: "저장하고 닫기")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "계속 편집")
        show(alert) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                // 저장이 성공하면 그 경로가 창을 닫는다. 실패하면 창이 남아 사유를 보여준다.
                self.save()
            case .alertSecondButtonReturn:
                self.closeWithoutAsking()
            default:
                break  // 계속 편집
            }
        }
    }

    /// 저장이 왜 안 됐는지, 그래서 지금 시스템이 어떤 상태인지 분명히 말한다.
    private func presentSaveFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = saveFailureTitle(error)
        alert.informativeText = "\(error)"
        alert.addButton(withTitle: "확인")
        alert.beginSheetModal(for: window!, completionHandler: nil)
    }

    private func saveFailureTitle(_ error: Error) -> String {
        guard let error = error as? ConfigInstaller.SaveError else { return "설정을 저장하지 못했습니다" }
        switch error {
        case .cancelled:
            return "인증을 취소해서 저장하지 않았습니다"
        case .notAdministrator:
            return "이 계정으로는 설정을 저장할 수 없습니다"
        case .helperMissing:
            return "전환 권한이 아직 설치되지 않았습니다"
        default:
            return "설정을 저장하지 못했습니다"
        }
    }

    @objc private func cancel() {
        // 버리겠다고 누른 사람에게 버려도 되냐고 다시 묻지 않는다.
        closeWithoutAsking()
    }

    // MARK: - 로그인 항목

    /// 이 체크상자는 **누르는 즉시 반영된다** — 아래 [저장] 과 아무 상관이 없다.
    /// 그런데 그 사실이 화면에 없어서, 옆의 [저장] 이 비활성인 것을 보고
    /// "이건 저장 안 해도 되나" 로 읽혔다. 그래서 눌린 결과를 그 자리에서 말한다.
    @objc private func toggleLoginItem(_ sender: NSButton) {
        let shouldRegister = sender.state == .on
        do {
            if shouldRegister { try LoginItem.enable() } else { try LoginItem.disable() }
        } catch {
            // 조용히 실패해서 켠 줄 알고 있는 것이 최악이다. 체크를 되돌리고 같은 자리에 알린다.
            sender.state = shouldRegister ? .off : .on
            showLoginItemStatus(
                shouldRegister ? "등록하지 못했습니다" : "해제하지 못했습니다",
                textColor: .systemRed,
                detail: "\(error)",
                dismissing: false
            )
            return
        }

        // **눌린 대로 됐다고 넘겨짚지 않고 다시 묻는다.** 켰는데 macOS 가 막아 두는 경우가 있고,
        // 그때 '등록됨' 이라고 말해 버리면 로그인해도 안 뜨는 이유를 영영 알 수 없다.
        showLoginItemState(after: shouldRegister ? .enabling : .disabling)
    }

    private enum LoginItemAction { case enabling, disabling }

    /// 시스템에게 상태를 묻고 체크상자와 아래 한 줄을 그린다.
    ///
    /// - Parameter action: 방금 사용자가 누른 것. `nil` 이면 창을 여는 길이라 결과 문구를 띄우지 않는다.
    private func showLoginItemState(after action: LoginItemAction? = nil) {
        let state = LoginItem.state
        loginItemCheckbox.state = state.isCheckedInUI ? .on : .off
        loginItemCheckbox.isEnabled = state.isToggleable

        // 지난번에 남긴 확인·실패 줄을 물려받지 않는다. 지금 화면은 지금 상태만 말한다.
        loginItemStatusDismissal?.cancel()
        loginItemStatusLabel.stringValue = ""
        loginItemStatusLabel.toolTip = nil

        switch state {
        case .blockedBySystem:
            // **지우지 않는다.** 이 줄이 사라지면 켜진 체크상자만 남고, 그것이 예전의 그 문제다 —
            // 앱은 켜졌다고 하는데 로그인하면 안 뜬다.
            showLoginItemStatus(
                "macOS 가 이 항목을 꺼 두었습니다 — [로그인 항목 열기…] 에서 켜세요",
                textColor: .systemOrange,
                dismissing: false
            )
        case .unavailable:
            showLoginItemStatus(
                "앱 번들로 실행할 때만 켤 수 있습니다",
                dismissing: false
            )
        case .on where action == .enabling:
            // 켠 것은 '됐다' 라서 표시(✓)를 얹는다.
            showLoginItemStatus(mark: "✓", "로그인 항목에 등록됨")
        case .off where action == .disabling:
            // 끈 것은 성공이라기보다 **상태 변화**라 표시를 얹지 않는다.
            showLoginItemStatus("로그인 항목에서 제거됨")
        case .on, .off:
            break
        }
    }

    /// 체크상자 아래 한 줄. **자리는 늘 잡아 두고 글자만 나타났다 사라진다** —
    /// 줄이 생겼다 없어지면 창 높이가 그때마다 출렁인다 (이 창이 오류 줄을 다루는 방식과 같다).
    ///
    /// **색은 표시(✓) 하나에만 얹는다.** 글자까지 물들이면 3초 뜨는 줄이 화면에서 가장 센 것이
    /// 된다. 초록을 흐리게 하는 길도 재 봤는데 **밝은 화면에서 읽기 어려워졌다** — 초록은
    /// 흰 바탕에서 이미 옅다. 그래서 양을 줄인다.
    ///
    /// - Parameters:
    ///   - detail: 한 줄에 담을 수 없는 사유. 툴팁으로 남긴다 — 짧은 말이 먼저고, 원문은 물어보면 나온다.
    ///   - dismissing: 잠깐 보였다 사라질 것인가. **실패는 지우지 않는다** — 못 봤는데 사라지면
    ///     켠 줄 알고 넘어간다. 다음에 다시 누를 때 새 결과가 덮는다.
    private func showLoginItemStatus(
        mark: String? = nil,
        _ text: String,
        textColor: NSColor = .secondaryLabelColor,
        detail: String? = nil,
        dismissing: Bool = true
    ) {
        // 연달아 누르면 앞의 타이머가 남아 방금 띄운 글자를 지운다. 먼저 걷어낸다.
        loginItemStatusDismissal?.cancel()

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let line = NSMutableAttributedString()
        if let mark {
            line.append(NSAttributedString(
                string: mark + " ",
                attributes: [.font: font, .foregroundColor: NSColor.systemGreen]
            ))
        }
        line.append(NSAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: textColor]
        ))
        loginItemStatusLabel.attributedStringValue = line
        loginItemStatusLabel.toolTip = detail

        guard dismissing else { return }
        loginItemStatusDismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.loginItemStatusLabel.stringValue = ""
            self.loginItemStatusLabel.toolTip = nil
        }
    }

    // MARK: - 오류 표시

    private func show(_ failure: DraftIssues) {
        for issue in failure.issues {
            guard let label = errorLabels[issue.field] else {
                // 칸으로 좁힐 수 없는 문제는 안내 줄에 남긴다 (조용히 삼키지 않는다).
                noticeLabel.isHidden = false
                noticeLabel.stringValue = issue.message
                continue
            }
            label.textColor = .systemRed
            label.stringValue = issue.message
            errorRows[issue.field]?.isHidden = false
        }
        if let first = failure.issues.first, let field = fieldControl(for: first.field) {
            window?.makeFirstResponder(field)
        }
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: Self.windowWidth, height: 320))
    }

    private func clearIssues() {
        for (field, label) in errorLabels {
            label.stringValue = ""
            errorRows[field]?.isHidden = true
        }
        // 안내 줄은 오류와 자리를 나눠 쓴다 — 오류를 지웠으면 그 자리로 돌아온다.
        noticeLabel.stringValue = serviceNotice ?? ""
        noticeLabel.isHidden = serviceNotice == nil
    }

    private func fieldControl(for field: DraftField) -> NSTextField? {
        switch field {
        case .ip: return ipField
        case .subnet: return subnetField
        case .router: return routerField
        case .dns: return dnsField
        case .ssids: return ssidField
        case .form: return nil
        }
    }

    // MARK: - 화면 구성

    private func makeContentView() -> NSView {
        let grid = NSGridView(views: [])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = Self.columnSpacing
        grid.rowSpacing = 8
        grid.rowAlignment = .firstBaseline

        serviceRow = addRow(to: grid, title: "네트워크 서비스", control: servicePopUp, field: nil)
        // 아래 값들이 **언제** 적용되는지를 먼저 정한다. 순서에 뜻이 있다 — 조건이 위, 그 조건에서 쓸 값이 아래.
        addRow(to: grid, title: "사내 Wi-Fi 이름", control: makeSSIDRow(), field: .ssids)
        addRow(to: grid, title: "IP 주소", control: ipField, field: .ip)
        addRow(to: grid, title: "서브넷 마스크", control: subnetField, field: .subnet)
        addRow(to: grid, title: "라우터", control: routerField, field: .router)
        addRow(to: grid, title: "DNS 서버", control: dnsField, field: .dns)

        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = Self.labelColumnWidth
        grid.column(at: 1).xPlacement = .fill

        // 한 글자 적을 때마다 [저장] 을 누를 수 있는지 다시 본다 — 다 채우고도 못 누르거나
        // 지우고도 눌리는 순간이 있으면 버튼을 믿을 수 없게 된다.
        for field in [ssidField, ipField, subnetField, routerField, dnsField] {
            field.delegate = self
        }
        // 서비스도 저장되는 값이다. 이 줄만 고치고 저장하는 자리가 실제로 있다
        // (Wi-Fi 서비스를 못 찾은 기기).
        servicePopUp.target = self
        servicePopUp.action = #selector(fieldChanged)

        let separator = Self.makeSeparator()
        let permissionSeparator = Self.makeSeparator()
        let permissionTitle = NSTextField(labelWithString: "권한")
        permissionTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        // 여기에는 [제거…] 가 있었다. 지금은 창 아래쪽 왼편의 [앱 삭제…] 하나로 합쳤다 —
        // 두 손잡이가 나란히 있으면 무엇이 다른지 알 수 없다.
        let permissionHeader = NSStackView(views: [permissionTitle, NSView()])
        permissionHeader.orientation = .horizontal
        permissionHeader.alignment = .firstBaseline
        permissionHeader.distribution = .fill
        permissionHeader.spacing = Self.columnSpacing

        buildPermissionGrid()

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem(_:))

        // 이 체크상자는 `SMAppService.mainApp` 으로 앱 자신을 로그인 항목에 올린다.
        // ad-hoc 서명으로도 등록된다 — 근거는 `LoginItem.swift` 머리말에 적어 두었다.
        //
        // **켜고 끄는 최종 권한은 macOS 에 있다** — 시스템 설정의 로그인 항목에서 꺼 버리면
        // 로그인해도 뜨지 않는다. 그 상태는 앱이 읽을 수 있으므로(`.blockedBySystem`)
        // 체크상자 아래에 "macOS 가 이 항목을 꺼 두었습니다" 를 적고, 그 화면으로 나갈 자리를 옆에 둔다.
        loginItemSettingsButton.bezelStyle = .rounded
        loginItemSettingsButton.controlSize = .small
        loginItemSettingsButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginItemSettingsButton.target = self
        loginItemSettingsButton.action = #selector(openLoginItemsSettings)
        // 그 화면도 목록이다 — 무엇을 찾아야 하는지 여기서 미리 말해 둔다.
        loginItemSettingsButton.toolTip = SystemSettingsPane.loginItems.openGuidance

        let loginItemRow = NSStackView(views: [loginItemCheckbox, loginItemSettingsButton, NSView()])
        loginItemRow.orientation = .horizontal
        loginItemRow.alignment = .centerY
        loginItemRow.distribution = .fill
        loginItemRow.spacing = Self.columnSpacing

        let cancelButton = NSButton(title: "취소", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .firstBaseline

        // 파괴적 동작이라는 것은 보이되 **기본 버튼([저장])보다 앞서면 안 된다.**
        // 빨간 배경(`bezelColor`)을 주면 채워진 버튼이 되어 이 창에서 가장 먼저 눈에 들어온다 —
        // 평소에 누를 것은 [저장] 이고 이 버튼은 한 번 누르고 끝나는 것이라 순서가 뒤집힌다.
        // 그래서 테두리는 다른 버튼과 같은 것을 쓰고 **글자만 빨갛게** 한다 (macOS 관례).
        // 위계는 자리가 만든다: 저장·취소와 반대쪽 끝에 홀로 선다.
        removeAppButton.bezelStyle = .rounded
        removeAppButton.hasDestructiveAction = true
        removeAppButton.target = self
        removeAppButton.action = #selector(performAppRemoval)
        removeAppButton.toolTip = "설치한 항목을 지우고 앱을 휴지통으로 옮깁니다."
        removeAppButton.isHidden = true
        applyRemoveAppButtonTitle(enabled: true)

        // 두 무리를 양 끝으로 벌린다. 늘어나는 것은 사이의 빈 자리 하나뿐이다.
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let buttonRow = NSStackView(views: [removeAppButton, footerSpacer, buttons])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [
            introLabel, grid,
            separator, permissionHeader, permissionGrid,
            permissionSeparator, loginItemRow, loginItemStatusLabel, noticeLabel, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(10, after: separator)
        stack.setCustomSpacing(10, after: permissionHeader)
        stack.setCustomSpacing(10, after: permissionSeparator)
        // 체크상자와 그 결과 줄은 한 덩이로 읽혀야 한다 — 사이를 좁히고, 다음 것과는 원래 간격을 둔다.
        stack.setCustomSpacing(4, after: loginItemRow)
        stack.setCustomSpacing(6, after: loginItemStatusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalToConstant: Self.windowWidth),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            introLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noticeLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // 글자가 없을 때도 폭을 붙들어 둔다 — 나타났다 사라질 때 옆 것이 밀리지 않게.
            loginItemStatusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    /// 권한 항목 넷을 한 번만 만든다.
    ///
    /// 갱신할 때 행을 다시 만들지 않는 이유는 **열이 흔들리지 않게** 하기 위해서다.
    /// 제목 열은 위쪽 입력 폼과 같은 너비를 쓰고(같은 세로선에 걸린다), 상태와 버튼은 한 줄에,
    /// 설명은 그 아래 줄에 둔다. 상태 글자가 길어지거나 버튼이 사라져도 열은 그대로다.
    private func buildPermissionGrid() {
        permissionGrid.translatesAutoresizingMaskIntoConstraints = false
        permissionGrid.columnSpacing = Self.columnSpacing
        permissionGrid.rowSpacing = 4
        permissionGrid.rowAlignment = .firstBaseline

        for (index, subject) in PermissionSubject.allCases.enumerated() {
            let row = PermissionRowViews(subject: subject)

            row.button.target = self
            row.button.action = #selector(performPermissionAction(_:))
            row.button.isHidden = true

            let header = NSStackView(views: [row.status, NSView(), row.button])
            header.orientation = .horizontal
            header.alignment = .firstBaseline
            header.distribution = .fill
            header.spacing = Self.columnSpacing

            let titleRow = permissionGrid.addRow(with: [row.title, header])
            // 항목 사이만 벌린다. 상태와 설명은 붙어 있어야 한 항목으로 읽힌다.
            if index > 0 { titleRow.topPadding = 10 }
            let noteRow = permissionGrid.addRow(with: [NSGridCell.emptyContentView, row.note])
            // 판정이 오기 전에는 숨겨 둔다 — 잠깐 나타났다 사라지면 창 높이가 한 번 출렁인다.
            noteRow.isHidden = true
            permissionNoteRows[subject] = noteRow

            permissionRows[subject] = row
        }

        permissionGrid.column(at: 0).xPlacement = .trailing
        permissionGrid.column(at: 0).width = Self.labelColumnWidth
        permissionGrid.column(at: 1).xPlacement = .fill
    }


    /// Wi-Fi 이름 칸과 그 옆의 권한 버튼 한 줄.
    ///
    /// **등록하는 사내 Wi-Fi 는 하나다.** 게스트망은 개방망이라 고정 IP 를 쓸 이유가 없어,
    /// 이름을 여럿 등록할 자리를 화면에 두지 않는다 (설정 파일의 `ssids` 는 배열 그대로다 —
    /// 나중에 다시 필요해질 때 파일 형식을 깨지 않으려고 구조는 남겨 둔다).
    ///
    /// 버튼을 이 칸 옆에 두는 이유: **이 칸을 채우는 것이 그 권한이 하는 일이다.**
    /// 아래 권한 섹션에도 같은 조치가 있지만, 빈 칸을 보고 있는 사람에게 필요한 것은
    /// "왜 비었는지" 를 설명하는 문장이 아니라 바로 여기서 누를 수 있는 손잡이다.
    private func makeSSIDRow() -> NSView {
        ssidPermissionButton.bezelStyle = .rounded
        ssidPermissionButton.controlSize = .small
        ssidPermissionButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        ssidPermissionButton.target = self
        ssidPermissionButton.action = #selector(performSSIDPermissionAction)
        // 권한 판정이 오기 전에는 숨어 있는다 — 잠깐 나타났다 사라지면 그것이 더 눈에 띈다.
        ssidPermissionButton.isHidden = true
        ssidPermissionButton.setContentHuggingPriority(.required, for: .horizontal)
        ssidPermissionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [ssidField, ssidPermissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        // 남는 폭은 입력 칸이 가져간다. 버튼이 없을 때 칸이 줄어들 이유가 없다.
        ssidField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 잠길 때 테두리 자리를 여백으로 채우려면 이 줄을 들고 있어야 한다 (`applySSIDLock`).
        ssidRow = row
        lockedFieldInsets = Self.insets(replacingBezelOf: ssidField)
        return row
    }

    /// 라벨 + 입력 칸 한 줄, 그리고 그 아래 숨겨진 오류 줄 하나.
    @discardableResult
    private func addRow(to grid: NSGridView, title: String, control: NSView, field: DraftField?) -> NSGridRow {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        let titleRow = grid.addRow(with: [label, control])

        guard let field else { return titleRow }
        let errorLabel = SettingsWindowController.makeWrappingLabel(
            font: .systemFont(ofSize: NSFont.smallSystemFontSize),
            color: .systemRed
        )
        // 줄바꿈 폭을 미리 정해 둔다 — 정하지 않으면 한 줄짜리 폭을 요구해 열 너비를 밀어낸다.
        errorLabel.preferredMaxLayoutWidth = Self.fieldColumnWidth
        let row = grid.addRow(with: [NSGridCell.emptyContentView, errorLabel])
        row.topPadding = -4
        row.isHidden = true
        errorLabels[field] = errorLabel
        errorRows[field] = row
        return titleRow
    }

    /// 테두리가 글자 둘레에 두고 있는 여백을 잰다. **테두리가 있는 지금** 재야 한다.
    ///
    /// 세 방향을 다 재는 이유가 있다. 가로만 맞추면 값의 왼쪽 끝은 맞는데 줄이 6pt 낮아져
    /// 아래 칸들과의 간격이 어긋나고, 위만 맞추면 글자는 제자리인데 줄 높이가 모자란다.
    /// 위쪽은 **글자가 앉는 높이(베이스라인)** 로, 아래쪽은 남은 높이로 정한다.
    private static func insets(replacingBezelOf field: NSTextField) -> NSEdgeInsets {
        let probe = NSRect(x: 0, y: 0, width: 200, height: field.intrinsicContentSize.height)
        let left = field.cell?.drawingRect(forBounds: probe).minX ?? 0
        let bezeledHeight = field.intrinsicContentSize.height
        let bezeledBaseline = field.firstBaselineOffsetFromTop

        // 지운 뒤의 값을 재고 곧바로 되돌린다 (이 시점의 칸은 편집 가능한 모습이어야 한다).
        field.isBezeled = false
        let plainHeight = field.intrinsicContentSize.height
        let plainBaseline = field.firstBaselineOffsetFromTop
        field.isBezeled = true
        field.bezelStyle = .roundedBezel

        let top = bezeledBaseline - plainBaseline
        return NSEdgeInsets(top: top, left: left, bottom: bezeledHeight - plainHeight - top, right: 0)
    }

    private static func makeField(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        return field
    }

    private static func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private static func makeWrappingLabel(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = font
        label.textColor = color
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

/// 권한 한 줄이 쓰는 뷰 묶음.
///
/// 상태·설명·버튼을 한 자리에 묶어 두면 갱신할 때 **같은 뷰를 계속 쓴다.**
/// 매번 새로 만들면 글자 길이에 따라 열 너비가 흔들린다.
@MainActor
private struct PermissionRowViews {

    let title: NSTextField
    let status: NSTextField
    let note: NSTextField
    let button: NSButton

    init(subject: PermissionSubject) {
        title = NSTextField(labelWithString: subject.title)
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        title.textColor = .labelColor

        status = NSTextField(labelWithString: "확인 중…")
        status.font = .systemFont(ofSize: NSFont.systemFontSize)
        status.lineBreakMode = .byTruncatingTail

        note = NSTextField(wrappingLabelWithString: subject.purpose)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.isSelectable = true
        // 줄바꿈 폭을 미리 정해 둔다 — 정하지 않으면 한 줄짜리 폭을 요구해 열 너비를 밀어낸다.
        note.preferredMaxLayoutWidth = SettingsWindowController.noteWidth
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    }
}
