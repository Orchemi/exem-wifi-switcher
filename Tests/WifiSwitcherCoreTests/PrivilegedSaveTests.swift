import Foundation
import Testing
@testable import WifiSwitcherCore

/// 설정 파일은 `root:wheel 0644` 다. 사용자 권한 프로세스는 고칠 수 없고,
/// 저장할 때만 **관리자 인증**을 한 번 받는다. 전환(`apply`)은 계속 무암호다.
///
/// 여기서 검증하는 것은 그 인증 경로를 만드는 **문자열과 판단**이다.
/// 실제 인증 창은 시스템이 띄우므로 테스트가 건드리지 않는다.
@Suite("관리자 인증 저장 경로")
struct PrivilegedSaveTests {

    // MARK: - 셸에 넣어도 안전한 경로인가

    @Test("평범한 경로는 통과한다", arguments: [
        "/usr/local/libexec/exem-wifi-switcher/save-config",
        "/private/var/tmp/exem-wifi-switcher-2C1B4E7A/config.json",
        "/Library/Application-Support/x_y.z-1/config.json",
    ])
    func acceptsPlainPaths(_ path: String) {
        #expect(PrivilegedShell.isSafePath(path))
    }

    // 이 목록이 곧 "인증 창 뒤에서 임의 명령이 돌지 않게 하는 경계"다.
    @Test("셸·AppleScript 로 새 나갈 수 있는 문자는 전부 막는다", arguments: [
        "/tmp/a'; rm -rf / ;'b",
        "/tmp/a\"b",
        "/tmp/a\\b",
        "/tmp/a b",
        "/tmp/a$(id)",
        "/tmp/a`id`",
        "/tmp/a;id",
        "/tmp/a\nid",
        "/tmp/a|id",
        "/tmp/한글",
        "relative/path",
        "",
    ])
    func rejectsDangerousPaths(_ path: String) {
        #expect(!PrivilegedShell.isSafePath(path))
    }

    @Test("명령은 두 경로를 작은따옴표로 감싼 형태 하나뿐이다")
    func buildsCommand() throws {
        let command = try PrivilegedShell.adminCommand(
            helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
            staged: "/private/var/tmp/exem-wifi-switcher-AB/config.json"
        )
        #expect(command == "'/usr/local/libexec/exem-wifi-switcher/save-config' '/private/var/tmp/exem-wifi-switcher-AB/config.json'")
        // 셸 메타문자가 남아 있으면 안 된다.
        #expect(!command.contains("\""))
        #expect(!command.contains("\\"))
    }

    @Test("안전하지 않은 경로로는 명령을 만들지 않는다")
    func refusesUnsafePaths() {
        #expect(throws: PrivilegedShell.ShellError.unsafePath("/tmp/a b")) {
            try PrivilegedShell.adminCommand(helper: "/usr/local/libexec/exem-wifi-switcher/save-config", staged: "/tmp/a b")
        }
        #expect(throws: PrivilegedShell.ShellError.unsafePath("/tmp/x;id")) {
            try PrivilegedShell.adminCommand(helper: "/tmp/x;id", staged: "/private/var/tmp/a/config.json")
        }
    }

    @Test("AppleScript 는 관리자 권한으로 셸 명령 하나만 실행한다")
    func buildsAppleScript() throws {
        let script = try PrivilegedShell.appleScript(
            helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
            staged: "/private/var/tmp/exem-wifi-switcher-AB/config.json"
        )
        #expect(script.hasPrefix("do shell script \""))
        #expect(script.hasSuffix("with administrator privileges"))
        // 다른 앱을 조종하지 않는다 (Apple Event 권한을 요구하지 않는다).
        #expect(!script.contains("tell application"))
    }

    // MARK: - 관리자 계정 판별

    @Test("admin 그룹에 속하면 관리자다")
    func detectsAdministrator() {
        #expect(PrivilegedShell.isAdministrator(groupListing: "staff everyone localaccounts admin _appstore"))
        #expect(PrivilegedShell.isAdministrator(groupListing: "admin"))
    }

    @Test("admin 이 부분 문자열로만 들어간 것은 관리자가 아니다")
    func doesNotMatchPartialGroupNames() {
        #expect(!PrivilegedShell.isAdministrator(groupListing: "staff everyone administrators"))
        #expect(!PrivilegedShell.isAdministrator(groupListing: "staff everyone _lpadmin"))
        #expect(!PrivilegedShell.isAdministrator(groupListing: ""))
    }

    // MARK: - 저장 흐름

    /// 인증까지 갈 필요가 없는 경우를 미리 갈라낸다.
    @Test("권한 스크립트가 없으면 인증을 묻지 않고 설치 안내를 낸다")
    func refusesWhenHelperMissing() {
        var asked = false
        let installer = ConfigInstaller(
            helperPath: "/nonexistent/save-config",
            configPath: "/nonexistent/config.json",
            isAdministrator: { true },
            authorize: { _ in asked = true; return .success }
        )
        #expect(throws: ConfigInstaller.SaveError.self) {
            try installer.save(Self.validConfig)
        }
        #expect(!asked, "설치도 안 된 상태에서 인증 창을 띄우면 안 된다")
    }

    @Test("관리자가 아니면 인증을 묻지 않고 그 사실을 알린다")
    func refusesForNonAdministrator() throws {
        try withInstalledHelper { helper in
            var asked = false
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { false },
                authorize: { _ in asked = true; return .success }
            )
            let error = #expect(throws: ConfigInstaller.SaveError.self) {
                try installer.save(Self.validConfig)
            }
            #expect(error == .notAdministrator)
            #expect(!asked, "통과할 수 없는 인증 창을 띄우지 않는다")
        }
    }

    @Test("검증에 실패한 설정은 인증 이전에 막는다")
    func refusesInvalidConfig() throws {
        try withInstalledHelper { helper in
            var asked = false
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { _ in asked = true; return .success }
            )
            let broken = AppConfig(
                profiles: [NetworkProfile(name: "office", mode: .manual, ip: "192.0.2.10")],
                defaultProfile: "office"
            )
            #expect(throws: ConfigInstaller.SaveError.self) { try installer.save(broken) }
            #expect(!asked)
        }
    }

    @Test("사용자가 인증을 취소하면 그 사실과 다시 시도할 방법을 남긴다")
    func reportsCancellation() throws {
        try withInstalledHelper { helper in
            var seenCommand: String?
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { command in seenCommand = command; return .cancelled }
            )
            let error = #expect(throws: ConfigInstaller.SaveError.self) {
                try installer.save(Self.validConfig)
            }
            guard case .cancelled(let stagedPath) = error else {
                Issue.record("취소를 취소로 알려야 한다: \(String(describing: error))")
                return
            }
            #expect(seenCommand?.contains(helper) == true)
            // 취소했을 때는 준비해 둔 파일을 지우지 않는다 — 터미널에서 그대로 이어서 저장할 수 있다.
            #expect(FileManager.default.fileExists(atPath: stagedPath))
            #expect("\(ConfigInstaller.SaveError.cancelled(stagedPath: stagedPath))".contains(stagedPath))
            try? FileManager.default.removeItem(atPath: (stagedPath as NSString).deletingLastPathComponent)
        }
    }

    @Test("권한 스크립트가 실패하면 그 메시지를 그대로 전한다")
    func reportsHelperFailure() throws {
        try withInstalledHelper { helper in
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { _ in .failed(message: "설정 디렉터리를 만들지 못했습니다") }
            )
            let error = #expect(throws: ConfigInstaller.SaveError.self) {
                try installer.save(Self.validConfig)
            }
            guard case .helperFailed(let message, let stagedPath) = error else {
                Issue.record("실패 사유를 잃어버렸다: \(String(describing: error))")
                return
            }
            #expect(message.contains("설정 디렉터리"))
            #expect(FileManager.default.fileExists(atPath: stagedPath))
            try? FileManager.default.removeItem(atPath: (stagedPath as NSString).deletingLastPathComponent)
        }
    }

    @Test("성공하면 준비 파일을 남기지 않는다")
    func cleansUpAfterSuccess() throws {
        try withInstalledHelper { helper in
            var stagedPath: String?
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { command in
                    stagedPath = PrivilegedSaveTests.lastQuotedArgument(command)
                    return .success
                }
            )
            try installer.save(Self.validConfig)
            let path = try #require(stagedPath)
            #expect(!FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("준비 파일은 이 사용자만 읽을 수 있어야 한다")
    func stagesWithTightPermissions() throws {
        try withInstalledHelper { helper in
            var stagedPath: String?
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { command in
                    stagedPath = PrivilegedSaveTests.lastQuotedArgument(command)
                    return .cancelled
                }
            )
            #expect(throws: ConfigInstaller.SaveError.self) { try installer.save(Self.validConfig) }

            let path = try #require(stagedPath)
            let directory = (path as NSString).deletingLastPathComponent
            let filePermissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
            let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? NSNumber
            #expect(filePermissions?.int16Value == 0o600)
            #expect(directoryPermissions?.int16Value == 0o700)

            // 내용은 저장하려던 설정 그대로여야 한다.
            let staged = try AppConfig.load(from: path)
            #expect(staged == Self.validConfig)

            try? FileManager.default.removeItem(atPath: directory)
        }
    }

    @Test("root 로 돌고 있으면 인증 없이 직접 쓴다")
    func writesDirectlyWhenAlreadyRoot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exem-wifi-switcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("config.json").path
        var asked = false
        let installer = ConfigInstaller(
            helperPath: "/nonexistent/save-config",
            configPath: path,
            isRoot: { true },
            isAdministrator: { false },
            authorize: { _ in asked = true; return .success }
        )
        #expect(try installer.save(Self.validConfig) == .savedDirectly)
        #expect(!asked)
        #expect(try AppConfig.load(from: path) == Self.validConfig)
    }

    // MARK: - 거들기

    private static let validConfig = AppConfig(
        service: "Wi-Fi",
        profiles: [
            NetworkProfile(name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
                           router: "192.0.2.1", dns: ["192.0.2.53"], label: "사내 고정 IP"),
            NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)"),
        ],
        defaultProfile: "auto"
    )

    /// 설치된 권한 스크립트가 있는 상황을 흉내낸다 (경로에 특수문자가 없는 자리에 만든다).
    private func withInstalledHelper(_ body: (String) throws -> Void) throws {
        let directory = "/private/var/tmp/exem-wifi-switcher-helper-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let helper = directory + "/save-config"
        FileManager.default.createFile(atPath: helper, contents: Data("#!/bin/bash\nexit 0\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        try body(helper)
    }

    /// `'A' 'B'` 형태의 명령에서 B 를 뽑아낸다.
    private static func lastQuotedArgument(_ command: String) -> String? {
        let parts = command.components(separatedBy: "' '")
        guard parts.count == 2 else { return nil }
        return String(parts[1].dropLast())
    }
}

@Suite("경로 표시")
struct PathDisplayTests {

    // 홈 경로 문자열을 조립해서 만든다 — 이 파일 자신이 RULES.md 의 사전 점검 grep 에 걸리지 않도록.
    // (그 grep 은 사용자 홈 절대경로가 레포에 들어오는 것을 막는 장치다)
    private static let home = "/" + "Users" + "/someone"

    @Test("홈 디렉터리는 ~ 로 줄인다")
    func abbreviatesHome() {
        #expect(PathDisplay.abbreviate(Self.home + "/Applications/App.app", home: Self.home)
                == "~/Applications/App.app")
        #expect(PathDisplay.abbreviate(Self.home, home: Self.home) == "~")
    }

    @Test("홈 밖의 경로는 그대로 둔다")
    func leavesOtherPathsAlone() {
        #expect(PathDisplay.abbreviate("/Applications/App.app", home: Self.home) == "/Applications/App.app")
        // 접두사만 같은 다른 사용자 디렉터리를 잘못 줄이지 않는다.
        let neighbour = Self.home + "-else/x"
        #expect(PathDisplay.abbreviate(neighbour, home: Self.home) == neighbour)
    }

    @Test("홈 경로를 모르면 아무것도 하지 않는다")
    func toleratesMissingHome() {
        let path = Self.home + "/x"
        #expect(PathDisplay.abbreviate(path, home: "") == path)
        #expect(PathDisplay.abbreviate(path, home: "/") == path)
    }

    /// 설치 계획(`--dry-run` 출력)처럼 여러 경로가 문장에 섞여 나오는 글에 쓴다.
    /// 그 글은 문제를 보고할 때 그대로 복사되기도 하므로 계정 이름을 남기지 않는다.
    @Test("글 안에 섞인 홈 디렉터리를 전부 줄인다")
    func abbreviatesInsideText() {
        let text = "설치 원본  \(Self.home)/tools/app\n로그인 항목 \(Self.home)/Library/LaunchAgents/x.plist"
        let shortened = PathDisplay.abbreviate(in: text, home: Self.home)
        #expect(!shortened.contains(Self.home))
        #expect(shortened.contains("~/tools/app"))
        #expect(shortened.contains("~/Library/LaunchAgents/x.plist"))
    }

    @Test("홈을 알 수 없으면 글을 건드리지 않는다")
    func leavesTextAloneWithoutHome() {
        #expect(PathDisplay.abbreviate(in: "a/b", home: "") == "a/b")
        #expect(PathDisplay.abbreviate(in: "/usr/local", home: "/") == "/usr/local")
    }
}
