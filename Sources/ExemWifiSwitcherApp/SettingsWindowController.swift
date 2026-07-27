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
    private let dnsField = SettingsWindowController.makeField(placeholder: "필수 · 사내 DNS 서버를 쉼표로 구분 (예: 192.0.2.53, 192.0.2.54)")

    private var errorLabels: [DraftField: NSTextField] = [:]
    private var errorRows: [DraftField: NSGridRow] = [:]

    private let loginItemCheckbox = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)
    private let noticeLabel = SettingsWindowController.makeWrappingLabel(
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )

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

    init(onSaved: @escaping () -> Void) {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("스토리보드를 쓰지 않는다")
    }

    // MARK: - 표시

    func present(observation: Observation) {
        self.observation = observation
        populate()
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
        if services.contains(currentService) { servicePopUp.selectItem(withTitle: currentService) }

        // 값 — 이미 저장된 프로필이 있으면 그 값을, 없으면 현재 구성에서 제안한다.
        let existingOffice = observation.readyConfig?.profiles.first { $0.mode == .manual }
        let suggestion = observation.interface.flatMap { ManualProfileDraft.from($0, dns: observation.dnsServers) }

        if let existingOffice, let ip = existingOffice.ip, let subnet = existingOffice.subnet, let router = existingOffice.router {
            fill(ManualProfileDraft(ip: ip, subnet: subnet, router: router, dns: existingOffice.dns.joined(separator: ", ")))
            introLabel.stringValue = "사내에서 쓰는 고정 IP 값입니다. 바꾼 뒤 저장하면 다음 전환부터 적용됩니다."
        } else if let suggestion {
            fill(suggestion)
            introLabel.stringValue = "지금 이 Mac 은 고정 IP 로 연결돼 있습니다. 아래 값을 사내 프로필로 저장할 수 있습니다."
        } else {
            fill(ManualProfileDraft())
            introLabel.stringValue = "지금은 고정 IP 구성이 아닙니다. 사내에서 쓰는 IP·서브넷·라우터를 입력하세요."
        }

        if case .unusable(_, let reason) = observation.config {
            introLabel.stringValue = "설정 파일을 읽지 못했습니다 — \(reason)\n아래 값으로 새로 저장할 수 있습니다."
        }

        loginItemCheckbox.state = LoginItem.isRegistered() ? .on : .off

        // 줄바꿈을 직접 넣는다 — 자동 줄바꿈에 맡기면 명령이 슬래시에서 잘려 읽기 어려워진다.
        if !observation.helperInstalled {
            // 설치 안내는 아직 설치되지 않았을 때만 보여준다. 평소에는 없는 편이 낫다.
            noticeLabel.isHidden = false
            noticeLabel.stringValue = "전환 권한이 아직 설치돼 있지 않습니다. 앱은 관리자 권한을 대신 얻지 않습니다.\n"
                + "레포 디렉터리에서 ./scripts/install.sh 를 먼저 실행하세요."
        } else {
            // 저장이 관리자 인증을 요구한다는 사실을 미리 알린다. 창이 뜨고 나서 놀라지 않도록.
            noticeLabel.isHidden = false
            noticeLabel.stringValue = "설정 파일은 root 소유(0644)라 사용자 권한으로는 바꿀 수 없습니다.\n"
                + "저장할 때 관리자 인증을 한 번 받습니다. 전환할 때는 묻지 않습니다."
        }

        clearIssues()
        showDNSReadFailureIfNeeded()
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
        label.stringValue = "현재 DNS 설정을 읽지 못했습니다 (\(reason)). 사내 DNS 서버를 직접 입력하세요."
        errorRows[.dns]?.isHidden = false
    }

    private func fill(_ draft: ManualProfileDraft) {
        ipField.stringValue = draft.ip
        subnetField.stringValue = draft.subnet
        routerField.stringValue = draft.router
        dnsField.stringValue = draft.dns
    }

    private var draft: ManualProfileDraft {
        ManualProfileDraft(
            ip: ipField.stringValue,
            subnet: subnetField.stringValue,
            router: routerField.stringValue,
            dns: dnsField.stringValue
        )
    }

    // MARK: - 저장

    @objc private func save() {
        clearIssues()

        let existing = observation.readyConfig
        let ssids = existing?.profile(named: OnboardingSetup.officeProfileName)?.ssids ?? []
        let result = draft.makeProfile(
            name: OnboardingSetup.officeProfileName,
            label: OnboardingSetup.officeProfileLabel,
            ssids: ssids
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
    }

    private func fieldControl(for field: DraftField) -> NSTextField? {
        switch field {
        case .ip: return ipField
        case .subnet: return subnetField
        case .router: return routerField
        case .dns: return dnsField
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

        addRow(to: grid, title: "네트워크 서비스", control: servicePopUp, field: nil)
        addRow(to: grid, title: "IP 주소", control: ipField, field: .ip)
        addRow(to: grid, title: "서브넷 마스크", control: subnetField, field: .subnet)
        addRow(to: grid, title: "라우터", control: routerField, field: .router)
        addRow(to: grid, title: "DNS 서버", control: dnsField, field: .dns)

        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = Self.labelColumnWidth
        grid.column(at: 1).xPlacement = .fill

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem(_:))

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

        let stack = NSStackView(views: [introLabel, grid, separator, loginItemCheckbox, noticeLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(10, after: separator)
        stack.setCustomSpacing(6, after: loginItemCheckbox)
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
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            introLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noticeLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    /// 라벨 + 입력 칸 한 줄, 그리고 그 아래 숨겨진 오류 줄 하나.
    private func addRow(to grid: NSGridView, title: String, control: NSView, field: DraftField?) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        grid.addRow(with: [label, control])

        guard let field else { return }
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

    private static func makeWrappingLabel(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = font
        label.textColor = color
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
