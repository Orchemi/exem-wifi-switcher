import Foundation
import Testing
@testable import WifiSwitcherCore

/// 로그인 항목(LaunchAgent) 등록에 쓰는 값.
///
/// 실제 등록은 하지 않는다 — 만들어질 plist 의 내용과, 등록을 거부해야 하는 조건만 본다.
/// (시스템에 무언가를 남기는 일은 사용자가 직접 한다)
@Suite("로그인 항목")
struct LoginItemTests {

    private func plist(_ contents: String) throws -> [String: Any] {
        let data = Data(contents.utf8)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(object as? [String: Any])
    }

    @Test("plist 는 앱 번들 안의 실행 파일을 가리킨다")
    func plistPointsIntoAppBundle() throws {
        let executable = "/Applications/EXEM Wifi Switcher.app/Contents/MacOS/EXEM Wifi Switcher"
        let parsed = try plist(LoginItem.plistContents(label: InstallPaths.agentLabel, executablePath: executable))

        #expect(parsed["Label"] as? String == "com.horbis.exem-wifi-switcher.agent")
        #expect(parsed["ProgramArguments"] as? [String] == [executable])
        #expect(parsed["RunAtLoad"] as? Bool == true)
        // 사용자가 앱을 종료했는데 launchd 가 되살리면 "끌 수 없는 앱" 이 된다.
        #expect(parsed["KeepAlive"] as? Bool == false)
    }

    @Test("맨 실행 파일은 등록하지 않는다")
    func refusesBareExecutable() {
        // Phase 0 에서 맨 실행 파일을 등록했다가 로그인 항목에 실행 파일 이름이 그대로 노출됐다.
        // 번들이 아니면 애초에 등록하지 않는다.
        #expect(throws: LoginItem.RegistrationError.notAnAppBundle("/usr/local/bin/exem-wifi-switcher")) {
            try LoginItem.executablePath(inAppBundle: "/usr/local/bin/exem-wifi-switcher")
        }
    }

    @Test("앱 번들이면 그 안의 실행 파일 경로를 만든다")
    func derivesExecutableFromBundle() throws {
        let path = try LoginItem.executablePath(inAppBundle: "/Applications/EXEM Wifi Switcher.app")
        #expect(path == "/Applications/EXEM Wifi Switcher.app/Contents/MacOS/EXEM Wifi Switcher")
        // 끝에 슬래시가 붙어 와도 같은 결과여야 한다.
        #expect(try LoginItem.executablePath(inAppBundle: "/Applications/EXEM Wifi Switcher.app/") == path)
    }

    /// 임시 디렉터리를 홈으로 삼는다. 사용자의 진짜 `~/Library/LaunchAgents` 는 건드리지 않는다.
    private func withTemporaryHome(_ body: (String) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("exem-wifi-switcher-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home.path)
    }

    @Test("등록하면 plist 만 놓는다 — 지금 떠 있는 앱을 한 벌 더 띄우지 않는다")
    func registerOnlyWritesPlist() throws {
        // launchctl bootstrap 을 함께 하면 RunAtLoad 때문에 launchd 가 두 번째 인스턴스를 띄운다.
        // 등록의 목적은 지금 실행이 아니라 다음 로그인이다.
        try withTemporaryHome { home in
            let bundle = "/Applications/EXEM Wifi Switcher.app"
            #expect(!LoginItem.isRegistered(homeDirectory: home))

            try LoginItem.register(appBundlePath: bundle, homeDirectory: home)

            #expect(LoginItem.isRegistered(homeDirectory: home))
            #expect(LoginItem.registeredExecutablePath(homeDirectory: home)
                == "\(bundle)/Contents/MacOS/EXEM Wifi Switcher")

            try LoginItem.unregister(homeDirectory: home)
            #expect(!LoginItem.isRegistered(homeDirectory: home))
        }
    }

    @Test("앱을 옮기면 등록된 경로를 따라 고친다")
    func reconcileFollowsMovedBundle() throws {
        try withTemporaryHome { home in
            try LoginItem.register(appBundlePath: "/tmp/staging/EXEM Wifi Switcher.app", homeDirectory: home)
            LoginItem.reconcile(appBundlePath: "/Applications/EXEM Wifi Switcher.app", homeDirectory: home)
            #expect(LoginItem.registeredExecutablePath(homeDirectory: home)
                == "/Applications/EXEM Wifi Switcher.app/Contents/MacOS/EXEM Wifi Switcher")
        }
    }

    @Test("등록돼 있지 않으면 아무것도 만들지 않는다")
    func reconcileDoesNothingWhenUnregistered() throws {
        try withTemporaryHome { home in
            LoginItem.reconcile(appBundlePath: "/Applications/EXEM Wifi Switcher.app", homeDirectory: home)
            #expect(!LoginItem.isRegistered(homeDirectory: home))
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
        #expect(uninstall.contains("Library/LaunchAgents/$AGENT_LABEL.plist"))
        // 앱이 남기는 설정값(UserDefaults)도 같은 번들 ID 아래에 쌓인다. 제거 대상에 들어 있어야 한다.
        #expect(uninstall.contains("Library/Preferences/$BUNDLE_ID.plist"))
        #expect(uninstall.contains("tccutil reset Location \"$BUNDLE_ID\""))
        #expect(LoginItem.plistFileName == "\(InstallPaths.agentLabel).plist")
    }
}
