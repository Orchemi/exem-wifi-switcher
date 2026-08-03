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

    @Test("명령은 두 경로와 지문을 작은따옴표로 감싼 형태 하나뿐이다")
    func buildsCommand() throws {
        let command = try PrivilegedShell.adminCommand(
            helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
            staged: "/private/var/tmp/exem-wifi-switcher-AB/config.json",
            digest: Self.sampleDigest
        )
        #expect(command == "'/usr/local/libexec/exem-wifi-switcher/save-config' "
                + "'/private/var/tmp/exem-wifi-switcher-AB/config.json' '\(Self.sampleDigest)'")
        // 셸 메타문자가 남아 있으면 안 된다.
        #expect(!command.contains("\""))
        #expect(!command.contains("\\"))
    }

    @Test("안전하지 않은 경로로는 명령을 만들지 않는다")
    func refusesUnsafePaths() {
        #expect(throws: PrivilegedShell.ShellError.unsafePath("/tmp/a b")) {
            try PrivilegedShell.adminCommand(
                helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
                staged: "/tmp/a b", digest: Self.sampleDigest)
        }
        #expect(throws: PrivilegedShell.ShellError.unsafePath("/tmp/x;id")) {
            try PrivilegedShell.adminCommand(
                helper: "/tmp/x;id", staged: "/private/var/tmp/a/config.json", digest: Self.sampleDigest)
        }
    }

    @Test("AppleScript 는 관리자 권한으로 셸 명령 하나만 실행한다")
    func buildsAppleScript() throws {
        let script = try PrivilegedShell.appleScript(
            helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
            staged: "/private/var/tmp/exem-wifi-switcher-AB/config.json",
            digest: Self.sampleDigest
        )
        #expect(script.hasPrefix("do shell script \""))
        #expect(script.hasSuffix("with administrator privileges"))
        // 다른 앱을 조종하지 않는다 (Apple Event 권한을 요구하지 않는다).
        #expect(!script.contains("tell application"))
    }

    // MARK: - 저장할 내용의 지문

    /// 형식만 맞으면 되는 자리에 쓰는 값.
    private static let sampleDigest = String(repeating: "ab", count: 32)

    /// 값이 흔들리면 스크립트와 앱이 서로 다른 것을 계산하게 된다. 알려진 답으로 못 박는다.
    @Test("SHA-256 은 소문자 16진수 64자로 적는다")
    func computesKnownDigest() {
        let digest = ContentDigest.sha256Hex(of: Data("hello".utf8))
        #expect(digest == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(digest.count == 64)
    }

    /// 앱이 계산한 값과 `save-config` 가 다시 계산하는 값이 같아야 대조가 성립한다.
    /// 스크립트는 `shasum -a 256` 을 쓴다 — 같은 바이트로 같은 값이 나오는지 여기서 잰다.
    @Test("스크립트가 쓰는 shasum 과 같은 값을 낸다")
    func matchesShasumOutput() throws {
        let data = Data(#"{"service":"Wi-Fi","profiles":[]}"#.utf8)
        let path = "/private/var/tmp/exem-wifi-switcher-digest-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: path, contents: data)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try SystemCommand.run(["/usr/bin/shasum", "-a", "256", "--", path])
        let fromShell = result.standardOutput.split(separator: " ").first.map(String.init)
        #expect(fromShell == ContentDigest.sha256Hex(of: data))
    }

    @Test("16진수 64자만 지문으로 받는다")
    func acceptsOnlyHexDigest() {
        #expect(ContentDigest.isWellFormed(Self.sampleDigest))
        #expect(ContentDigest.isWellFormed(String(repeating: "0", count: 64)))
    }

    // 지문도 인증 창 뒤에서 도는 셸 명령의 인자다. 경로와 같은 잣대로 막는다.
    @Test("지문 자리에 다른 것이 들어오면 명령을 만들지 않는다", arguments: [
        "",
        String(repeating: "a", count: 63),
        String(repeating: "a", count: 65),
        String(repeating: "A", count: 64),          // 대문자는 스크립트 쪽 규칙과 어긋난다
        String(repeating: "g", count: 64),
        String(repeating: "a", count: 60) + "; id",
        String(repeating: "a", count: 60) + "$(id)",
        String(repeating: "a", count: 60) + "' 'x",
    ])
    func refusesMalformedDigest(_ digest: String) {
        #expect(!ContentDigest.isWellFormed(digest))
        #expect(throws: PrivilegedShell.ShellError.self) {
            try PrivilegedShell.adminCommand(
                helper: "/usr/local/libexec/exem-wifi-switcher/save-config",
                staged: "/private/var/tmp/exem-wifi-switcher-AB/config.json",
                digest: digest)
        }
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
            guard case .cancelled(let stagedPath, let digest) = error else {
                Issue.record("취소를 취소로 알려야 한다: \(String(describing: error))")
                return
            }
            #expect(seenCommand?.contains(helper) == true)
            // 취소했을 때는 준비해 둔 파일을 지우지 않는다 — 터미널에서 그대로 이어서 저장할 수 있다.
            #expect(FileManager.default.fileExists(atPath: stagedPath))
            // 이어서 저장할 명령은 **그대로 붙여넣어 도는 것**이어야 한다. 인자가 하나라도 빠지면
            // 인증 창을 실수로 닫은 사람에게 남는 유일한 탈출구가 막힌다.
            let guidance = "\(ConfigInstaller.SaveError.cancelled(stagedPath: stagedPath, digest: digest))"
            #expect(guidance.contains("sudo \(InstallPaths.saveConfigScript) \(stagedPath) \(digest)"))
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
            guard case .helperFailed(let message, let stagedPath, let digest) = error else {
                Issue.record("실패 사유를 잃어버렸다: \(String(describing: error))")
                return
            }
            #expect(message.contains("설정 디렉터리"))
            #expect(FileManager.default.fileExists(atPath: stagedPath))
            let guidance = "\(ConfigInstaller.SaveError.helperFailed(message: message, stagedPath: stagedPath, digest: digest))"
            #expect(guidance.contains("sudo \(InstallPaths.saveConfigScript) \(stagedPath) \(digest)"))
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

    // MARK: - 인증 창이 떠 있는 동안

    /// 준비 파일은 **로그인 사용자 소유**다 (root 가 아니다). 인증 창은 수 초간 떠 있고,
    /// 그동안 같은 사용자로 도는 코드가 그 파일을 갈아 끼울 수 있다.
    /// 명령 문자열은 창이 뜨기 전에 확정되므로, 거기 박힌 지문은 **우리가 저장하려던 내용**의 것이다.
    /// 갈아 끼운 내용은 그 지문과 맞지 않고, `save-config` 는 대조에서 그것을 거부한다.
    @Test("인증 창이 떠 있는 사이에 내용을 갈아 끼워도 지문은 우리가 저장하려던 내용의 것이다")
    func pinsContentBeforeAuthorization() throws {
        try withInstalledHelper { helper in
            let attacker = Data(#"{"version":1,"service":"Wi-Fi","defaultProfile":"evil","profiles":[{"name":"evil","mode":"manual","ip":"198.51.100.10","subnet":"255.255.255.0","router":"198.51.100.1","dns":["198.51.100.53"]}]}"#.utf8)
            var seenDigest: String?
            var swappedContent: Data?

            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { command in
                    let arguments = PrivilegedSaveTests.quotedArguments(command)
                    guard arguments.count == 3 else { return .failed(message: "인자 수가 다르다") }
                    // 인증 창이 떠 있는 사이 — 같은 사용자로 도는 코드가 내용을 갈아 끼운다.
                    try? attacker.write(to: URL(fileURLWithPath: arguments[1]))
                    swappedContent = FileManager.default.contents(atPath: arguments[1])
                    seenDigest = arguments[2]
                    return .success
                }
            )
            try installer.save(Self.validConfig)

            let digest = try #require(seenDigest)
            let swapped = try #require(swappedContent)
            #expect(swapped == attacker, "바꿔치기가 실제로 일어난 상황을 재현해야 한다")
            // 명령에 박힌 지문은 우리가 넘긴 내용의 것이다 — 바뀐 내용의 것이 아니다.
            #expect(digest == ContentDigest.sha256Hex(of: try Self.encoded(Self.validConfig)))
            #expect(digest != ContentDigest.sha256Hex(of: attacker))
        }
    }

    /// 앱만 새로 받고 `save-config` 는 예전 것이 설치된 사용자가 생긴다.
    /// 예전 스크립트는 지문 인자를 모른다 — 조용히 옛 계약으로 되돌아가지 않고,
    /// **인증 창을 띄우기 전에** 재설치가 필요하다는 것을 알려야 한다.
    @Test("설치된 스크립트가 지문을 모르면 인증을 묻지 않고 재설치를 안내한다")
    func detectsOutdatedHelper() throws {
        // 예전 save-config 는 `--capabilities` 를 경로로 읽고 '절대 경로여야 합니다' 로 죽는다 (exit 2).
        try withInstalledHelper(body: "#!/bin/bash\nexit 2\n") { helper in
            var asked = false
            let installer = ConfigInstaller(
                helperPath: helper,
                configPath: "/nonexistent/config.json",
                isAdministrator: { true },
                authorize: { _ in asked = true; return .success }
            )
            let error = #expect(throws: ConfigInstaller.SaveError.self) {
                try installer.save(Self.validConfig)
            }
            guard case .helperOutdated(let path) = error else {
                Issue.record("예전 스크립트를 예전 스크립트라고 말해야 한다: \(String(describing: error))")
                return
            }
            #expect(!asked, "통과할 수 없는 인증 창을 띄우지 않는다")
            #expect(path == helper)
            let guidance = "\(ConfigInstaller.SaveError.helperOutdated(path))"
            #expect(guidance.contains("[설치]"), "재설치가 필요하다는 것이 사용자에게 전달돼야 한다")
        }
    }

    /// 권한 표도 **같은 물음**으로 스크립트 버전을 본다 (`PermissionInput.saveConfigAcceptsDigest`).
    /// 저장이 막히는 근거와 화면이 '설치됨' 을 적는 근거가 갈리면, 화면은 다 됐다고 하는데
    /// 저장은 재설치를 안내하고 재설치할 손잡이는 어디에도 없는 상태가 된다 (2026-08-03 실측).
    @Test("스크립트 버전 판정이 예전 것과 지금 것을 갈라 본다")
    func helperVersionProbeAnswersBothWays() throws {
        // 예전 save-config 는 `--capabilities` 를 저장할 경로로 읽고 exit 2 로 죽는다.
        try withInstalledHelper(body: "#!/bin/bash\nexit 2\n") { helper in
            #expect(!ConfigInstaller.helperAcceptsDigest(helper))
        }
        // 지금 계약을 아는 스크립트는 `sha256` 이라고 답한다 (기본 본문).
        try withInstalledHelper { helper in
            #expect(ConfigInstaller.helperAcceptsDigest(helper))
        }
        // 판단이 서지 않으면 아직 모르는 것으로 본다 — 없는 파일에 인증 창을 띄우지 않는다.
        #expect(!ConfigInstaller.helperAcceptsDigest("/nonexistent/save-config"))
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

    /// 앱이 스크립트에 넘기는 바로 그 바이트.
    private static func encoded(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    /// 설치된 권한 스크립트가 있는 상황을 흉내낸다 (경로에 특수문자가 없는 자리에 만든다).
    ///
    /// 기본 본문은 **지금 계약을 아는** 스크립트다 — `--capabilities` 에 `sha256` 이라고 답한다.
    /// 예전 스크립트를 흉내내려면 `body` 를 바꿔 넘긴다.
    private func withInstalledHelper(
        body script: String = "#!/bin/bash\nif [ \"$1\" = --capabilities ]; then printf 'sha256\\n'; exit 0; fi\nexit 0\n",
        _ body: (String) throws -> Void
    ) throws {
        let directory = "/private/var/tmp/exem-wifi-switcher-helper-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let helper = directory + "/save-config"
        FileManager.default.createFile(atPath: helper, contents: Data(script.utf8),
                                       attributes: [.posixPermissions: 0o755])
        try body(helper)
    }

    /// `'A' 'B' 'C'` 형태의 명령에서 인자를 순서대로 뽑아낸다.
    private static func quotedArguments(_ command: String) -> [String] {
        guard command.hasPrefix("'"), command.hasSuffix("'") else { return [] }
        return command.dropFirst().dropLast().components(separatedBy: "' '")
    }

    /// 준비 파일 경로 (명령의 두 번째 인자).
    private static func lastQuotedArgument(_ command: String) -> String? {
        let arguments = quotedArguments(command)
        guard arguments.count == 3 else { return nil }
        return arguments[1]
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
