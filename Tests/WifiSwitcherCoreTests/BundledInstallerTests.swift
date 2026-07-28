import Foundation
import Testing
@testable import WifiSwitcherCore

/// 앱 안에서 설치·제거할 때 **인증 창 뒤로 넘어가는 문자열**.
///
/// 여기가 이 도구에서 가장 위험한 자리다 — 이 문자열이 root 로 실행된다.
/// 실제 인증은 시스템이 하므로 테스트가 건드리지 않고, 무엇이 넘어가는지만 못박는다.
@Suite("앱 안에서 설치·제거")
struct BundledInstallerTests {

    private let bundle = "/Applications/EXEM Wifi Switcher.app"

    private func script(_ operation: BundledInstaller.Operation) -> String {
        BundledInstaller.scriptPath(for: operation, bundlePath: bundle)
    }

    // MARK: - 경로

    @Test("설치 스크립트는 번들 안 정해진 자리에서만 온다")
    func scriptPathIsFixed() {
        #expect(script(.install)
            == "/Applications/EXEM Wifi Switcher.app/Contents/Resources/scripts/install.sh")
        #expect(script(.uninstall)
            == "/Applications/EXEM Wifi Switcher.app/Contents/Resources/scripts/uninstall.sh")
    }

    @Test("번들 경로 끝의 슬래시를 두 번 겹치지 않는다")
    func toleratesTrailingSlash() {
        #expect(BundledInstaller.scriptPath(for: .install, bundlePath: bundle + "/") == script(.install))
    }

    // MARK: - 명령 조립

    @Test("설치 명령은 스크립트 하나와 정해진 옵션뿐이다")
    func installCommand() throws {
        let command = try BundledInstaller.command(scriptPath: script(.install), operation: .install, user: "alice")
        #expect(command == "'\(script(.install))' --user 'alice' --yes")
        // 앱이 자기를 죽이는 옵션은 설치에 붙지 않는다.
        #expect(!command.contains("--skip-running-app"))
    }

    @Test("제거는 실행 중인 앱을 종료하지 않는다")
    func uninstallKeepsAppRunning() throws {
        // 앱이 자기 자신을 제거하는 길이다. 스크립트가 앱을 죽이면 결과를 볼 창이 사라진다.
        let command = try BundledInstaller.command(scriptPath: script(.uninstall), operation: .uninstall, user: "alice")
        #expect(command == "'\(script(.uninstall))' --user 'alice' --yes --skip-running-app")
    }

    @Test("계획을 미리 볼 때는 셸을 거치지 않고 아무것도 바꾸지 않는다")
    func previewUsesDryRun() throws {
        let arguments = try BundledInstaller.previewArguments(
            scriptPath: script(.install), operation: .install, user: "alice"
        )
        #expect(arguments == ["/bin/bash", script(.install), "--dry-run", "--user", "alice"])
        #expect(arguments.contains("--dry-run"))
        #expect(!arguments.contains("--yes"))
    }

    // MARK: - 넘겨서는 안 되는 것

    @Test("번들 안의 그 파일이 아니면 실행하지 않는다", arguments: [
        "/tmp/install.sh",
        "/Applications/EXEM Wifi Switcher.app/Contents/MacOS/EXEM Wifi Switcher",
        "/Applications/EXEM Wifi Switcher.app/Contents/Resources/scripts/apply",
        "/Applications/Other.app/Contents/Resources/scripts/uninstall.sh",
    ])
    func refusesForeignScripts(_ path: String) {
        #expect(throws: BundledInstaller.InstallerError.unsafePath(path)) {
            try BundledInstaller.command(scriptPath: path, operation: .install, user: "alice")
        }
    }

    @Test("셸·AppleScript 로 새 나갈 수 있는 경로는 막는다", arguments: [
        "/tmp/a'; rm -rf / ;'/Contents/Resources/scripts/install.sh",
        "/tmp/a\"b/Contents/Resources/scripts/install.sh",
        "/tmp/a\\b/Contents/Resources/scripts/install.sh",
        "/tmp/a$(id)/Contents/Resources/scripts/install.sh",
        "/tmp/a`id`/Contents/Resources/scripts/install.sh",
        "/tmp/a\nid/Contents/Resources/scripts/install.sh",
        "relative/Contents/Resources/scripts/install.sh",
    ])
    func refusesDangerousPaths(_ path: String) {
        #expect(throws: BundledInstaller.InstallerError.unsafePath(path)) {
            try BundledInstaller.command(scriptPath: path, operation: .install, user: "alice")
        }
    }

    @Test("sudoers 에 들어갈 계정 이름을 검사한다", arguments: [
        "bad name", "a;id", "a'b", "../root", "", "한글",
    ])
    func refusesDangerousUserNames(_ name: String) {
        #expect(throws: BundledInstaller.InstallerError.unsafeUserName(name)) {
            try BundledInstaller.command(scriptPath: script(.install), operation: .install, user: name)
        }
    }

    @Test("평범한 계정 이름은 통과한다", arguments: ["alice", "a", "first.last", "user_1", "a-b"])
    func acceptsPlainUserNames(_ name: String) {
        #expect(PrivilegedShell.isSafeUserName(name))
    }

    // MARK: - 경로 허용 규칙

    @Test("번들 경로에는 공백을 허용하되 그 하나만 넓힌다")
    func bundlePathAllowsSpaceOnly() {
        // 제품명에 공백이 있어 번들 경로에는 반드시 공백이 들어간다.
        #expect(PrivilegedShell.isSafeBundleScriptPath(script(.install)))
        // 설정 저장 경로에 쓰는 규칙은 그대로 좁게 둔다.
        #expect(!PrivilegedShell.isSafePath(script(.install)))
        for dangerous in ["/tmp/a'b", "/tmp/a\"b", "/tmp/a\\b", "/tmp/a\nb", "/tmp/한글", "relative"] {
            #expect(!PrivilegedShell.isSafeBundleScriptPath(dangerous))
        }
        #expect(!PrivilegedShell.isSafeBundleScriptPath("/Applications/trailing "))
    }

    // MARK: - 터미널로 빠져나가는 길

    @Test("앱 설치가 막혔을 때 붙여넣을 명령을 준다")
    func terminalFallback() {
        // 공백이 있는 경로라 따옴표가 없으면 두 인자로 쪼개진다.
        #expect(BundledInstaller.terminalCommand(scriptPath: script(.install)) == "\"\(script(.install))\"")
        #expect(BundledInstaller.repositoryCommand(for: .install) == "./scripts/install.sh")
        #expect(BundledInstaller.repositoryCommand(for: .uninstall) == "./scripts/uninstall.sh")
    }
}

/// 번들이 서명된 뒤 바뀌었는지 본다. **신뢰의 근거가 아니라 손댄 흔적을 잡는 장치**다.
@Suite("번들 무결성 확인")
struct BundleIntegrityTests {

    @Test("확인할 수 없는 것은 어긋났다고 말하지 않는다")
    func unknownIsNotAltered() {
        // 근거가 없을 때 막아 버리면, 확인이 안 되는 환경에서 설치가 통째로 불가능해진다.
        #expect(BundleIntegrity.verify(bundlePath: "") == .unknown("번들 경로를 알 수 없습니다"))
        if case .unknown = BundleIntegrity.verify(bundlePath: "/private/var/tmp/exem-no-such-bundle.app") {
            // 없는 경로도 판정하지 않는다 — 이 경로는 스크립트 존재 확인에서 이미 걸린다.
        } else {
            Issue.record("없는 번들을 '바뀌었다' 로 판정했습니다")
        }
    }

    @Test("서명이 온전한 번들은 통과한다")
    func intactBundlePasses() throws {
        // 이 레포가 만든 번들이 있으면 그것으로, 없으면 시스템 앱으로 확인한다.
        let candidates = [
            RepositoryLayout.root.appendingPathComponent("dist/EXEM Wifi Switcher.app").path,
            "/System/Applications/Calculator.app",
        ]
        guard let bundle = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }
        #expect(BundleIntegrity.verify(bundlePath: bundle) == .intact)
    }
}
