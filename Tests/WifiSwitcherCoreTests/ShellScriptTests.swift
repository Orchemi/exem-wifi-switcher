import Foundation
import Testing
@testable import WifiSwitcherCore

/// 테스트에서 레포 안의 파일을 찾을 때 쓰는 경로.
/// 컴파일 시점의 소스 위치에서 역산하므로 절대경로를 소스에 적어둘 필요가 없다.
enum RepositoryLayout {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/WifiSwitcherCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 레포 루트
}

@Suite("sudo -n 호출 조립")
struct ApplyCommandTests {

    @Test("프로필 이름 하나만 인자로 넘긴다")
    func buildsArguments() throws {
        let arguments = try ApplyCommand.arguments(profileName: "office")
        #expect(arguments == ["/usr/bin/sudo", "-n", "/usr/local/libexec/exem-wifi-switcher/apply", "office"])
        // 셸을 거치지 않으므로 인자는 항상 정확히 4개다 (문자열이 쪼개지지 않는다).
        #expect(arguments.count == 4)
    }

    @Test("위험한 이름은 명령을 만들기 전에 막는다", arguments: [
        "office; rm -rf /", "$(id)", "`id`", "../../etc/passwd", "office name", "", "*", "office\nid",
    ])
    func refusesDangerousNames(_ name: String) {
        #expect(throws: ApplyCommand.CommandError.invalidProfileName(name)) {
            try ApplyCommand.arguments(profileName: name)
        }
    }
}

@Suite("설치 스크립트")
struct ShellScriptTests {

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLayout.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> SystemCommand.Result {
        try SystemCommand.run(arguments)
    }

    @Test("셸 스크립트 검증이 전부 통과한다")
    func shellTestSuitePasses() throws {
        let script = RepositoryLayout.root.appendingPathComponent("Tests/shell/apply-tests.sh").path
        let result = try run(["/bin/bash", script])
        if !result.succeeded {
            Issue.record("Tests/shell/apply-tests.sh 실패\n\(result.standardOutput)\n\(result.standardError)")
        }
        #expect(result.succeeded)
    }

    @Test("스크립트에 문법 오류가 없다", arguments: ["scripts/apply", "scripts/install.sh", "scripts/uninstall.sh", "scripts/build-app.sh"])
    func scriptsHaveValidSyntax(_ relativePath: String) throws {
        let path = RepositoryLayout.root.appendingPathComponent(relativePath).path
        let result = try run(["/bin/bash", "-n", path])
        #expect(result.succeeded)
    }

    @Test("Swift 쪽 경로 상수와 스크립트의 경로가 같다")
    func pathConstantsMatchScripts() throws {
        let apply = try read("scripts/apply")
        let install = try read("scripts/install.sh")
        let uninstall = try read("scripts/uninstall.sh")

        let saveConfig = try read("scripts/save-config")

        #expect(apply.contains(InstallPaths.configFile))
        #expect(install.contains(InstallPaths.applyScript))
        #expect(install.contains(InstallPaths.saveConfigScript))
        #expect(install.contains(InstallPaths.configFile))
        #expect(install.contains(InstallPaths.sudoersFile))
        #expect(saveConfig.contains(InstallPaths.configFile))
        #expect(uninstall.contains(InstallPaths.libexecDirectory))
        #expect(uninstall.contains(InstallPaths.configDirectory))
        #expect(uninstall.contains(InstallPaths.sudoersFile))
    }

    /// 설정 파일을 잠근 것과, 그 잠금을 우회하지 않는다는 것이 같은 자리에서 지켜져야 한다.
    @Test("설정 파일을 root:wheel 0644 로 놓고, 저장 경로를 무암호로 열지 않는다")
    func locksConfigurationAndKeepsSavePathAuthenticated() throws {
        let install = try read("scripts/install.sh")

        // 설정 디렉터리·파일 모두 root 외에는 쓸 수 없어야 한다.
        #expect(install.contains("install -d -o root -g wheel -m 0755 \"$CONFIG_DIR\""))
        #expect(install.contains("install -o root -g wheel -m 0644 \"$REPO_ROOT/config.example.json\" \"$CONFIG_PATH\""))
        // 예전 버전이 남긴 root:admin 0664 를 그대로 두면 admin 그룹이 그대로 쓸 수 있다.
        #expect(install.contains("chown root:wheel \"$CONFIG_PATH\""))
        #expect(install.contains("chmod 0644 \"$CONFIG_PATH\""))
        #expect(!install.contains("-g admin"))

        // save-config 는 설치하되, sudoers 규칙에는 들어가지 않아야 한다.
        #expect(install.contains("install -o root -g wheel -m 0755 \"$REPO_ROOT/scripts/save-config\" \"$SAVE_CONFIG_PATH\""))
        let result = try run(["/bin/bash", RepositoryLayout.root.appendingPathComponent("scripts/install.sh").path, "--dry-run"])
        #expect(result.succeeded)
        let sudoersBlock = result.standardOutput
            .components(separatedBy: "Cmnd_Alias EXEM_WIFI_SWITCHER_APPLY").last ?? ""
        let rule = sudoersBlock.components(separatedBy: "NOPASSWD").first ?? sudoersBlock
        #expect(!rule.contains("save-config"),
                "save-config 가 무암호로 열리면 설정 파일을 root 소유로 잠근 의미가 사라진다")
    }

    @Test("root 로 도는 스크립트는 둘 다 같은 안전 규칙을 지킨다",
          arguments: ["scripts/apply", "scripts/save-config"])
    func privilegedScriptsShareSafetyRules(_ relativePath: String) throws {
        let script = try read(relativePath)
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("PATH=/usr/sbin:/usr/bin:/sbin:/bin"))
        #expect(script.contains("LC_ALL=C"))
        // 그룹 쓰기도 world 쓰기와 똑같이 막는다 (0002 만 보면 admin 그룹이 통과한다).
        #expect(script.contains("8#0022"))
        #expect(!script.contains("eval "))
        #expect(script.contains("assert_self_is_safe"))
    }

    /// 검사한 파일과 실제로 파싱하는 파일이 같아야 한다.
    @Test("apply 는 설정 파일을 한 번만 열어 사본에서만 파싱한다")
    func applyReadsConfigurationOnce() throws {
        let apply = try read("scripts/apply")
        #expect(apply.contains("open_config_snapshot"))
        #expect(apply.contains("/dev/fd/9"))
        // 사본을 만든 뒤에는 원본 경로를 다시 열지 않는다.
        #expect(!apply.contains("config_get \"$CONFIG_FILE\""))
        #expect(!apply.contains("find_profile_index \"$CONFIG_FILE\""))
        #expect(!apply.contains("load_profile_values \"$CONFIG_FILE\""))
    }

    @Test("프로필 이름 길이 상한이 스크립트와 같다")
    func nameLengthLimitMatchesScripts() throws {
        let expected = "PROFILE_NAME_MAX_LENGTH=\(ProfileName.maxLength)"
        let apply = try read("scripts/apply")
        let install = try read("scripts/install.sh")
        #expect(apply.contains(expected))
        #expect(install.contains(expected))
    }

    @Test("install.sh 는 sudoers 를 놓기 전에 visudo 로 검증한다")
    func installValidatesSudoersBeforeInstalling() throws {
        let install = try read("scripts/install.sh")
        #expect(install.contains("visudo -c -f \"$SUDOERS_TEMP\""))
        #expect(install.contains("sudo visudo -c"))

        // 검증 실패 시 설치하지 않고 중단하는 경로가 있어야 한다.
        #expect(install.contains("sudoers 파일을 설치하지 않았습니다"))
        // 설치 후 전체 검증이 실패하면 되돌린다.
        #expect(install.contains("sudo rm -f \"$SUDOERS_PATH\""))
    }

    @Test("권한 스크립트를 root:wheel 0755 로 놓는다")
    func installUsesRootOwnedPermissions() throws {
        let install = try read("scripts/install.sh")
        #expect(install.contains("install -d -o root -g wheel -m 0755 \"$LIBEXEC_DIR\""))
        #expect(install.contains("install -o root -g wheel -m 0755 \"$REPO_ROOT/scripts/apply\" \"$APPLY_PATH\""))
        #expect(install.contains("install -o root -g wheel -m 0440 \"$SUDOERS_TEMP\" \"$SUDOERS_PATH\""))
    }

    @Test("sudoers 규칙에 와일드카드 인자를 쓰지 않는다")
    func sudoersRuleHasNoWildcard() throws {
        let result = try run(["/bin/bash", RepositoryLayout.root.appendingPathComponent("scripts/install.sh").path, "--dry-run"])
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("Cmnd_Alias EXEM_WIFI_SWITCHER_APPLY"))
        #expect(result.standardOutput.contains("visudo -c 문법 검증 통과"))
        // `apply *` 처럼 임의 인자를 여는 형태가 있으면 안 된다.
        #expect(!result.standardOutput.contains("\(InstallPaths.applyScript) *"))
        // 길이별 고정 패턴이 이름 최대 길이만큼 있어야 한다.
        let patternCount = result.standardOutput.components(separatedBy: "\(InstallPaths.applyScript) [A-Za-z0-9]").count - 1
        #expect(patternCount == ProfileName.maxLength)
    }

    @Test("스크립트에 사용자 홈 경로가 하드코딩돼 있지 않다",
          arguments: ["scripts/apply", "scripts/install.sh", "scripts/uninstall.sh", "scripts/build-app.sh",
                      "Tests/shell/apply-tests.sh"])
    func scriptsHaveNoHardcodedHomePath(_ relativePath: String) throws {
        // 문자열을 조립해서 만든다 — 이 파일 자신이 RULES.md 의 사전 점검 grep 에 걸리지 않도록.
        let homePrefix = "/" + "Users" + "/"
        let contents = try read(relativePath)
        #expect(!contents.contains(homePrefix))
    }

    @Test("root 로 도는 스크립트에 eval 이 없다")
    func applyScriptHasNoEval() throws {
        let apply = try read("scripts/apply")
        #expect(!apply.contains("eval "))
        #expect(apply.contains("set -euo pipefail"))
    }
}
