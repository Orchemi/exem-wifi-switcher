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
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

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
    /// Wi-Fi 이름 칸이 지금 편집 가능한가.
    ///
    /// **사내(고정 IP 구성)에서 이름이 채워져 있으면 잠근다.** 그 이름은 앱이 지금 접속한
    /// Wi-Fi 에서 그대로 읽어 넣은 값이라 사람이 손댈 이유가 없고, 실수로 고치면 값이 다
    /// 맞아도 자동 전환만 조용히 걸리지 않는다.
    ///
    /// **사외(DHCP)에서는 잠그지 않는다.** 사외에서 처음 설정하는 사람은 사내 Wi-Fi 이름을
    /// 손으로 넣어야 하고, 잘못 넣은 이름을 고칠 자리도 거기뿐이다 — 이 창에 여는 버튼이 없으므로
    /// 여기까지 잠그면 되돌릴 길이 사라진다.
    ///
    /// 사내인데 칸이 빈 경우(위치 권한이 없어 이름을 못 읽음)도 잠그지 않는다. 잠가 두면
    /// 권한을 끝내 거부한 사람에게 남는 길이 없다.
    private var isSSIDEditable = true
    /// Wi-Fi 서비스를 못 찾았을 때만 남는 안내. 저장 실패 문구와 같은 줄을 쓰므로
    /// 상태로 들고 있다가 그 문구를 지울 때 되돌린다.
    private var serviceNotice: String?

    private let loginItemCheckbox = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)
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
    /// 설치된 것을 되돌리는 손잡이. 항목별 조치가 아니라 섹션 전체에 걸리므로 머리말 옆에 둔다.
    private let uninstallButton = NSButton(title: "제거…", target: nil, action: nil)
    /// 설치·제거가 도는 동안 같은 일을 두 번 걸지 않는다.
    private var isRunningInstaller = false

    private var observation = Observation.pending
    private var hasBeenShown = false

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
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        observeApplicationActivation()
    }

    /// 시스템 설정에 다녀와 앱으로 돌아오면 권한을 다시 확인한다.
    ///
    /// 이것이 없으면 사용자가 권한을 허용하고 돌아와도 창은 "거부됨" 을 계속 보여준다 —
    /// 고친 사람에게 안 고쳐졌다고 말하는 셈이다.
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
        let existingOffice = observation.readyConfig?.profiles.first { $0.mode == .manual }
        let suggestion = observation.interface.flatMap {
            ManualProfileDraft.from($0, dns: observation.dnsServers, ssid: observation.ssid)
        }

        if let existingOffice, let ip = existingOffice.ip, let subnet = existingOffice.subnet, let router = existingOffice.router {
            // 저장해 둔 값이 언제나 이긴다 — 사용자가 고쳐 둔 Wi-Fi 이름을 지금 붙어 있는 이름으로 덮지 않는다.
            fill(ManualProfileDraft(
                ip: ip, subnet: subnet, router: router,
                dns: existingOffice.dns.joined(separator: ", "),
                ssids: existingOffice.ssids.joined(separator: ", ")
            ))
            introLabel.stringValue = "사내에서 쓰는 고정 IP 값 · 저장하면 다음 전환부터 적용"
        } else if let suggestion {
            fill(suggestion)
            // 지금 이 자리가 곧 사내다 — Wi-Fi 이름까지 채워졌으면 [저장] 한 번으로 자동 전환까지 선다.
            introLabel.stringValue = suggestion.ssids.isEmpty
                ? "지금 고정 IP 로 연결됨 · 아래 값을 사내 프로필로 저장"
                : "지금 고정 IP 로 연결됨 · 붙어 있는 Wi-Fi 와 그 값을 사내 프로필로 저장"
        } else {
            fill(ManualProfileDraft())
            // 지금은 DHCP 다. 사내 값도, 사내 Wi-Fi 이름도 여기서는 알 수 없다 —
            // 지금 붙어 있는 Wi-Fi(집·카페일 수 있다)를 사내 것으로 적어 두면 그 자리에서 고정 IP 가 걸린다.
            introLabel.stringValue = "지금은 고정 IP 구성이 아님 · 사내 Wi-Fi 이름과 IP·서브넷·라우터 입력"
        }

        if case .unusable(_, let reason) = observation.config {
            introLabel.stringValue = "설정 파일을 읽지 못함 — \(reason)"
        }

        loginItemCheckbox.state = LoginItem.isRegistered() ? .on : .off

        // 설치 안내와 '저장할 때 인증을 받는다' 는 이제 아래 권한 섹션이 말한다.
        // 같은 말을 두 자리에서 하면 어느 쪽이 최신인지 알 수 없게 된다.
        isSSIDEditable = !(observation.interface?.isManual == true) || ssidField.stringValue.isEmpty
        applySSIDLock()

        serviceNotice = serviceFound ? nil : "Wi-Fi 서비스 없음 · 위에서 사용할 서비스 선택"

        clearIssues()
        showDNSReadFailureIfNeeded()
    }

    /// 잠금 상태를 칸·버튼·안내 줄에 한 번에 반영한다.
    ///
    /// **잠겼다는 것이 보여야 한다.** 눌러도 아무 일 없는 칸처럼 보이면 고장으로 읽힌다 —
    /// 비활성 색으로 칠하고, 여는 손잡이를 옆에 둔다.
    private func applySSIDLock() {
        ssidField.isEditable = isSSIDEditable
        ssidField.isSelectable = true
        ssidField.textColor = isSSIDEditable ? .labelColor : .secondaryLabelColor
        showSSIDLockHint()
    }

    /// 왜 잠겼는지 한 줄. 오류 줄과 자리를 나눠 쓴다 — 둘이 함께 필요한 순간이 없다.
    private func showSSIDLockHint() {
        guard let label = errorLabels[.ssids], let row = errorRows[.ssids] else { return }
        guard !isSSIDEditable else {
            row.isHidden = true
            return
        }
        label.textColor = .secondaryLabelColor
        // 왜 채워졌는지와 왜 못 고치는지를 한 구로. '사내에서는' 이 곧 되돌릴 자리(사외)를 가리킨다.
        label.stringValue = "자동 입력 · 사내에서는 잠김"
        row.isHidden = false
    }

    /// 창이 열려 있는 동안 새 관측이 왔을 때 화면을 맞춘다.
    ///
    /// **위치 권한을 방금 허용한 순간이 이 경로의 이유다.** 그때 Wi-Fi 이름이 처음으로 읽히는데,
    /// 창을 다시 열기 전에는 칸이 빈 채로 남아 있었다 — 권한을 받아 놓고도 손으로 넣게 되는 셈이다.
    ///
    /// **사용자가 적어 둔 것은 건드리지 않는다.** 비어 있는 칸만 채운다.
    func update(observation: Observation) {
        self.observation = observation
        if ssidField.stringValue.isEmpty, let ssid = observation.ssid.name {
            ssidField.stringValue = ssid
        }
        refreshPermissions()
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
        uninstallButton.isHidden = !report.canUninstall
        uninstallButton.isEnabled = !isRunningInstaller
        window?.setContentSize(window?.contentView?.fittingSize ?? NSSize(width: Self.windowWidth, height: 320))
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

    @objc private func performUninstall() {
        beginInstaller(.uninstall)
    }

    @objc private func openLoginItemsSettings() {
        open(.loginItems)
    }

    /// 시스템 설정의 해당 화면을 연다.
    ///
    /// 알림은 우리 앱의 줄을 편 채로 열린다 (`url(revealing:)`). 나머지는 목록이 열리므로,
    /// 무엇을 찾아야 하는지는 각 항목의 안내 문구(`openGuidance`)가 미리 말해 둔다.
    private func open(_ pane: SystemSettingsPane) {
        guard let url = URL(string: pane.url(revealing: Bundle.main.bundleIdentifier)) else { return }
        NSWorkspace.shared.open(url)
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
            : "설치한 항목을 제거합니다"
        alert.informativeText = operation == .install
            ? "관리자 인증을 한 번 받습니다. 아래가 설치할 내용 전부입니다."
            : "관리자 인증을 한 번 받습니다. 아래 항목을 지웁니다 — 입력한 네트워크 값도 함께 지워집니다."
        alert.accessoryView = InstallPlanView.make(preview.plan)

        let confirmButton = alert.addButton(withTitle: operation.title)
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

        switch result {
        case .success:
            presentInstallerSuccess(operation)
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

    private func presentInstallerSuccess(_ operation: BundledInstaller.Operation) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch operation {
        case .install:
            alert.messageText = "설치했습니다"
            alert.informativeText = "이제 프로필을 전환할 때 암호를 묻지 않습니다. "
                + "설정 값을 저장할 때는 관리자 인증을 한 번 받습니다."
        case .uninstall:
            alert.messageText = "제거했습니다"
            alert.informativeText = "전환·저장 권한과 설정을 지웠습니다. 앱은 계속 실행 중입니다 — "
                + "앱 자체를 지우려면 \(InstallPaths.appName).app 을 직접 지우세요."
        }
        alert.addButton(withTitle: "확인")
        show(alert)
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
        uninstallButton.isEnabled = enabled
        for row in permissionRows.values { row.button.isEnabled = enabled }
    }

    private func show(_ alert: NSAlert, then handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in handler?(response) }
    }

    // MARK: - 저장

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

        onSaved()
        close()
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
        close()
    }

    // MARK: - 로그인 항목

    @objc private func toggleLoginItem(_ sender: NSButton) {
        let shouldRegister = sender.state == .on
        do {
            if shouldRegister {
                try LoginItem.register(appBundlePath: Bundle.main.bundlePath)
            } else {
                try LoginItem.unregister()
            }
        } catch {
            sender.state = shouldRegister ? .off : .on
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = shouldRegister ? "로그인 항목으로 등록하지 못했습니다" : "로그인 항목을 해제하지 못했습니다"
            alert.informativeText = "\(error)"
            alert.addButton(withTitle: "확인")
            alert.beginSheetModal(for: window!, completionHandler: nil)
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
        // 두 안내 줄 모두 오류와 자리를 나눠 쓴다 — 오류를 지웠으면 그 자리로 돌아온다.
        noticeLabel.stringValue = serviceNotice ?? ""
        noticeLabel.isHidden = serviceNotice == nil
        showSSIDLockHint()
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

        let separator = Self.makeSeparator()
        let permissionSeparator = Self.makeSeparator()
        let permissionTitle = NSTextField(labelWithString: "권한")
        permissionTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        // 제거는 항목 하나의 조치가 아니라 설치한 것 전체를 되돌리는 일이라 머리말 옆에 둔다.
        uninstallButton.bezelStyle = .rounded
        uninstallButton.controlSize = .small
        uninstallButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        uninstallButton.target = self
        uninstallButton.action = #selector(performUninstall)
        uninstallButton.isHidden = true

        let permissionHeader = NSStackView(views: [permissionTitle, NSView(), uninstallButton])
        permissionHeader.orientation = .horizontal
        permissionHeader.alignment = .firstBaseline
        permissionHeader.distribution = .fill
        permissionHeader.spacing = Self.columnSpacing

        buildPermissionGrid()

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem(_:))

        // 이 체크상자는 `~/Library/LaunchAgents` 에 항목을 놓을 뿐이고, **켜고 끄는 최종 권한은
        // macOS 에 있다** — 시스템 설정의 로그인 항목에서 꺼 버리면 로그인해도 뜨지 않는다.
        // 앱은 그 상태를 읽을 수 없으므로(서명 인증서가 없어 `SMAppService` 를 못 쓴다)
        // 체크상자는 계속 '켜짐' 으로 보인다. 확인하러 갈 자리를 옆에 둔다.
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

        let saveButton = NSButton(title: "저장", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .firstBaseline

        let buttonRow = NSStackView(views: [NSView(), buttons])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [
            introLabel, grid,
            separator, permissionHeader, permissionGrid,
            permissionSeparator, loginItemRow, noticeLabel, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(10, after: separator)
        stack.setCustomSpacing(10, after: permissionHeader)
        stack.setCustomSpacing(10, after: permissionSeparator)
        stack.setCustomSpacing(6, after: loginItemRow)
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
