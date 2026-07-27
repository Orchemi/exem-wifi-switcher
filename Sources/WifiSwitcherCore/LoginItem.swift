import Foundation

/// 로그인 시 자동 실행 (LaunchAgent).
///
/// 서명 인증서가 없어 `SMAppService` 는 쓸 수 없다(Developer ID 를 요구한다).
/// 그래서 `~/Library/LaunchAgents` 에 plist 를 놓고 `launchctl` 로 붙이는 고전적인 경로를 쓴다.
///
/// **반드시 `.app` 번들 안의 실행 파일을 등록한다.** 맨 실행 파일을 등록하면 시스템 설정의
/// 로그인 항목에 실행 파일 이름이 그대로 노출된다 (Phase 0 에서 실제로 겪은 사고다).
public enum LoginItem {

    public static let plistFileName = "\(InstallPaths.agentLabel).plist"

    public enum RegistrationError: Error, Equatable, CustomStringConvertible {
        case notAnAppBundle(String)
        case missingHomeDirectory
        case launchctlFailed(exitCode: Int32, message: String)
        case fileFailed(String)

        public var description: String {
            switch self {
            case .notAnAppBundle(let path):
                return "앱 번들이 아니라서 로그인 항목으로 등록하지 않았습니다: \(path)\n"
                    + "scripts/build-app.sh 로 만든 '\(InstallPaths.appName).app' 을 실행한 상태에서만 등록할 수 있습니다."
            case .missingHomeDirectory:
                return "홈 디렉터리를 찾지 못해 로그인 항목을 다루지 못했습니다"
            case .launchctlFailed(let exitCode, let message):
                return "launchctl 이 실패했습니다 (종료 코드 \(exitCode)) \(message)"
            case .fileFailed(let message):
                return "로그인 항목 파일을 다루지 못했습니다: \(message)"
            }
        }
    }

    // MARK: - 경로

    /// `~/Library/LaunchAgents/<label>.plist`
    public static func plistPath(homeDirectory: String? = ProcessInfo.processInfo.environment["HOME"]) throws -> String {
        guard let homeDirectory, !homeDirectory.isEmpty else { throw RegistrationError.missingHomeDirectory }
        return (homeDirectory as NSString)
            .appendingPathComponent("Library/LaunchAgents/\(plistFileName)")
    }

    /// 앱 번들 경로에서 실행 파일 경로를 만든다. 번들이 아니면 등록하지 않는다.
    public static func executablePath(inAppBundle bundlePath: String) throws -> String {
        let normalized = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        guard normalized.hasSuffix(".app") else { throw RegistrationError.notAnAppBundle(bundlePath) }
        return (normalized as NSString).appendingPathComponent("Contents/MacOS/\(InstallPaths.appName)")
    }

    // MARK: - plist

    /// 등록에 쓰는 plist 본문 (XML).
    public static func plistContents(label: String, executablePath: String) -> String {
        let entries: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            // 사용자가 앱을 종료했는데 launchd 가 되살리면 끌 수 없는 앱이 된다.
            "KeepAlive": false,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    // MARK: - 상태
    //
    // 아래 함수들의 `homeDirectory` 는 테스트를 위한 이음매다. 값을 주면 그 디렉터리를 홈으로 보고,
    // **시스템 launchd 를 건드리지 않는다** — 테스트가 사용자의 진짜 로그인 항목을 떼어내면 안 된다.

    public static func isRegistered(homeDirectory: String? = nil) -> Bool {
        guard let path = try? plistPath(in: homeDirectory) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private static func plistPath(in homeDirectory: String?) throws -> String {
        if let homeDirectory { return try plistPath(homeDirectory: homeDirectory) }
        return try plistPath()
    }

    // MARK: - 등록 · 해제

    /// 등록된 plist 가 가리키는 실행 파일 경로. 등록돼 있지 않으면 nil.
    public static func registeredExecutablePath(homeDirectory: String? = nil) -> String? {
        guard let path = try? plistPath(in: homeDirectory),
              let data = FileManager.default.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let entries = object as? [String: Any]
        else { return nil }
        return (entries["ProgramArguments"] as? [String])?.first
    }

    /// 로그인 항목으로 등록한다. 사용자가 명시적으로 켰을 때만 부른다.
    ///
    /// **plist 를 놓기만 하고 `launchctl bootstrap` 은 하지 않는다.**
    /// 지금 앱이 떠 있는 상태에서 bootstrap 하면 `RunAtLoad` 때문에 launchd 가 한 벌 더 띄운다
    /// (메뉴바에 아이콘이 둘이 된다). 등록의 목적은 지금 실행이 아니라 **다음 로그인**이다.
    public static func register(appBundlePath: String, homeDirectory: String? = nil) throws {
        let executable = try executablePath(inAppBundle: appBundlePath)
        let path = try plistPath(in: homeDirectory)

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(plistContents(label: InstallPaths.agentLabel, executablePath: executable).utf8)
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw RegistrationError.fileFailed("\(error)")
        }
    }

    /// 앱을 옮긴 뒤에도 로그인 항목이 살아 있게 한다.
    ///
    /// 등록해 둔 경로와 지금 실행 중인 번들 경로가 다르면 plist 를 다시 쓴다.
    /// (앱을 `/Applications` 로 옮기라고 안내하므로, 옮긴 뒤 조용히 안 뜨는 일을 막는다)
    /// 등록돼 있지 않으면 아무것도 하지 않는다.
    public static func reconcile(appBundlePath: String, homeDirectory: String? = nil) {
        guard let registered = registeredExecutablePath(homeDirectory: homeDirectory),
              let current = try? executablePath(inAppBundle: appBundlePath),
              registered != current
        else { return }
        try? register(appBundlePath: appBundlePath, homeDirectory: homeDirectory)
    }

    /// 등록을 해제하고 파일까지 지운다. 남는 것이 없어야 한다.
    public static func unregister(homeDirectory: String? = nil) throws {
        let path = try plistPath(in: homeDirectory)
        // 이번 로그인 세션에 이미 붙어 있을 수 있으니 떼어낸다. 붙어 있지 않으면 실패하고, 그건 무시해도 된다.
        if homeDirectory == nil {
            _ = try? SystemCommand.run(["/bin/launchctl", "bootout", domainTarget()])
        }
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                throw RegistrationError.fileFailed("\(error)")
            }
        }
    }

    private static func domainTarget() -> String { "gui/\(getuid())/\(InstallPaths.agentLabel)" }
}
