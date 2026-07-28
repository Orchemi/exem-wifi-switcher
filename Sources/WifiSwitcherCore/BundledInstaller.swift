import Foundation

/// 앱 안에서 전환 권한을 설치·제거하는 길.
///
/// ## 왜 스크립트를 그대로 부르는가
///
/// 설치 로직은 `scripts/install.sh` 한 곳에만 있다. 앱은 그 스크립트를 **번들 안에 품고**
/// 관리자 인증을 받아 실행할 뿐이다. Swift 로 다시 구현하면 터미널로 설치한 사람과
/// 앱으로 설치한 사람이 다른 시스템을 갖게 된다 — 두 벌은 반드시 어긋난다.
///
/// ## 신뢰 경계
///
/// **앱은 신뢰 경계가 아니다.** `.app` 은 사용자가 쓸 수 있는 자리에 놓이므로, 번들 안 스크립트를
/// 고칠 수 있는 코드는 이 앱을 거치지 않고도 같은 일을 할 수 있다. 그래서 여기서 하는 일은
/// 경계를 세우는 것이 아니라 **경계를 넓히지 않는 것**이다.
///
/// - 인증 창 뒤 셸에 넘기는 것은 **우리가 만든 경로 하나 + 정해진 옵션**뿐이다.
///   경로는 `Bundle.main.bundlePath` 에서 조립하고, 파일 이름은 상수 둘 중 하나로 고정된다
/// - 그 경로를 다시 문자 화이트리스트로 검사한다 (사용자 입력이 섞일 자리를 남기지 않는다)
/// - root 로 올라간 스크립트는 **자기 자리가 남이 고칠 수 있는 곳인지 스스로 확인**한다
///   (`assert_self_is_safe` — `apply`·`save-config` 와 같은 발상)
/// - 실행 전에 `codesign --verify` 로 번들이 서명 이후 바뀌지 않았는지 본다.
///   ad-hoc 서명은 누구나 다시 만들 수 있으므로 **신뢰의 근거가 아니라 손댄 흔적을 잡는 장치**다
public enum BundledInstaller {

    public enum Operation: Equatable, Sendable {
        case install
        case uninstall

        var scriptName: String {
            switch self {
            case .install: return InstallPaths.installScriptName
            case .uninstall: return InstallPaths.uninstallScriptName
            }
        }

        /// 화면에 적는 이름. 판정과 같은 자리에 둔다.
        public var title: String {
            switch self {
            case .install: return "설치"
            case .uninstall: return "제거"
            }
        }
    }

    public enum InstallerError: Error, Equatable, CustomStringConvertible {
        case notBundled
        case scriptMissing(String)
        case unsafePath(String)
        case unsafeUserName(String)

        public var description: String {
            switch self {
            case .notBundled:
                return "앱 번들 밖에서 실행 중이라 설치 스크립트를 찾을 수 없습니다."
            case .scriptMissing(let path):
                return "앱 안에 설치 스크립트가 없습니다: \(path)"
            case .unsafePath(let path):
                return "관리자 권한으로 넘길 수 없는 경로입니다: '\(path)'"
            case .unsafeUserName(let name):
                return "계정 이름에 다룰 수 없는 문자가 있습니다: '\(name)'"
            }
        }
    }

    /// 번들 안 스크립트의 절대 경로. 있는지는 확인하지 않는다.
    public static func scriptPath(for operation: Operation, bundlePath: String) -> String {
        InstallPaths.bundledScript(operation.scriptName, inBundleAt: bundlePath)
    }

    /// 인증 창 뒤에서 실행할 명령 한 줄.
    ///
    /// - install:   `'<번들>/…/install.sh' --user '<계정>' --yes`
    /// - uninstall: `'<번들>/…/uninstall.sh' --user '<계정>' --yes --skip-running-app`
    ///
    /// `--yes` 를 붙이는 근거는 **부르는 쪽이 같은 내용을 먼저 보여주고 확인을 받는다**는 것이다
    /// (설정 창이 `--dry-run` 출력을 그대로 띄운다). 확인 없이 이 함수를 부르면 안 된다.
    ///
    /// `--user` 가 필요한 이유: 관리자 인증을 거치면 root 로 실행되는데, 그 자리에서는
    /// sudo 규칙을 적을 계정도 홈 디렉터리도 알 수 없다.
    public static func command(scriptPath: String, operation: Operation, user: String) throws -> String {
        guard PrivilegedShell.isSafeBundleScriptPath(scriptPath) else {
            throw InstallerError.unsafePath(scriptPath)
        }
        // 우리가 만든 경로가 맞는지 마지막으로 확인한다 — 임의 파일을 root 로 실행하지 않는다.
        guard scriptPath.hasSuffix("/\(InstallPaths.bundledScriptsSubpath)/\(operation.scriptName)") else {
            throw InstallerError.unsafePath(scriptPath)
        }
        guard PrivilegedShell.isSafeUserName(user) else {
            throw InstallerError.unsafeUserName(user)
        }
        var command = "'\(scriptPath)' --user '\(user)' --yes"
        if operation == .uninstall {
            // 앱이 자기 자신을 제거하는 길이다. 스크립트가 앱을 죽이면 결과를 볼 창이 사라진다.
            command += " --skip-running-app"
        }
        return command
    }

    /// 설치 전에 보여줄 계획을 뽑는 명령 (`--dry-run`). 권한이 필요 없고 아무것도 바꾸지 않는다.
    public static func previewArguments(scriptPath: String, operation: Operation, user: String) throws -> [String] {
        guard PrivilegedShell.isSafeBundleScriptPath(scriptPath) else {
            throw InstallerError.unsafePath(scriptPath)
        }
        guard PrivilegedShell.isSafeUserName(user) else {
            throw InstallerError.unsafeUserName(user)
        }
        // 셸을 거치지 않고 argv 로 넘긴다 — 여기서는 따옴표를 다룰 일이 없다.
        return ["/bin/bash", scriptPath, "--dry-run", "--user", user]
    }

    /// 터미널로 직접 하려는 사람에게 건네는 명령. 앱 설치가 막혔을 때의 출구다.
    ///
    /// `sudo` 를 붙이지 않는다 — 스크립트가 하는 일을 먼저 보여주고 확인을 받은 뒤
    /// 필요한 순간에만 스스로 승격한다. 앱을 거칠 때와 같은 순서다.
    /// 번들 경로에는 공백이 있으므로 따옴표를 붙여 그대로 붙여넣을 수 있게 한다.
    public static func terminalCommand(scriptPath: String) -> String {
        "\"\(scriptPath)\""
    }

    /// 터미널 안내에 쓰는 레포 기준 명령 (번들이 없을 때).
    public static func repositoryCommand(for operation: Operation) -> String {
        "./scripts/\(operation.scriptName)"
    }
}

/// 실행 중인 번들이 서명 이후 바뀌지 않았는가.
///
/// **ad-hoc 서명은 신뢰의 근거가 아니다.** 마음먹은 사람은 고친 뒤 다시 서명하면 된다.
/// 그래도 검사를 두는 이유는 두 가지다 — 내려받다 깨진 번들, 그리고 조용히 파일 하나만
/// 바꿔 둔 경우. 둘 다 여기서 걸린다. 이 검사가 통과했다고 "안전하다" 고 말하지 않는다.
public enum BundleIntegrity {

    public enum Verdict: Equatable, Sendable {
        case intact
        case altered(String)
        /// `codesign` 을 실행하지 못했다. 판정하지 않는다 — 없는 근거로 막지 않는다
        case unknown(String)
    }

    public static let codesignBinary = "/usr/bin/codesign"

    public static func verify(bundlePath: String) -> Verdict {
        guard !bundlePath.isEmpty else { return .unknown("번들 경로를 알 수 없습니다") }
        // 없는 번들은 '바뀌었다' 가 아니다. 그 경우는 스크립트 존재 확인이 먼저 잡는다.
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            return .unknown("번들이 없습니다: \(bundlePath)")
        }
        do {
            let result = try SystemCommand.run([codesignBinary, "--verify", "--strict", bundlePath])
            if result.succeeded { return .intact }
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return .altered(message.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unknown("\(error)")
        }
    }
}
