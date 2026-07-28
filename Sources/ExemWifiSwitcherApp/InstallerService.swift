import AppKit
import WifiSwitcherCore

/// 설정 창의 [설치] · [제거] 버튼이 부르는 자리.
///
/// 하는 일은 셋뿐이다.
///   1. 번들이 서명 이후 바뀌지 않았는지 본다
///   2. `--dry-run` 을 돌려 **무엇을 할지** 를 그대로 받아 온다 (권한이 필요 없다)
///   3. 사용자가 확인하면 관리자 인증을 받아 **같은 스크립트**를 실행한다
///
/// 설치 절차를 여기서 흉내 내지 않는다. 판단도 하지 않는다 — 스크립트가 한다.
@MainActor
enum InstallerService {

    enum PreviewFailure: Error {
        /// 번들 밖에서 실행 중이거나 스크립트가 없다
        case unavailable(String)
        /// 번들이 서명 이후 바뀌었다
        case altered(String)
        /// 스크립트가 계획을 만들다 멈췄다 (예: /usr/local 소유자 문제)
        case refused(String)
    }

    struct Preview {
        /// `--dry-run` 이 출력한 계획 전문. 사람이 읽으라고 만든 글이다
        let plan: String
        /// 앱 설치가 막혔을 때 터미널로 이어서 할 수 있는 명령
        let terminalCommand: String
    }

    static var isAvailable: Bool { PermissionProbe.bundledInstallerAvailable() }

    static func scriptPath(for operation: BundledInstaller.Operation) -> String {
        BundledInstaller.scriptPath(for: operation, bundlePath: Bundle.main.bundlePath)
    }

    /// 무엇을 할지 미리 받아 온다. 시스템을 건드리지 않는다.
    static func preview(_ operation: BundledInstaller.Operation) async -> Result<Preview, PreviewFailure> {
        let path = scriptPath(for: operation)
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failure(.unavailable(BundledInstaller.InstallerError.scriptMissing(path).description))
        }

        // 서명 확인이 먼저다. 바뀐 번들이면 인증 창을 띄우기 전에 멈춘다.
        let bundlePath = Bundle.main.bundlePath
        let integrity = await Task.detached { BundleIntegrity.verify(bundlePath: bundlePath) }.value
        switch integrity {
        case .intact, .unknown:
            // 확인하지 못한 것을 어긋난 것으로 다루지 않는다 — 없는 근거로 막지 않는다.
            break
        case .altered(let reason):
            return .failure(.altered(reason))
        }

        let arguments: [String]
        do {
            arguments = try BundledInstaller.previewArguments(
                scriptPath: path, operation: operation, user: NSUserName()
            )
        } catch {
            return .failure(.unavailable("\(error)"))
        }

        let result = await Task.detached { try? SystemCommand.run(arguments) }.value
        guard let result else {
            return .failure(.unavailable("계획을 확인하지 못했습니다: \(path)"))
        }
        guard result.succeeded else {
            let message = [result.standardError, result.standardOutput]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            return .failure(.refused(clean(message)))
        }
        return .success(Preview(
            plan: clean(result.standardOutput),
            terminalCommand: BundledInstaller.terminalCommand(scriptPath: path)
        ))
    }

    /// 관리자 인증을 받아 스크립트를 실행한다. **확인을 받은 뒤에만 부른다.**
    ///
    /// 인증 창이 뜨는 동안 메인 스레드가 멈춘다 (설정을 저장할 때와 같은 경로다).
    static func run(_ operation: BundledInstaller.Operation) -> ConfigInstaller.AuthorizationResult {
        let command: String
        do {
            command = try BundledInstaller.command(
                scriptPath: scriptPath(for: operation), operation: operation, user: NSUserName()
            )
        } catch {
            return .failed(message: "\(error)")
        }
        return ConfigInstaller.runWithAdministratorPrivileges(command)
    }

    /// 화면에 옮기기 전에 다듬는다.
    ///
    /// - 터미널 색 코드는 창에서 글자 쓰레기로 보인다
    /// - 홈 디렉터리는 `~` 로 줄인다. 이 글은 문제를 보고할 때 그대로 복사되기도 한다
    private static func clean(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression
        )
        return PathDisplay.abbreviate(in: stripped)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
