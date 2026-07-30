import AppKit
import WifiSwitcherCore

/// 메뉴바 항목 하나와 그 메뉴.
///
/// 이 타입이 하는 일은 넷뿐이다.
///   1. 시스템을 읽어(`SystemProbe`) 상태를 새로 고친다
///   2. 상태를 메뉴·아이콘으로 그린다 (무엇을 그릴지는 `StatusModel` 이 이미 정해 놓았다)
///   3. 네트워크가 바뀌면(`NetworkChangeMonitor`) 자동 전환을 판정한다
///      (**전환할지 말지는 `AutoSwitchPolicy` 가 정한다** — 여기에는 판단이 없다)
///   4. 사용자가 고른 프로필로 전환한다
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    /// **`init()` 안에서 만든다.** 상태 항목은 태어나는 순간 저장된 자리를 읽으므로,
    /// 자리를 심는 일이 그보다 먼저 끝나야 한다 (아래 `init()` 참조).
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let probe = SystemProbe()
    private let notifier = SwitchNotifier()
    private let locationAuthority = LocationAuthority()
    private let preferenceStore = UserDefaults.standard

    private var observation = Observation.pending
    private var action: ActionState = .idle
    private var settingsWindow: SettingsWindowController?
    private var refreshTimer: Timer?
    private var monitor: NetworkChangeMonitor?
    private var visibilityWatch: MenuBarVisibilityWatch?
    /// 같은 상태를 다시 그리지 않는다 — 메뉴가 열린 채 갱신될 때 항목이 깜박이지 않게 한다.
    private var renderedModel: StatusModel?

    // MARK: - 자동 전환

    private var autoSwitchEnabled: Bool
    /// 마지막 판정이 전환하지 않기로 한 이유. 메뉴에 그대로 적는다.
    private var autoSwitchHold: AutoSwitchHold?
    /// 지금 Wi-Fi 에서 자동 전환이 무엇을 시도했는지. 무한 루프를 막는 기록이다.
    private var autoSwitchState = AutoSwitchState()
    /// 위치 권한 거부는 실행 중 한 번만 알린다 (반복 알림은 그 자체로 소음이다).
    private var announcedPermissionDenied = false

    /// 전환 중에 사용자가 메뉴에서 고른 프로필. 지금 전환이 끝나면 이어서 적용한다.
    /// (버리면 클릭이 아무 반응 없이 사라진다 — 누른 사람에게는 고장으로 보인다)
    private var queuedUserChoice: String?

    // MARK: - 갱신 직렬화
    //
    // 갱신을 부르는 문이 넷이다 — 주기 확인 · SCDynamicStore 감시 · 메뉴 열기 · 위치 권한 변경.
    // `probe.read` 는 서브프로세스를 서너 개 띄워 수백 ms 가 걸리므로, 겹쳐 돌면 **늦게 시작한 쪽이
    // 먼저 끝나 낡은 관측이 새 값을 덮어쓴다.** 그 값으로 자동 전환을 판정하면 사외에서 사내 고정 IP를
    // 물거나 그 반대가 된다.
    //
    // 그래서 한 번에 하나만 돌린다. 겹쳐 들어온 요청은 새로 프로세스를 띄우지 않고 **하나로 묶어**
    // 진행 중인 갱신이 끝난 뒤 한 번만 이어 돈다 (`EventCoalescer` 와 같은 사고방식이다).
    private var isRefreshing = false
    private var refreshQueued = false

    /// 지금 관측값으로 계산한 상태. 계산이 싸므로 저장하지 않고 그때그때 만든다.
    private var model: StatusModel {
        StatusModel.resolve(observation.statusInput(
            action: action,
            autoSwitchEnabled: autoSwitchEnabled,
            autoSwitchHold: autoSwitchHold,
            notifications: notifier.permission
        ))
    }

    private var isSwitching: Bool {
        if case .switching = action { return true }
        return false
    }

    /// 사용자가 ⌘-드래그로 옮겨 둔 아이콘 자리를 기억하는 이름.
    ///
    /// **한 번 정하면 바꾸지 마라.** macOS 는 이 이름으로 `UserDefaults` 에
    /// `NSStatusItem Preferred Position <이름>` 을 적어 둔다 — 이름을 바꾸면 사용자가 옮겨 둔 자리를
    /// 통째로 잃고 아이콘이 다시 왼쪽 끝(노치 자리)으로 돌아간다.
    ///
    /// `--diagnose` 도 이 이름으로 자리를 찾는다 (`Diagnostics.menuBarSeat`) — 두 벌로 적어 두면
    /// 한쪽만 바뀐 채 진단이 엉뚱한 열쇠를 읽는다.
    static let statusItemAutosaveName = "status-item"

    override init() {
        autoSwitchEnabled = AutoSwitchPreferences.isEnabled(in: UserDefaults.standard)
        // 자리를 먼저 심고 항목을 만든다 — 순서를 뒤집으면 항목은 이미 놓인 뒤라 값을 읽지 않는다.
        //
        // 심는 것은 **저장된 자리가 없고 화면에 노치가 있을 때뿐이다** (`StatusItemSeat.seedPosition`).
        // 사용자가 옮겨 둔 자리는 손대지 않는다.
        MenuBarSeat.seedIfNeeded(autosaveName: Self.statusItemAutosaveName, store: UserDefaults.standard)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        // 아이콘 자리를 기억시킨다.
        //
        // 이것이 없으면 아이콘은 **뜰 때마다 남은 자리 중 왼쪽 끝**에 놓인다. 노치가 있는 Mac 에서
        // 그 자리는 노치에 물리는 자리다 (실측: 노치가 663 에서 시작하는데 왼쪽 끝 자리는 676 에서
        // 끝난다 — `StatusItemPlacement` 의 표). 옮겨 봐야 다음 로그인에 제자리로 돌아오니
        // 사용자가 고칠 방법 자체가 없었다.
        //
        // 이 이름을 붙이면 ⌘ 를 누른 채 아이콘을 오른쪽(시계 쪽)으로 한 번 끌어 두는 것으로 끝난다.
        // 메뉴 막대 오른쪽은 노치에 닿지 않는다.
        //
        // **다만 이 이름은 사용자가 한 번 옮긴 뒤에야 듣는다.** 옮기기 전까지는 매번 노치 자리라서,
        // 위에서 첫 자리를 미리 심어 둔다 (`MenuBarSeat.seedIfNeeded`).
        //
        // **`isVisible = false` 로 항목을 숨겼다 켜면 이 기억이 지워진다.** 실측으로 갈라 본 자리다 —
        // 자리를 심어 두고 띄웠을 때, 켠 채로 시작하면 그 자리에 놓였고(x=1097 · 저장값 남음),
        // 숨겼다 1초 뒤에 켜면 저장값이 사라지고 왼쪽 끝(x=613 · 노치 자리)으로 돌아갔다.
        // 그래서 '첫 관측 전에는 숨겨 둔다' 를 걷어냈다. 그 대신 치르는 값은 관측이 오기 전 몇백 ms 동안
        // **폭 16pt 짜리 빈자리**가 보이는 것뿐이고(실측), 원래 피하려던 것 — 틀린 아이콘을 잠깐 보여
        // 주는 일 — 은 그대로 일어나지 않는다. 자리는 이미 잡혀 있으니 아이콘이 채워질 때 튀지도 않는다.
        statusItem.autosaveName = Self.statusItemAutosaveName
    }

    // MARK: - 수명

    func start() {
        // 알림 권한 답이 오면 메뉴를 다시 그린다 — 거부됐다는 사실도 메뉴에 적히는 정보다.
        notifier.onPermissionChange = { [weak self] in self?.render() }
        notifier.prepare()

        locationAuthority.onChange = { [weak self] in
            Task { @MainActor in
                // 권한 상태는 앱을 띄운 **직후에도 한 번 늦게** 온다 (`LocationAuthority` 참조).
                // 설정 창이 이미 열려 있으면 그 창의 권한 섹션도 함께 고쳐 그려야
                // "권한 없음" 과 "Wi-Fi 이름 읽음" 이 한 화면에 남지 않는다.
                self?.settingsWindow?.refreshPermissions()
                await self?.refreshAndEvaluate()
            }
        }
        if autoSwitchEnabled { locationAuthority.requestIfNeeded() }

        Task {
            await refreshAndEvaluate()
            // 첫 실행(설정이 없거나 예시 그대로)이면 바로 설정 창을 연다.
            //
            // **묻는 것이 먼저다.** 위치 권한이 있어야 지금 붙어 있는 Wi-Fi 이름이 읽히고,
            // 그래야 온보딩의 '사내 Wi-Fi 이름' 칸이 채워진 채로 열린다. 순서를 뒤집으면
            // 사용자는 빈 칸부터 마주하고, 그 칸을 손으로 채우게 된다 — 이 도구가 없애려던 수고다.
            if model.needsSetup {
                locationAuthority.requestIfNeeded()
                openSettings()
            }
        }

        // 심어 둔 자리로도 아이콘이 가려질 수 있다 (앞선 항목이 많으면 심은 자리가 이미 차 있다).
        // 그때는 한 번 더 오른쪽으로 밀어 보고, 그래도 안 되면 옮기라고 말한다.
        let watch = MenuBarVisibilityWatch(
            statusItem: statusItem,
            autosaveName: Self.statusItemAutosaveName,
            store: preferenceStore,
            announce: { [weak self] message in self?.notifier.post(message) }
        )
        visibilityWatch = watch
        watch.start()

        // 옛 방식(~/Library/LaunchAgents)으로 켜 두었던 사람을 새 방식으로 옮긴다.
        // 둘 다 남겨 두면 로그인할 때 두 벌이 뜬다.
        LoginItem.migrateLegacyAgent()
        // 앱을 옮겼다면 로그인 항목이 가리키는 경로를 맞춰 둔다 (켜져 있을 때만 동작한다).
        LoginItem.reconcile()

        // 네트워크 변경 감시가 본선이다.
        let monitor = NetworkChangeMonitor { [weak self] in
            Task { @MainActor in await self?.refreshAndEvaluate() }
        }
        let watching = monitor.start()
        self.monitor = monitor

        // 주기 확인은 보조다. SCDynamicStore 가 놓치는 경우(절전에서 깨어난 직후 등)를 위한 그물이지
        // 감시의 본체가 아니므로 간격을 넉넉히 둔다.
        // 감시를 붙이지 못했다면 주기 확인이 유일한 수단이 되므로 간격을 좁힌다.
        let timer = Timer.scheduledTimer(withTimeInterval: watching ? 60 : 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAndEvaluate() }
        }
        timer.tolerance = watching ? 15 : 2
        refreshTimer = timer

        // 시스템 설정에 다녀와 앱으로 돌아오면 권한을 다시 확인한다.
        //
        // 설정 창은 이미 자기 몫을 이렇게 챙기고 있다(`SettingsWindowController`). 그런데 그 창은
        // **자기 화면만** 고쳐 그린다 — 메뉴가 읽는 값은 그대로 낡은 채로 남는다. 그래서 메뉴 쪽에도 둔다.
        //
        // 다만 이것만으로는 부족하다. 메뉴바 전용 앱(`.accessory`)은 상태 항목을 눌러도 활성화되지
        // 않아, 설정 창을 열지 않은 사용자에게는 이 알림이 오지 않는다. 그 경로는 `menuWillOpen` 이 맡는다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAndEvaluate() }
        }

        // 메뉴바에 아이콘이 보이지 않을 때의 비상구 — 앱을 한 번 더 실행하면 설정 창이 열린다.
        DistributedNotificationCenter.default().addObserver(
            forName: AppDelegate.showSettingsRequest,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
    }

    // MARK: - 상태 갱신

    /// 시스템을 다시 읽는다. 프로세스를 띄우므로 메인 스레드 밖에서 돈다.
    ///
    /// **직접 부르지 마라.** 겹쳐 돌면 낡은 관측이 새 값을 덮어쓴다 — `refreshAndEvaluate()` 만이 문이다.
    private func readSystem() async {
        // 알림 권한도 **관측값이다.** 시스템 설정에서 켜고 끈 것을 앱이 알아채는 자리가 여기밖에 없다
        // (`SwitchNotifier.refresh`). 시스템을 읽으러 온 김에 함께 묻는다 — 아래 `probe.read` 가
        // 서브프로세스를 서너 개 띄워 수백 ms 를 쓰는 것에 비하면 이 한 번의 조회는 값이 없다시피 하다.
        //
        // 먼저 묻는 데에는 이유가 있다. 메뉴를 여는 순간에도 이 경로로 들어오는데, 뒤에 두면
        // 느린 관측이 끝날 때까지 메뉴가 낡은 '알림 꺼짐' 을 들고 있게 된다.
        await notifier.refresh()

        let probe = self.probe
        let authorization = locationAuthority.state
        observation = await Task.detached(priority: .utility) { probe.read(locationAuthorization: authorization) }.value
        render()
        // 열려 있는 설정 창도 같은 관측을 보게 한다. 위치 권한을 방금 허용한 순간이 여기다 —
        // 그때 처음 읽히는 Wi-Fi 이름이 창의 빈 칸으로 들어간다.
        if window(isVisible: settingsWindow) { settingsWindow?.update(observation: observation) }
    }

    private func window(isVisible controller: SettingsWindowController?) -> Bool {
        controller?.window?.isVisible == true
    }

    /// 읽고 나서 자동 전환을 판정한다. 네트워크 변경·주기 확인·메뉴 열기·권한 변경이 모두 이 문으로 들어온다.
    ///
    /// 진행 중인 갱신이 있으면 **겹쳐 읽지 않고** 뒤에 한 번만 이어 돈다. 이 직렬화가 없으면
    /// 늦게 시작한 읽기가 먼저 끝나는 순간 자동 전환이 낡은 관측으로 판정한다.
    private func refreshAndEvaluate() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        repeat {
            // 이번 회차가 소화할 요청이므로 먼저 내린다. 읽는 동안 새로 들어온 요청만 다음 회차로 남는다.
            refreshQueued = false
            await readSystem()
            evaluateAutoSwitch()
        } while refreshQueued
        isRefreshing = false
    }

    private func render() {
        let model = self.model
        guard model != renderedModel else { return }
        renderedModel = model

        statusItem.isVisible = true
        if let button = statusItem.button {
            if let image = StatusIcons.image(for: model.icon) {
                button.image = image
                button.title = ""
            } else {
                // 이미지가 없으면 폭 0 짜리 항목이 되어 메뉴바에서 아예 보이지 않는다.
                // 아이콘을 못 찾는 상황에서도 자리는 잡게 글자로 대신한다.
                button.image = nil
                button.title = "IP"
            }
            button.toolTip = [model.headline, model.detail].compactMap { $0 }.joined(separator: "\n")
            button.setAccessibilityTitle(model.headline)
        }
        rebuildMenu(model)
    }

    // MARK: - 자동 전환

    /// 지금 전환할 것인가를 정책에 묻고, 그대로 따른다.
    ///
    /// **판단은 여기에 없다.** 무한 루프를 막는 규칙(이미 같으면 no-op·정착 대기·백오프·중단)은
    /// 전부 `AutoSwitchPolicy` 에 있고 단위 테스트가 지킨다.
    private func evaluateAutoSwitch() {
        // Wi-Fi 가 바뀌었으면 지난 기록을 잊는다 (실패 기록 때문에 새 네트워크에서 굳지 않게).
        autoSwitchState.adopt(ssid: observation.ssid.name)

        let now = Date()
        let context = observation.autoSwitchContext(isEnabled: autoSwitchEnabled, isBusy: isSwitching)
        switch AutoSwitchPolicy.decide(context, state: autoSwitchState, now: now) {
        case .hold(let reason):
            autoSwitchHold = reason
            // 구성이 목표와 같아진 것을 **실제로 관측한** 순간이다. 여기서 시도 기록을 정산하지 않으면
            // 나중에 구성이 풀렸을 때 '적용했는데 효과가 없다' 로 굳어 그 Wi-Fi 에서 영영 멈춘다.
            if case .alreadyApplied(let profile) = reason {
                autoSwitchState.recordSettled(profile: profile, at: now)
            }
            announceIfBlockedByPermission(reason)
            render()
        case .apply(let profileName):
            autoSwitchHold = nil
            apply(profileName: profileName, userInitiated: false)
        }
    }

    /// 위치 권한이 없어 자동 전환이 성립하지 않는 상태는 조용히 넘어가면 안 된다.
    /// 다만 승인 창이 떠 있는 동안(아직 답하지 않음)에는 알리지 않는다 — 창 자체가 이미 안내다.
    private func announceIfBlockedByPermission(_ hold: AutoSwitchHold) {
        guard hold == .locationPermissionDenied, !announcedPermissionDenied else { return }
        announcedPermissionDenied = true
        notifier.post(SwitchAnnouncement.locationPermissionNeeded())
    }

    @objc private func toggleAutoSwitch() {
        autoSwitchEnabled.toggle()
        AutoSwitchPreferences.setEnabled(autoSwitchEnabled, in: preferenceStore)

        if autoSwitchEnabled {
            // 다시 자동에 맡긴다 — 지난 실패 기록을 여기서 거둔다.
            //
            // 실패 기록을 남겨 두면, 원인을 고치고(install.sh 재실행 등) 토글을 껐다 켠 사용자에게
            // **아무 일도 일어나지 않는다.** 같은 Wi-Fi 에 있는 한 앱을 다시 띄우는 것 말고 길이 없어진다.
            autoSwitchState.clearAttempts()
            autoSwitchHold = nil
            locationAuthority.requestIfNeeded()
            Task { await refreshAndEvaluate() }
        } else {
            autoSwitchHold = .disabled
            render()
        }
    }

    /// 백오프·중단으로 멈춘 자동 전환을 지금 다시 걸어 본다.
    ///
    /// 이 항목이 없으면 빠져나오는 길이 **Wi-Fi 를 갈아타는 것**뿐이다. sudoers 규칙이 풀려
    /// 다섯 번 실패한 뒤 사용자가 설치 스크립트를 다시 실행해도, 같은 자리에 앉아 있는 한
    /// 자동 전환은 멈춘 채로 남는다.
    @objc private func retryAutoSwitchNow() {
        autoSwitchState.clearAttempts()
        autoSwitchHold = nil
        Task { await refreshAndEvaluate() }
    }

    /// 시스템 설정의 해당 화면을 연다.
    ///
    /// **주소는 코어(`SystemSettingsPane`)가 들고 있다.** 설정 창의 같은 버튼과 한 자리를 쓴다 —
    /// 두 벌로 적어 두면 한쪽만 고쳐진 채 조용히 갈라진다.
    private func openSystemSettings(_ pane: SystemSettingsPane) {
        guard let url = URL(string: pane.url(revealing: Bundle.main.bundleIdentifier)) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openNotificationSettings() {
        openSystemSettings(.notifications)
    }

    // MARK: - 메뉴

    /// 메뉴는 네 무리다 — [지금 상태] · [프로필 고르기] · [자동 전환] · [앱]
    /// 무리마다 구분선을 넣어, 어디까지가 한 이야기인지 눈으로 끊기게 한다.
    /// **빈 무리는 서지 않는다** — 고를 프로필이 없으면 그 자리는 통째로 없다 (`MenuLayout`).
    ///
    /// 그릴 것은 인자로 받는다 — 그리는 중간에 상태를 다시 계산하면 머리말과 아래 항목이
    /// 서로 다른 순간의 값을 말할 수 있다.
    private func rebuildMenu(_ model: StatusModel) {
        menu.removeAllItems()

        // **구분선은 무리와 무리 사이에만 넣는다.** 무리가 사라지는 자리에서 구분선만 남으면
        // 아무것도 나누지 않는 선이 되고, 둘이 붙으면 빈 칸처럼 보인다. 어떤 무리가 서는지는
        // 코어가 정하고(`MenuLayout`), 항목을 내지 않는 무리는 애초에 오지 않는다.
        for (index, section) in MenuLayout.sections(model).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            add(section, of: model)
        }
    }

    private func add(_ section: MenuSection, of model: StatusModel) {
        switch section {
        case .status:
            // 첫 줄은 상태 한 마디이면서 설정 창으로 들어가는 문이다 (`MenuStyle.headline`).
            // 설정이 아직 없는 상태에서는 `StatusModel` 이 문구를 '초기 설정하기' 로 바꿔 놓는다.
            menu.addItem(MenuStyle.headline(
                model.headline, target: self, action: #selector(openSettingsFromMenu)
            ))
            if let detail = model.detail, !detail.isEmpty {
                menu.addItem(MenuStyle.secondary(detail))
            }

        case .profiles:
            for profile in model.profiles {
                let item = NSMenuItem(
                    title: profile.displayName,
                    action: #selector(selectProfile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.name
                // 체크 표시는 **잠긴 상태에서도** 그대로 선다 — 지금 무엇이 서 있는지를 말하는 자리다.
                item.state = profile.name == model.activeProfileName ? .on : .off
                // 자동 전환이 켜져 있으면 잠긴다 (권한 없음·전환 중과 같은 자리에서 정해진다).
                item.isEnabled = model.canSwitch
                menu.addItem(item)
            }

        case .autoSwitch:
            addAutoSwitchItems(model)

        case .app:
            let settings = NSMenuItem(title: "설정…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
            settings.target = self
            menu.addItem(settings)

            // macOS 관례는 '<앱 이름> 종료' 지만, 메뉴바 전용 앱에서 그 관례는 **긴 제품명 하나로
            // 메뉴 폭을 정하는 값**을 치른다. 어느 앱의 메뉴인지는 이미 눌러서 연 아이콘이 말한다.
            let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
        }
    }

    /// 자동 전환 토글과, 그 아래 딸린 것들.
    ///
    /// 순서에 뜻이 있다 — **액션(토글) 먼저, 딸린 상태가 그 아래, 조치할 액션이 그다음.**
    private func addAutoSwitchItems(_ model: StatusModel) {
        let toggle = NSMenuItem(title: "자동 전환", action: #selector(toggleAutoSwitch), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.autoSwitchEnabled ? .on : .off
        menu.addItem(toggle)

        for note in model.autoSwitchNotes {
            menu.addItem(MenuStyle.secondary(note))
        }

        // 멈춰 있는 상태에서 빠져나오는 손잡이. 누를 이유가 있을 때만 나타난다.
        if model.canRetryAutoSwitch {
            let retry = NSMenuItem(title: "지금 다시 시도", action: #selector(retryAutoSwitchNow), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)
        }

        // 이 항목은 누르면 메뉴가 닫히고 시스템 설정으로 넘어간다 — 그 뒤에 무엇을 해야 하는지
        // 말할 자리가 메뉴에는 없다. 그래서 **누르기 전에** 툴팁으로 그 한 문장을 붙여 둔다.
        // 문장은 설정 창·알림과 같은 자리에서 온다 (`SystemSettingsPane.openGuidance`).
        //
        // **위치 권한에는 같은 항목을 두지 않는다.** 그 권한이 막혀 있으면 초기 설정이 끝나지 않은
        // 상태라 이 무리 자체가 서지 않는다(`MenuLayout`) — 머리말이 '초기 설정하기' 로 말하고,
        // 실제 조치는 설정 창의 권한 섹션이 버튼으로 처리한다.
        if model.needsNotificationPermission {
            let item = NSMenuItem(title: "알림 설정 열기…", action: #selector(openNotificationSettings), keyEquivalent: "")
            item.target = self
            item.toolTip = SystemSettingsPane.notifications.openGuidance
            menu.addItem(item)
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // 열자마자 마지막 상태를 보여주고, 새로 읽은 값이 오면 열린 채로 갱신한다.
        //
        // **권한도 여기서 다시 읽는다**(`readSystem`). 메뉴를 여는 순간이 사용자가 상태를 확인하는
        // 순간이고, 메뉴바 전용 앱에서는 이 순간이 시스템 설정에 다녀온 것을 알아챌 가장 확실한 자리다.
        Task { await refreshAndEvaluate() }
    }

    func menuDidClose(_ menu: NSMenu) {
        // 실패 표시는 사용자가 메뉴에서 이유를 본 뒤에 거둔다.
        // (그 전에 지우면 아이콘만 잠깐 붉었다가 사라져 무슨 일이 있었는지 알 수 없다)
        if case .failed = action {
            action = .idle
            Task { await refreshAndEvaluate() }
        }
    }

    // MARK: - 동작

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        apply(profileName: name, userInitiated: true)
    }

    /// 프로필을 적용한다.
    /// - Parameter userInitiated: 사용자가 직접 고른 경우에만 실패를 창으로 알린다.
    ///   자동 전환은 `false` 로 불러 배경에서 조용히 실패하고 메뉴·알림에만 남긴다.
    func apply(profileName: String, userInitiated: Bool) {
        if isSwitching {
            // 사용자의 클릭을 조용히 버리지 않는다 — 누른 사람에게는 아무 반응 없이 사라진 것으로 보인다.
            // 지금 전환이 끝나면 이어서 적용한다. 자동 전환의 요청은 다음 판정에서 다시 오므로 쌓지 않는다.
            if userInitiated { queuedUserChoice = profileName }
            return
        }
        action = .switching(profile: profileName)
        // 시도 기록은 **적용을 실제로 시작하는 이 자리**에서 남긴다. 판정 쪽에 두면
        // 여기서 되돌아가는 경로가 생겼을 때 '시도했는데 결과가 없는' 기록만 남는다.
        if !userInitiated { autoSwitchState.recordAttempt(profile: profileName, at: Date()) }
        render()

        Task {
            let outcome = await Self.runApply(profileName: profileName)
            let now = Date()

            switch outcome {
            case .succeeded:
                action = .idle
                // 사용자가 직접 고른 전환은 기록하지 않는다. **자동 전환이 켜져 있는 동안에는
                // 프로필을 고를 수 없으므로**(`StatusModel.canSwitch`) 이 경로는 자동이 꺼져 있을 때만
                // 열리고, 꺼져 있는 자동에게는 남길 기록이 없다.
                if !userInitiated {
                    autoSwitchState.recordSuccess(at: now)
                    announceApplied(profileName)
                }
            case .failed(let message):
                action = .failed(profile: profileName, message: message)
                if userInitiated {
                    presentFailure(profileName: profileName, message: message)
                } else {
                    autoSwitchState.recordFailure(message: message, at: now)
                    announceFailure(profileName: profileName, message: message)
                }
            }

            // 결과를 반영해 다시 읽고 판정한다. 성공했으면 '이미 적용됨' 으로 조용해지고,
            // 실패했으면 백오프가 걸려 곧바로 다시 시도하지 않는다.
            await refreshAndEvaluate()

            // 전환 중에 사용자가 고른 것이 있으면 이제 처리한다.
            if let queued = queuedUserChoice {
                queuedUserChoice = nil
                apply(profileName: queued, userInitiated: true)
            }
        }
    }

    private enum ApplyOutcome: Sendable {
        case succeeded
        case failed(String)
    }

    private nonisolated static func runApply(profileName: String) async -> ApplyOutcome {
        await Task.detached(priority: .userInitiated) {
            do {
                try ApplyCommand.run(profileName: profileName)
                return ApplyOutcome.succeeded
            } catch {
                return ApplyOutcome.failed("\(error)")
            }
        }.value
    }

    // MARK: - 알림

    private func announceApplied(_ profileName: String) {
        guard let profile = profile(named: profileName) else { return }
        notifier.post(SwitchAnnouncement.applied(profile: profile, ssid: observation.ssid.name))
    }

    /// 실패는 **처음 한 번**과 **멈추기로 한 순간**만 알린다.
    /// 백오프로 재시도할 때마다 알리면 같은 말을 다섯 번 하게 된다.
    private func announceFailure(profileName: String, message: String) {
        guard let profile = profile(named: profileName) else { return }
        let failures = autoSwitchState.consecutiveFailures
        if failures == 1 {
            notifier.post(SwitchAnnouncement.failed(profile: profile, ssid: observation.ssid.name, reason: message))
        } else if failures >= AutoSwitchPolicy.failureLimit {
            notifier.post(SwitchAnnouncement.stopped(profile: profile, failures: failures))
        }
    }

    private func profile(named name: String) -> NetworkProfile? {
        observation.readyConfig?.profile(named: name)
    }

    private func presentFailure(profileName: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "'\(displayName(of: profileName))' 으로 전환하지 못했습니다"
        alert.informativeText = [message, Self.remedy(for: message)]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 실패 원문만으로는 무엇을 해야 할지 알 수 없는 경우에 한 줄을 덧붙인다.
    ///
    /// **터미널로 보내지 않는다.** 앱이 설치를 대신하게 된 뒤로도 이 두 줄만 옛 안내로 남아 있었다 —
    /// 창에서 버튼 한 번이면 되는 일에 터미널 명령을 내미는 셈이었다.
    private static func remedy(for message: String) -> String? {
        if message.contains("password is required") || message.contains("sudo") {
            return "무암호 규칙이 없어 전환할 때마다 암호를 묻습니다. 설정 창의 권한 섹션에서 다시 설치하세요."
        }
        if message.contains(InstallPaths.applyScript) {
            return "전환 권한이 설치돼 있지 않습니다. 설정 창의 권한 섹션에서 설치하세요."
        }
        return nil
    }

    private func displayName(of profileName: String) -> String {
        model.profiles.first { $0.name == profileName }?.displayName ?? profileName
    }

    // MARK: - 설정 창

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    /// 설정 창을 연다. 이미 열려 있으면 앞으로 가져온다 (`present` 가 `NSApp.activate` 까지 한다).
    ///
    /// **설정 창으로 들어가는 문은 이 함수 하나다** — 메뉴의 `설정…` · 첫 실행 온보딩 ·
    /// 다시 열기(`AppDelegate.applicationShouldHandleReopen`) · 다른 자리의 사본이 남긴 신호가 모두 여기로 온다.
    func openSettings() {
        // 위치 권한은 값을 넘기지 않고 **물어보는 길**을 넘긴다 — 창이 열려 있는 동안에도 바뀌기 때문이다.
        let controller = settingsWindow ?? SettingsWindowController(
            locationAuthorization: { [weak self] in self?.locationAuthority.state ?? .notDetermined },
            requestLocationPermission: { [weak self] in self?.locationAuthority.requestIfNeeded() },
            onSaved: { [weak self] in
                Task { @MainActor in await self?.refreshAndEvaluate() }
            }
        )
        settingsWindow = controller
        controller.present(observation: observation)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
