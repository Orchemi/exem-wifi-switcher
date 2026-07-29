import Foundation
import ServiceManagement

/// 로그인 시 자동 실행.
///
/// **`SMAppService.mainApp` 을 쓴다.** 서명 인증서가 없어도 된다 — ad-hoc 서명으로 실제 등록이
/// 되는지 재 보고 확인했다(2026-07-29). `SMAppService` 가 Developer ID 를 요구한다는 것은
/// **`SMAppService.daemon`**(root 데몬) 이야기였고, 앱 자신을 로그인 항목으로 올리는
/// `.mainApp` 에는 해당하지 않는다.
///
/// **왜 옛 방식(`~/Library/LaunchAgents` 에 plist 놓기)을 버렸는가** — 셋 다 사용자가 겪는 문제다.
///
/// 1. **엉뚱한 목록에 뜬다.** macOS 는 그 plist 를 `legacy agent` 로 분류해
///    시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램의 **아래쪽 '백그라운드에서 허용'** 에 넣는다.
///    사람이 찾는 곳은 위쪽 **'로그인 시 열기'** 다. `.mainApp` 은 `app` 으로 분류돼 그 위쪽에 뜬다.
/// 2. **상태를 읽을 수 없었다.** 파일이 있는지만 알 수 있어서, macOS 가 항목을 꺼도 앱의 체크상자는
///    켜진 채였다. `SMAppService.status` 는 꺼진 것까지 말해 준다(`blockedBySystem`).
/// 3. **끄는 길이 파일 삭제뿐이었다.** 시스템이 아는 상태와 앱이 아는 상태가 갈라질 자리가 늘 있었다.
///
/// 옛 방식으로 등록해 둔 사람의 plist 는 `migrateLegacyAgent()` 가 걷어낸다.
/// 그대로 두면 둘 다 살아 있어 로그인할 때 두 벌이 뜬다.
public enum LoginItem {

    // MARK: - 상태

    /// 로그인 항목이 지금 어떤 상태인가.
    ///
    /// 체크상자 하나로는 담기지 않는다 — **켜져 있다** 와 **켰는데 macOS 가 막고 있다** 는 다르고,
    /// 그 둘을 같은 모습으로 그리면 "켰는데 안 뜬다" 를 설명할 방법이 없어진다.
    public enum State: Equatable, Sendable {
        /// 다음 로그인에 열린다.
        case on
        /// 꺼져 있다.
        case off
        /// 등록은 돼 있는데 **macOS(사용자)가 시스템 설정에서 꺼 두었다.** 앱이 되돌릴 수 없다.
        case blockedBySystem
        /// 등록할 수 있는 항목이 없다 — `.app` 번들이 아닌 채로 실행 중일 때(개발 빌드·CLI).
        case unavailable

        /// 체크상자에 그릴 값. **막힌 상태도 켜짐으로 그린다** — 사용자가 켠 것은 사실이고,
        /// 막혀 있다는 말은 바로 아래 줄이 따로 한다. 여기서 꺼짐으로 그리면 다시 누르게 되고,
        /// 그래 봐야 이미 등록돼 있어 아무것도 달라지지 않는다.
        public var isCheckedInUI: Bool { self == .on || self == .blockedBySystem }

        /// 체크상자를 누를 수 있는가.
        public var isToggleable: Bool { self != .unavailable }
    }

    /// `SMAppService.Status` 를 앱이 다루는 상태로 옮긴다.
    ///
    /// **`notFound` 를 '켤 수 없음' 으로 읽으면 안 된다.** 재 보니 *한 번도 켠 적 없는 정상 번들*과
    /// *번들이 아닌 맨 실행 파일*이 똑같이 `notFound` 를 돌려준다 — 그 뜻은 "등록 기록이 없다" 이지
    /// "등록할 수 없다" 가 아니다. 여기서 갈랐다면 **새로 받은 사람은 체크상자를 누를 수조차 없었다.**
    /// 켤 수 있는 자리인지는 상태가 아니라 번들이 말한다 (`canRegister`).
    static func state(from status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .blockedBySystem
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    /// 이 자리에서 로그인 항목을 켤 수 있는가.
    ///
    /// `SMAppService.mainApp` 은 **번들을 등록한다.** 번들 밖에서 실행 중이면(개발 빌드·CLI)
    /// 등록할 대상 자체가 없다. `.app` 번들이 아니면 애초에 체크상자를 누를 수 없게 한다 —
    /// Phase 0 에서 맨 실행 파일을 등록했다가 로그인 항목에 실행 파일 이름이 그대로 노출된 적이 있다.
    public static func canRegister(bundlePath: String, bundleIdentifier: String?) -> Bool {
        let normalized = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return normalized.hasSuffix(".app")
    }

    /// 지금 상태. 시스템에게 묻는다.
    public static var state: State {
        guard canRegister(bundlePath: Bundle.main.bundlePath, bundleIdentifier: Bundle.main.bundleIdentifier)
        else { return .unavailable }
        return state(from: SMAppService.mainApp.status)
    }

    // MARK: - 켜기 · 끄기

    public enum RegistrationError: Error, Equatable, CustomStringConvertible {
        case missingHomeDirectory
        case fileFailed(String)
        case systemRefused(String)

        public var description: String {
            switch self {
            case .missingHomeDirectory:
                return "홈 디렉터리를 찾지 못해 로그인 항목을 다루지 못했습니다"
            case .fileFailed(let message):
                return "로그인 항목 파일을 다루지 못했습니다: \(message)"
            case .systemRefused(let message):
                return "macOS 가 로그인 항목 등록을 거부했습니다: \(message)"
            }
        }
    }

    /// 로그인 항목으로 등록한다. 사용자가 명시적으로 켰을 때만 부른다.
    ///
    /// 이미 등록돼 있어도 실패하지 않는다(여러 번 불러도 같은 결과 — 실기로 확인).
    public static func enable() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw RegistrationError.systemRefused("\(error)")
        }
    }

    /// 등록을 해제한다. 등록돼 있지 않아도 실패하지 않는다.
    public static func disable() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw RegistrationError.systemRefused("\(error)")
        }
    }

    /// 앱을 옮긴 뒤에도 로그인 항목이 **지금 자리의 앱**을 가리키게 한다.
    ///
    /// macOS 는 등록할 때의 번들 경로를 기억한다. `/Applications` 으로 옮기라고 안내하는 도구라
    /// 옮긴 뒤 옛 자리를 가리킨 채로 남을 자리가 있다. 켜져 있을 때만 다시 등록해 경로를 새로 쓴다.
    ///
    /// **꺼져 있거나 macOS 가 막아 둔 상태에서는 아무것도 하지 않는다** — 사용자가 끈 것을 되살리는 앱이 된다.
    public static func reconcile() {
        guard state == .on else { return }
        try? SMAppService.mainApp.register()
    }

    // MARK: - 옛 방식(LaunchAgent)에서 넘어오기

    public static let legacyPlistFileName = "\(InstallPaths.agentLabel).plist"

    /// `~/Library/LaunchAgents/<label>.plist`
    public static func legacyPlistPath(
        homeDirectory: String? = ProcessInfo.processInfo.environment["HOME"]
    ) throws -> String {
        guard let homeDirectory, !homeDirectory.isEmpty else { throw RegistrationError.missingHomeDirectory }
        return (homeDirectory as NSString)
            .appendingPathComponent("Library/LaunchAgents/\(legacyPlistFileName)")
    }

    /// 옛 방식으로 등록해 둔 흔적이 남아 있는가.
    public static func legacyAgentExists(homeDirectory: String? = nil) -> Bool {
        guard let path = try? legacyPlistPath(in: homeDirectory) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// 옛 항목을 걷어낼지, 새 방식으로 켤지.
    ///
    /// **순수한 판단만 담는다** — 파일도 시스템도 만지지 않으므로 표로 검사할 수 있다.
    public struct MigrationPlan: Equatable, Sendable {
        public var removesLegacyAgent: Bool
        public var enablesLoginItem: Bool

        public static let nothingToDo = MigrationPlan(removesLegacyAgent: false, enablesLoginItem: false)
    }

    /// - `unavailable` 일 때는 **옛 것도 지우지 않는다.** 새 방식으로 넘겨받을 수 없는 자리(번들 밖 실행)라
    ///   여기서 지우면 사용자가 켜 둔 자동 실행만 사라진다.
    /// - 이미 켜져 있거나 macOS 가 막아 둔 상태면 **옛 것만 걷어낸다.** 다시 등록하면 사용자가
    ///   시스템 설정에서 꺼 둔 것을 앱이 되살리는 셈이 된다.
    public static func migrationPlan(legacyAgentExists: Bool, state: State) -> MigrationPlan {
        guard legacyAgentExists, state != .unavailable else { return .nothingToDo }
        return MigrationPlan(removesLegacyAgent: true, enablesLoginItem: state == .off)
    }

    /// 옛 방식으로 등록해 둔 사람을 새 방식으로 옮긴다. 앱이 뜰 때 한 번 부른다.
    ///
    /// 둘 다 살아 있으면 로그인할 때 두 벌이 뜨므로(하나는 스스로 물러나지만, 시스템 설정에는
    /// 두 줄로 남는다) **옛 것을 지우는 일이 먼저다.**
    @discardableResult
    public static func migrateLegacyAgent(homeDirectory: String? = nil) -> MigrationPlan {
        let plan = migrationPlan(legacyAgentExists: legacyAgentExists(homeDirectory: homeDirectory), state: state)
        if plan.enablesLoginItem { try? enable() }
        if plan.removesLegacyAgent { try? removeLegacyAgent(homeDirectory: homeDirectory) }
        return plan
    }

    /// 옛 plist 를 떼어내고 지운다. 남는 것이 없어야 한다.
    public static func removeLegacyAgent(homeDirectory: String? = nil) throws {
        let path = try legacyPlistPath(in: homeDirectory)
        // 이번 로그인 세션에 이미 붙어 있을 수 있으니 떼어낸다. 붙어 있지 않으면 실패하고, 그건 무시해도 된다.
        // 테스트가 임시 홈을 넘겨 부를 때는 **시스템 launchd 를 건드리지 않는다.**
        if homeDirectory == nil {
            _ = try? SystemCommand.run(["/bin/launchctl", "bootout", legacyDomainTarget()])
        }
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw RegistrationError.fileFailed("\(error)")
        }
    }

    private static func legacyPlistPath(in homeDirectory: String?) throws -> String {
        if let homeDirectory { return try legacyPlistPath(homeDirectory: homeDirectory) }
        return try legacyPlistPath()
    }

    private static func legacyDomainTarget() -> String { "gui/\(getuid())/\(InstallPaths.agentLabel)" }
}
