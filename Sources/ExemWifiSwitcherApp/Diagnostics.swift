import AppKit
import UserNotifications
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
        let authorization = LocationAuthority().state
        let observation = readOffMainThread(authorization: authorization)
        let enabled = AutoSwitchPreferences.isEnabled(in: UserDefaults.standard)

        var lines: [String] = []
        lines.append("\(InstallPaths.appName) 진단")
        lines.append("")
        // 이 출력은 문제 보고에 그대로 붙여넣으라고 만든 것이다. 사용자 이름이 함께 나가지 않게 줄인다.
        lines.append("앱 번들        \(PathDisplay.abbreviate(Bundle.main.bundlePath))")
        lines.append("번들 식별자    \(Bundle.main.bundleIdentifier ?? "없음 (번들 밖에서 실행됨)")")
        lines.append("위치 권한      \(text(for: authorization))")
        lines.append("알림 권한      \(notificationState())")
        lines.append("네트워크 감시  \(networkWatchState())")
        lines.append("Wi-Fi 이름     \(observation.ssid.statusText)")
        lines.append("자동 전환      \(enabled ? "켜짐" : "꺼짐")")
        lines.append("전환 권한      \(observation.helperInstalled ? "설치됨" : "없음 — ./scripts/install.sh 필요")")
        lines.append("저장 권한      \(saveAuthorityState())")
        lines.append("설정 파일      \(text(for: observation.config))")
        lines.append("현재 구성      \(currentConfiguration(observation))")
        lines.append("자동 전환 판정  \(decision(observation, enabled: enabled))")

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

    /// 알림이 막혀 있으면 자동 전환은 **완전히 무성**이 된다. 메뉴바 아이콘까지 보이지 않는 환경에서는
    /// 이 줄이 "IP 가 언제 바뀌었는지 알 수 없는 이유" 를 알려주는 유일한 자리다.
    ///
    /// 권한을 **묻지 않고 지금 상태만 읽는다.** 진단이 승인 창을 띄우면 안 된다.
    private static func notificationState() -> String {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            return "확인 불가 — 앱 번들 밖에서 실행 중입니다"
        }
        final class Box: @unchecked Sendable {
            var value: UNAuthorizationStatus = .notDetermined
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        // **`Task { }` 를 쓰면 안 된다** — 이 자리에서 만든 작업은 메인 액터에 격리되는데,
        // 아래에서 메인 스레드를 붙잡고 기다리므로 서로를 기다리는 교착이 된다.
        Task.detached {
            box.value = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            done.signal()
        }
        done.wait()

        switch box.value {
        case .authorized, .provisional, .ephemeral:
            return "허용됨"
        case .denied:
            return "거부됨 — 전환 알림이 뜨지 않습니다 (시스템 설정 > 알림)"
        case .notDetermined:
            return "아직 묻지 않음 (앱을 실행하면 승인 창이 뜹니다)"
        @unknown default:
            return "알 수 없음"
        }
    }

    /// 설정을 저장할 수 있는 상태인가. "저장이 안 된다" 의 원인이 대개 이 둘 중 하나다.
    private static func saveAuthorityState() -> String {
        let installed = FileManager.default.isExecutableFile(atPath: InstallPaths.saveConfigScript)
        guard installed else { return "없음 — ./scripts/install.sh 필요" }
        guard PrivilegedShell.currentUserIsAdministrator() else {
            return "설치됨 — 다만 이 계정은 관리자가 아니라 저장할 수 없습니다"
        }
        return "설치됨 (저장할 때 관리자 인증을 한 번 받습니다)"
    }

    /// `SCDynamicStore` 에 실제로 붙을 수 있는지 확인한다. 붙였다가 곧바로 뗀다.
    private static func networkWatchState() -> String {
        let monitor = NetworkChangeMonitor {}
        defer { monitor.stop() }
        return monitor.start() ? "정상 (SCDynamicStore)" : "실패 — 주기 확인으로만 동작합니다"
    }

    private static func text(for authorization: LocationAuthorizationState) -> String {
        switch authorization {
        case .granted: return "승인됨"
        case .denied: return "거부됨 — 시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스"
        case .notDetermined: return "아직 묻지 않음 (앱을 실행하면 승인 창이 뜹니다)"
        }
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
            let model = StatusModel.resolve(observation.statusInput(
                action: .idle, autoSwitchEnabled: true, autoSwitchHold: reason
            ))
            return "전환하지 않는다 — \(model.autoSwitchNote ?? "이유를 특정하지 못했습니다")"
        }
    }
}
