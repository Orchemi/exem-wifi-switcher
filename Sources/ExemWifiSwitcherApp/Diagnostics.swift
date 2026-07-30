import AppKit
import WifiSwitcherCore

/// `--diagnose` 로 실행했을 때의 진단 출력.
///
/// **왜 앱 안에 있는가**: SSID 판독은 `.app` 번들 + 위치 권한이 있어야 한다. CLI 바이너리로는
/// 원리상 확인할 수 없다(Phase 0). 그래서 "Wi-Fi 이름이 읽히는가" 를 점검하는 자리는 앱뿐이다.
///
/// 메뉴바에 아이콘이 보이지 않는 환경에서 상태를 확인하는 통로이기도 하다.
///
/// **실제 주소는 찍지 않는다.** 진단에 필요한 것은 "고정 IP 인가 / 어느 프로필과 같은가" 이지
/// 주소 값 자체가 아니다. 사내 IP 가 터미널 기록·스크린샷으로 새 나가는 쪽이 손해가 크다.
@MainActor
enum Diagnostics {

    static func run() {
        // 승인 창을 띄우지 않고 지금 상태만 본다 — 진단이 시스템을 바꾸면 안 된다.
        let authority = LocationAuthority()
        var authorization = authority.state
        var observation = readOffMainThread(authorization: authorization)

        // `CLLocationManager` 는 만든 직후 '아직 묻지 않음' 을 돌려주고, 실제 값은 위치 데몬과
        // 이야기한 뒤에 온다. 한 번 찍고 끝나는 이 경로에는 그 순간이 오지 않아
        // **"위치 권한 아직 묻지 않음" 과 "Wi-Fi 이름 <읽힘>" 이 나란히 찍혔다.**
        //
        // Wi-Fi 이름이 읽혔다면 권한은 있는 것이다 — 그때는 기다릴 것도 없이 답이 나와 있다.
        // 읽히지도 않았고 상태도 정해지지 않았을 때만 잠깐 기다렸다가 다시 본다.
        if observation.ssid.name == nil, authorization == .notDetermined {
            authorization = authority.settledState()
            if authorization != .notDetermined {
                observation.ssid = readSSIDOffMainThread(authorization: authorization)
            }
        }

        let enabled = AutoSwitchPreferences.isEnabled(in: UserDefaults.standard)
        // 권한 판정은 설정 창과 **같은 자리**에서 가져온다. 여기서 문구를 따로 만들면 두 화면이 다른 답을 낸다.
        let permissions = PermissionReport.resolve(PermissionProbe.readBlocking(
            location: authorization,
            wifiNameVisible: observation.ssid.name != nil
        ))

        var lines: [String] = []
        lines.append("\(InstallPaths.appName) 진단")
        lines.append("")
        // 이 출력은 문제 보고에 그대로 붙여넣으라고 만든 것이다. 사용자 이름이 함께 나가지 않게 줄인다.
        lines.append("앱 번들        \(PathDisplay.abbreviate(Bundle.main.bundlePath))")
        lines.append("번들 식별자    \(Bundle.main.bundleIdentifier ?? "없음 (번들 밖에서 실행됨)")")
        lines.append("위치 권한      \(permissions.item(.location).diagnosticText)")
        lines.append("알림 권한      \(permissions.item(.notification).diagnosticText)")
        lines.append("네트워크 감시  \(networkWatchState())")
        lines.append("Wi-Fi 이름     \(observation.ssid.diagnosticText)")
        lines.append("자동 전환      \(enabled ? "켜짐" : "꺼짐")")
        lines.append("전환 권한      \(permissions.item(.switching).diagnosticText)")
        lines.append("저장 권한      \(permissions.item(.saving).diagnosticText)")
        lines.append("설정 파일      \(text(for: observation.config))")
        lines.append("현재 구성      \(currentConfiguration(observation))")
        lines.append("자동 전환 판정  \(decision(observation, enabled: enabled))")
        lines.append("메뉴바 아이콘  \(menuBarSeat())")

        print(lines.joined(separator: "\n"))
    }

    /// 관측은 **메인 스레드 밖에서** 한다.
    ///
    /// `SystemProbe.read` 는 백그라운드 전용이다 — 서브프로세스를 여럿 띄우고, SSID 판독 경로의
    /// `CLLocationManager.locationServicesEnabled()` 는 메인 스레드에서 부르면 시스템이 경고한다.
    /// `--diagnose` 는 그 전제를 깨고 메인에서 시작하므로 여기서 다시 넘긴다.
    /// 한 번 찍고 끝나는 경로라 메인을 잠깐 붙잡아도 잃을 것이 없다 (아직 실행 루프도 돌지 않는다).
    private static func readOffMainThread(authorization: LocationAuthorizationState) -> Observation {
        final class Box: @unchecked Sendable {
            var value = Observation.pending
        }
        let box = Box()
        let probe = SystemProbe()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = probe.read(locationAuthorization: authorization)
            done.signal()
        }
        done.wait()
        return box.value
    }

    /// 권한이 늦게 정해졌을 때 Wi-Fi 이름만 다시 읽는다.
    ///
    /// 전체 관측을 다시 돌리지 않는 이유: 나머지 값은 권한과 무관한데 서브프로세스만 여럿 더 뜬다.
    /// (`SystemProbe.read` 와 같은 이유로 메인 스레드 밖에서 읽는다)
    private static func readSSIDOffMainThread(authorization: LocationAuthorizationState) -> SSIDReading {
        final class Box: @unchecked Sendable {
            var value = SSIDReading.unavailable("아직 읽지 않았습니다")
        }
        let box = Box()
        let reader = WiFiSSIDReader()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = reader.read(authorization: authorization)
            done.signal()
        }
        done.wait()
        return box.value
    }

    /// 메뉴 막대 아이콘이 어디 있고 보이는가.
    ///
    /// **지금 좌표는 잴 수 없다.** 이 경로는 `NSApplication` 을 띄우지 않아 상태 항목이 없고
    /// (`main.swift`), 따로 돌고 있는 앱에게 물어볼 길도 없다. 그래서 지어내지 않고 **그 앱이
    /// 마지막으로 재서 남긴 것**을 말한다. 없는 값을 채우느니 없다고 적는 편이 낫다 —
    /// 이 줄이 없어서 오너는 접근성 API 를 손으로 두드려야 했다.
    ///
    /// 노치 유무만은 지금 잰다. `NSScreen` 은 앱 없이도 읽히고, 아이콘이 왜 가려졌는지는
    /// 대개 그 한 가지로 설명된다.
    private static func menuBarSeat() -> String {
        let store = UserDefaults.standard
        let hasNotch = NSScreen.main.map { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
        return MenuBarSeatReport.text(
            lastKnownHidden: HiddenIconNotice.lastKnownHidden(in: store),
            state: StatusItemSeat.state(autosaveName: StatusItemController.statusItemAutosaveName, in: store),
            hasNotch: hasNotch
        )
    }

    /// `SCDynamicStore` 에 실제로 붙을 수 있는지 확인한다. 붙였다가 곧바로 뗀다.
    private static func networkWatchState() -> String {
        let monitor = NetworkChangeMonitor {}
        defer { monitor.stop() }
        return monitor.start() ? "정상 (SCDynamicStore)" : "실패 — 주기 확인으로만 동작합니다"
    }

    private static func text(for config: ConfigStatus) -> String {
        switch config {
        case .missing(let path): return "없음 — \(PathDisplay.abbreviate(path))"
        case .pristineExample: return "예시 그대로 — 설정 창에서 값을 등록하세요"
        case .unusable(_, let reason): return "읽지 못함 — \(reason)"
        case .ready(let config): return "정상 (프로필 \(config.profiles.count)개, 기본 '\(config.defaultProfile)')"
        }
    }

    /// 주소 대신 **구성 방식과 일치하는 프로필**만 적는다.
    private static func currentConfiguration(_ observation: Observation) -> String {
        guard let interface = observation.interface else {
            return "읽지 못함 — \(observation.interfaceError ?? "이유 불명")"
        }
        let method = interface.isManual ? "고정 IP" : "자동 (DHCP)"
        guard let config = observation.readyConfig else { return method }
        if let matched = config.profiles.first(where: { interface.conforms(to: $0) }) {
            return "\(method) · 프로필 '\(matched.name)' 과 같음"
        }
        return "\(method) · 어떤 프로필과도 다름"
    }

    private static func decision(_ observation: Observation, enabled: Bool) -> String {
        var state = AutoSwitchState()
        state.adopt(ssid: observation.ssid.name)
        let context = observation.autoSwitchContext(isEnabled: enabled, isBusy: false)
        switch AutoSwitchPolicy.decide(context, state: state, now: Date()) {
        case .apply(let profile):
            return "'\(profile)' 로 전환한다"
        case .hold(.disabled):
            return "자동 전환이 꺼져 있다"
        case .hold(let reason):
            // 이유 문구는 메뉴와 같은 자리(StatusModel)에서 가져온다 — 두 벌로 갈라지지 않게.
            //
            // 메뉴가 실제로 **올리는** 줄(`autoSwitchNote`)이 아니라 판정 자체를 묻는다.
            // 메뉴는 머리말·액션 항목이 대신 말하는 이유를 걷어내지만, 진단에는 전부 필요하다.
            let reasonText = StatusModel.autoSwitchReason(
                reason,
                ssid: observation.ssid,
                profiles: observation.readyConfig?.profiles ?? []
            )
            return "전환하지 않는다 — \(reasonText ?? "이유를 특정하지 못했습니다")"
        }
    }
}
