import Foundation
import ServiceManagement
import Testing
@testable import WifiSwitcherCore

/// 로그인 항목.
///
/// **실제 등록은 하지 않는다.** `SMAppService` 를 부르는 자리(`enable` · `disable` · `reconcile` ·
/// `migrateLegacyAgent`)는 테스트가 건드리지 않는다 — 테스트가 사용자의 진짜 로그인 항목을
/// 켜거나 꺼서는 안 된다. 여기서 보는 것은 **판단**(상태 옮기기 · 이관 계획)과,
/// 옛 방식의 흔적을 임시 홈에서 다루는 길이다.
@Suite("로그인 항목")
struct LoginItemTests {

    // MARK: - 상태

    @Test("시스템이 말하는 상태를 앱의 상태로 옮긴다")
    func mapsSystemStatus() {
        #expect(LoginItem.state(from: .enabled) == .on)
        #expect(LoginItem.state(from: .notRegistered) == .off)
        // 등록은 돼 있는데 macOS 가 꺼 둔 자리. '꺼짐' 과 섞으면 "켰는데 안 뜬다" 를 설명할 수 없다.
        #expect(LoginItem.state(from: .requiresApproval) == .blockedBySystem)
    }

    @Test("한 번도 켠 적 없는 상태(notFound)는 '꺼짐' 이다 — 켤 수 없음이 아니다")
    func neverRegisteredIsSimplyOff() {
        // 재 보니 *한 번도 켠 적 없는 정상 번들*과 *맨 실행 파일*이 똑같이 notFound 를 돌려준다.
        // 이것을 '켤 수 없음' 으로 읽으면 **새로 받은 사람은 체크상자를 누를 수조차 없다.**
        #expect(LoginItem.state(from: .notFound) == .off)
        #expect(LoginItem.State.off.isToggleable)
    }

    @Test("켤 수 있는 자리인지는 상태가 아니라 번들이 말한다")
    func onlyAppBundlesCanRegister() {
        #expect(LoginItem.canRegister(
            bundlePath: "/Applications/EXEM Wifi Switcher.app", bundleIdentifier: InstallPaths.bundleIdentifier
        ))
        // 끝에 슬래시가 붙어 와도 같은 판단이어야 한다.
        #expect(LoginItem.canRegister(
            bundlePath: "/Applications/EXEM Wifi Switcher.app/", bundleIdentifier: InstallPaths.bundleIdentifier
        ))
        // 맨 실행 파일. Phase 0 에서 이것을 등록했다가 실행 파일 이름이 그대로 노출됐다.
        #expect(!LoginItem.canRegister(
            bundlePath: "/usr/local/bin", bundleIdentifier: InstallPaths.bundleIdentifier
        ))
        // 번들 식별자가 없으면 등록할 신원이 없다 (swift run 으로 띄운 개발 빌드).
        #expect(!LoginItem.canRegister(
            bundlePath: "/Applications/EXEM Wifi Switcher.app", bundleIdentifier: nil
        ))
    }

    @Test("막힌 상태도 체크상자는 켜짐으로 그린다 — 사용자가 켠 것은 사실이다")
    func blockedStateStillLooksChecked() {
        #expect(LoginItem.State.on.isCheckedInUI)
        #expect(LoginItem.State.blockedBySystem.isCheckedInUI)
        #expect(!LoginItem.State.off.isCheckedInUI)
        #expect(!LoginItem.State.unavailable.isCheckedInUI)
    }

    @Test("켤 수 없는 자리에서는 체크상자를 누를 수 없다")
    func unavailableIsNotToggleable() {
        #expect(!LoginItem.State.unavailable.isToggleable)
        for state in [LoginItem.State.on, .off, .blockedBySystem] {
            #expect(state.isToggleable)
        }
    }

    // MARK: - 옛 방식에서 넘어오기

    @Test("옛 흔적이 없으면 아무것도 하지 않는다")
    func migrationDoesNothingWithoutLegacyAgent() {
        for state in [LoginItem.State.on, .off, .blockedBySystem, .unavailable] {
            #expect(LoginItem.migrationPlan(legacyAgentExists: false, state: state) == .nothingToDo)
        }
    }

    @Test("옛 방식으로 켜 두었으면 새 방식으로 이어받고 옛 것은 걷어낸다")
    func migrationCarriesTheSettingOver() {
        let plan = LoginItem.migrationPlan(legacyAgentExists: true, state: .off)
        #expect(plan == LoginItem.MigrationPlan(removesLegacyAgent: true, enablesLoginItem: true))
    }

    @Test("이미 새 방식으로 켜져 있으면 옛 것만 걷어낸다 — 두 번 등록하지 않는다")
    func migrationDoesNotRegisterTwice() {
        let plan = LoginItem.migrationPlan(legacyAgentExists: true, state: .on)
        #expect(plan == LoginItem.MigrationPlan(removesLegacyAgent: true, enablesLoginItem: false))
    }

    @Test("macOS 가 꺼 둔 것을 앱이 되살리지 않는다")
    func migrationRespectsSystemDisable() {
        let plan = LoginItem.migrationPlan(legacyAgentExists: true, state: .blockedBySystem)
        #expect(plan == LoginItem.MigrationPlan(removesLegacyAgent: true, enablesLoginItem: false))
    }

    @Test("넘겨받을 수 없는 자리에서는 옛 것도 지우지 않는다")
    func migrationKeepsLegacyWhenItCannotTakeOver() {
        // 번들 밖에서 실행 중(개발 빌드)일 때 지워 버리면, 사용자가 켜 둔 자동 실행만 사라진다.
        #expect(LoginItem.migrationPlan(legacyAgentExists: true, state: .unavailable) == .nothingToDo)
    }

    /// 임시 디렉터리를 홈으로 삼는다. 사용자의 진짜 `~/Library/LaunchAgents` 는 건드리지 않는다.
    private func withTemporaryHome(_ body: (String) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("exem-wifi-switcher-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home.path)
    }

    private func placeLegacyAgent(in home: String) throws {
        let path = try LoginItem.legacyPlistPath(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: path))
    }

    @Test("옛 항목은 홈 아래 LaunchAgents 의 라벨 이름 파일이다")
    func legacyPlistPathIsUnderLaunchAgents() throws {
        let path = try LoginItem.legacyPlistPath(homeDirectory: "/var/empty")
        #expect(path == "/var/empty/Library/LaunchAgents/com.horbis.exem-wifi-switcher.agent.plist")
        #expect(LoginItem.legacyPlistFileName == "\(InstallPaths.agentLabel).plist")
    }

    @Test("옛 흔적을 알아보고 지운다")
    func detectsAndRemovesLegacyAgent() throws {
        try withTemporaryHome { home in
            #expect(!LoginItem.legacyAgentExists(homeDirectory: home))

            try placeLegacyAgent(in: home)
            #expect(LoginItem.legacyAgentExists(homeDirectory: home))

            try LoginItem.removeLegacyAgent(homeDirectory: home)
            #expect(!LoginItem.legacyAgentExists(homeDirectory: home))
        }
    }

    @Test("지울 옛 흔적이 없어도 실패하지 않는다")
    func removingAbsentLegacyAgentSucceeds() throws {
        try withTemporaryHome { home in
            try LoginItem.removeLegacyAgent(homeDirectory: home)
            #expect(!LoginItem.legacyAgentExists(homeDirectory: home))
        }
    }

    @Test("제거 스크립트가 지우는 것과 같은 이름·경로를 쓴다")
    func matchesUninstallScript() throws {
        let uninstall = try String(
            contentsOf: RepositoryLayout.root.appendingPathComponent("scripts/uninstall.sh"), encoding: .utf8
        )
        // 스크립트는 번들 ID 하나에서 라벨·설정값 경로를 모두 파생시킨다. 그 뿌리가 같은지 본다.
        #expect(uninstall.contains("BUNDLE_ID=\(InstallPaths.bundleIdentifier)"))
        #expect(uninstall.contains("AGENT_LABEL=\"$BUNDLE_ID.agent\""))
        #expect(InstallPaths.agentLabel == "\(InstallPaths.bundleIdentifier).agent")
        // 옛 방식으로 켜 두었던 사람의 흔적은 제거 스크립트도 계속 지운다 (앱을 안 열고 지우는 길).
        #expect(uninstall.contains("Library/LaunchAgents/$AGENT_LABEL.plist"))
        // 앱이 남기는 설정값(UserDefaults)도 같은 번들 ID 아래에 쌓인다. 제거 대상에 들어 있어야 한다.
        #expect(uninstall.contains("Library/Preferences/$BUNDLE_ID.plist"))
        #expect(uninstall.contains("tccutil reset Location \"$BUNDLE_ID\""))
    }
}
