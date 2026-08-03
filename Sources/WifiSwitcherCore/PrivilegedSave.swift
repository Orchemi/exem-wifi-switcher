import CryptoKit
import Foundation

/// 저장할 내용을 **인증 이전에** 못 박는 지문.
///
/// 앱은 내용을 임시 파일에 쓴 뒤 관리자 인증 창을 띄운다. 그 창은 수 초간 떠 있고,
/// 임시 파일의 소유자는 root 가 아니라 로그인 사용자다 — 그 사이에 같은 사용자로 도는 코드가
/// 내용을 갈아 끼울 수 있다. 파일은 바꿀 수 있어도 **이미 확정된 명령 인자는 바꿀 수 없으므로**,
/// 지문을 명령에 함께 실어 보내면 무엇을 저장하는지가 인증 이전에 정해진다.
///
/// 표기는 `shasum -a 256` 출력과 같은 **소문자 16진수 64자**다. `save-config` 가 설치 직전에
/// 같은 값을 다시 계산해 대조하므로, 두 자리의 규칙이 어긋나면 저장이 통째로 막힌다.
public enum ContentDigest {

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 소문자 16진수 64자인가. **허용 문자만 통과시키는** 화이트리스트다 —
    /// 이 값도 인증 창 뒤에서 도는 셸 명령의 인자가 되므로 경로와 같은 잣대로 본다.
    public static func isWellFormed(_ digest: String) -> Bool {
        guard digest.count == 64 else { return false }
        let allowed = Set("0123456789abcdef")
        return digest.allSatisfy { allowed.contains($0) }
    }
}

/// 설정 파일을 저장하는 길.
///
/// ## 왜 인증을 받는가
///
/// 설치된 `config.json` 은 **`root:wheel 0644`** 다. 사용자 권한으로 도는 프로세스는 고칠 수 없다.
/// 이 파일의 값(`dns` · `router`)은 NOPASSWD 로 열려 있는 `apply` 를 통해 root 의
/// `networksetup -setdnsservers` · `-setmanual` 인자가 된다. 파일이 사용자 쓰기 가능하면,
/// **암호를 모르는 채 그 사용자로 실행되는 코드**가 시스템 DNS 와 기본 게이트웨이를 갈아치울 수 있다.
/// 설치 전에는 두 작업 모두 관리자 인증이 필요했으므로, 그 델타가 곧 로컬 권한 상승이다.
///
/// ## 신뢰 경계
///
/// - **쓰기**(온보딩 저장)에는 관리자 인증을 받는다. 온보딩은 1회성이라 UX 손해가 작다
/// - **읽기·전환**(`apply`)은 계속 무암호다. 이 도구의 존재 이유가 거기에 있다
/// - 저장용 권한 경로(`save-config`)는 **sudoers NOPASSWD 에 넣지 않는다.**
///   넣는 순간 파일을 잠근 의미가 사라진다
///
/// ## 흐름
///
/// 1. 검증을 통과한 설정을 **사용자만 읽을 수 있는 임시 파일**(0700 디렉터리 / 0600 파일)에 쓰고,
///    그 내용의 SHA-256 을 함께 들고 있는다
/// 2. `do shell script "'…/save-config' '<임시파일>' '<지문>'" with administrator privileges` 로
///    관리자 인증을 한 번 받는다
/// 3. root 로 실행된 `save-config` 가 설치할 바로 그 바이트에서 지문을 다시 계산해 대조하고,
///    모양을 확인한 뒤 `root:wheel 0644` 로 제자리에 놓는다
///
/// 임시 파일 경로도 지문도 우리가 만들고 **문자 화이트리스트로 다시 검사**하므로, 인증 창 뒤에서
/// 도는 셸 명령에 사용자 입력이 섞여 들어갈 자리가 없다.
///
/// 지문이 하는 일은 인증 창이 떠 있는 **수 초 동안**의 델타를 막는 것이다. 임시 파일은
/// 로그인 사용자 소유라 그동안 갈아 끼울 수 있고, `save-config` 의 모양 검사(JSON · 키 존재)는
/// 공격자가 넣은 값도 통과시킨다. 그러면 그 값이 `root:wheel 0644` 로 설치되고, 그 뒤로는
/// 무암호로 열려 있는 `apply` 가 공격자의 DNS · 게이트웨이를 계속 적용한다.
public enum PrivilegedShell {

    public enum ShellError: Error, Equatable, CustomStringConvertible {
        case unsafePath(String)
        case unsafeDigest(String)

        public var description: String {
            switch self {
            case .unsafePath(let path):
                return "관리자 권한으로 넘길 수 없는 경로입니다: '\(path)'"
            case .unsafeDigest(let digest):
                return "저장할 내용의 지문이 16진수 64자가 아닙니다 (길이 \(digest.count))"
            }
        }
    }

    /// 관리자 인증 셸 명령에 넣어도 되는 경로인가.
    ///
    /// 작은따옴표로 감싸 넘기므로 `'` 하나만 막아도 셸은 안전하지만, AppleScript 문자열을
    /// 거치므로 `"` 와 `\` 도 막는다. 나머지는 **허용 문자만 통과시키는** 화이트리스트다 —
    /// 막을 문자를 나열하는 방식은 빠뜨린 하나가 곧 구멍이 된다.
    public static func isSafePath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count <= 1024 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+/")
        return path.allSatisfy { allowed.contains($0) }
    }

    /// 앱 번들 안의 스크립트 경로로 허용되는가.
    ///
    /// `isSafePath` 보다 **공백 하나만** 넓다. 제품명이 `EXEM Wifi Switcher.app` 이라
    /// 번들 경로에는 공백이 반드시 들어가는데, 이름을 바꿀 수는 없기 때문이다.
    /// 공백은 작은따옴표 안에서도 AppleScript 문자열 안에서도 아무 일도 하지 않는다.
    /// 나머지(`'` `"` `\` 제어문자 등)는 그대로 막는다 — 여전히 허용 목록 방식이다.
    ///
    /// 설정 저장 경로에는 이 완화를 쓰지 않는다. 그 경로는 우리가 만들고 공백이 필요 없다.
    public static func isSafeBundleScriptPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count <= 1024 else { return false }
        guard !path.hasSuffix(" ") else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+/ ")
        return path.allSatisfy { allowed.contains($0) }
    }

    /// sudoers 규칙과 홈 디렉터리를 찾는 데 쓰이는 계정 이름. 설치 스크립트의 검사와 같은 규칙이다.
    public static func isSafeUserName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return name.allSatisfy { allowed.contains($0) }
    }

    /// `'<헬퍼>' '<임시파일>' '<지문>'` — 인자 세 개짜리 명령 하나. 그 밖의 것은 실행하지 않는다.
    ///
    /// **지문을 뺀 형태는 만들지 않는다.** 그 형태가 남아 있으면 지문 없이 저장하는 길이
    /// 되살아나고, 인증 창이 떠 있는 동안의 바꿔치기를 다시 막지 못하게 된다.
    public static func adminCommand(helper: String, staged: String, digest: String) throws -> String {
        guard isSafePath(helper) else { throw ShellError.unsafePath(helper) }
        guard isSafePath(staged) else { throw ShellError.unsafePath(staged) }
        guard ContentDigest.isWellFormed(digest) else { throw ShellError.unsafeDigest(digest) }
        return "'\(helper)' '\(staged)' '\(digest)'"
    }

    /// 검증을 마친 셸 명령 하나를 관리자 권한으로 실행하는 AppleScript.
    /// 다른 앱을 조종하지 않으므로 자동화 권한을 요구하지 않는다.
    public static func appleScript(command: String) -> String {
        "do shell script \"\(command)\" with administrator privileges"
    }

    /// 두 경로와 지문을 검사한 뒤 그대로 AppleScript 로 만든다.
    public static func appleScript(helper: String, staged: String, digest: String) throws -> String {
        appleScript(command: try adminCommand(helper: helper, staged: staged, digest: digest))
    }

    /// `id -Gn` 출력에 `admin` 그룹이 있는가. 부분 일치(`_lpadmin`)를 관리자로 세지 않는다.
    public static func isAdministrator(groupListing: String) -> Bool {
        groupListing
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .contains("admin")
    }

    /// 지금 이 프로세스를 실행하는 계정이 관리자 그룹인가.
    public static func currentUserIsAdministrator() -> Bool {
        guard let result = try? SystemCommand.run(["/usr/bin/id", "-Gn"]) else { return false }
        return result.succeeded && isAdministrator(groupListing: result.standardOutput)
    }
}

/// 검증을 통과한 설정을 설치된 자리에 놓는다.
///
/// 의존하는 것(관리자 여부 판별 · 인증 실행)을 주입받으므로, 인증 창을 띄우지 않고도
/// "어떤 상황에서 무엇을 하는가" 를 전부 시험할 수 있다.
public struct ConfigInstaller {

    /// 인증 실행 결과.
    public enum AuthorizationResult: Equatable, Sendable {
        case success
        /// 사용자가 인증 창을 닫았다
        case cancelled
        /// 인증은 됐는데 스크립트가 실패했다
        case failed(message: String)
    }

    public enum SaveOutcome: Equatable, Sendable {
        /// 이미 root 라 인증 없이 바로 썼다 (`sudo` 로 도는 CLI)
        case savedDirectly
        /// 관리자 인증을 받아 권한 스크립트가 놓았다
        case savedWithAuthorization
    }

    public enum SaveError: Error, Equatable, CustomStringConvertible {
        case invalid([ValidationError])
        case helperMissing(String)
        case helperOutdated(String)
        case notAdministrator
        case stagingFailed(String)
        case unsafeStagedPath(String)
        case cancelled(stagedPath: String, digest: String)
        case helperFailed(message: String, stagedPath: String, digest: String)
        case directWriteFailed(String)

        public var description: String {
            switch self {
            case .invalid(let errors):
                return "설정 값에 문제가 있어 저장하지 않았습니다:\n" + errors.map { "  - \($0)" }.joined(separator: "\n")
            case .helperMissing(let path):
                return "전환 권한이 아직 설치돼 있지 않아 설정을 저장할 수 없습니다.\n"
                    + "레포 디렉터리에서 ./scripts/install.sh 를 먼저 실행하세요. (없는 파일: \(path))"
            case .helperOutdated(let path):
                return "설치된 저장 스크립트가 지금 앱보다 오래돼서 저장하지 않았습니다.\n"
                    + "설정 창의 권한 항목에서 [설치] 를 다시 실행하면 지금 앱에 맞는 스크립트로 바뀝니다.\n"
                    + "(오래된 파일: \(path))"
            case .notAdministrator:
                return "설정 파일은 root 소유라 저장하려면 관리자 계정이어야 합니다.\n"
                    + "지금 계정은 관리자 그룹이 아닙니다. 관리자 계정으로 로그인해 저장하거나, "
                    + "관리자에게 설정 파일 수정을 요청하세요."
            case .stagingFailed(let reason):
                return "저장할 내용을 임시 파일로 준비하지 못했습니다: \(reason)"
            case .unsafeStagedPath(let path):
                return "임시 파일 경로에 다룰 수 없는 문자가 있어 중단했습니다: \(path)"
            // 이어서 저장할 명령에는 **지문까지** 적는다. 하나라도 빠지면 그대로 붙여넣어도 돌지 않고,
            // 인증 창을 실수로 닫은 사람에게 남는 유일한 탈출구가 막힌다.
            case .cancelled(let stagedPath, let digest):
                return "관리자 인증을 취소해서 설정이 저장되지 않았습니다. 이전 설정이 그대로 남아 있습니다.\n"
                    + "다시 저장하거나, 터미널에서 아래 명령으로 이어서 저장할 수 있습니다:\n"
                    + "  sudo \(InstallPaths.saveConfigScript) \(stagedPath) \(digest)"
            case .helperFailed(let message, let stagedPath, let digest):
                return "설정을 저장하지 못했습니다. 이전 설정이 그대로 남아 있습니다.\n\(message)\n"
                    + "터미널에서 아래 명령으로 다시 시도할 수 있습니다:\n"
                    + "  sudo \(InstallPaths.saveConfigScript) \(stagedPath) \(digest)"
            case .directWriteFailed(let reason):
                return "설정 파일에 쓰지 못했습니다: \(reason)"
            }
        }
    }

    private let helperPath: String
    private let configPath: String
    private let isRoot: () -> Bool
    private let isAdministrator: () -> Bool
    private let helperAcceptsDigest: (String) -> Bool
    private let authorize: (String) -> AuthorizationResult

    public init(
        helperPath: String = InstallPaths.saveConfigScript,
        configPath: String = InstallPaths.configFile,
        isRoot: @escaping () -> Bool = { geteuid() == 0 },
        isAdministrator: @escaping () -> Bool = PrivilegedShell.currentUserIsAdministrator,
        helperAcceptsDigest: @escaping (String) -> Bool = ConfigInstaller.helperAcceptsDigest,
        authorize: @escaping (String) -> AuthorizationResult = ConfigInstaller.runWithAdministratorPrivileges
    ) {
        self.helperPath = helperPath
        self.configPath = configPath
        self.isRoot = isRoot
        self.isAdministrator = isAdministrator
        self.helperAcceptsDigest = helperAcceptsDigest
        self.authorize = authorize
    }

    /// 설정을 저장한다. 실패 사유는 **무슨 일이 일어났는지** 를 담아 그대로 화면에 옮길 수 있다.
    @discardableResult
    public func save(_ config: AppConfig) throws -> SaveOutcome {
        // 1) 검증이 먼저다. 못 쓸 값 때문에 인증 창을 띄우지 않는다.
        let errors = config.validate()
        guard errors.isEmpty else { throw SaveError.invalid(errors) }

        // 2) 이미 root 면 인증할 것이 없다 (sudo 로 도는 CLI·복구 상황).
        if isRoot() {
            do {
                try config.save(to: configPath)
            } catch {
                throw SaveError.directWriteFailed("\(error)")
            }
            return .savedDirectly
        }

        // 3) 통과할 수 없는 인증 창은 띄우지 않는다.
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw SaveError.helperMissing(helperPath)
        }
        guard isAdministrator() else { throw SaveError.notAdministrator }

        // 4) 설치된 스크립트가 지금 계약을 아는지 **인증 창을 띄우기 전에** 확인한다.
        //    앱만 새로 받은 사용자는 여기서 걸린다. 암호를 받아 놓고 실패하지 않는다.
        guard helperAcceptsDigest(helperPath) else { throw SaveError.helperOutdated(helperPath) }

        // 5) 내용을 사용자만 읽을 수 있는 자리에 준비하고, 그 내용의 지문을 든다.
        let staged = try stage(config)
        guard PrivilegedShell.isSafePath(staged.file) else {
            try? FileManager.default.removeItem(atPath: staged.directory)
            throw SaveError.unsafeStagedPath(staged.file)
        }

        // 6) 인증 창이 뜨기 **전에** 명령을 확정한다. 이 순간부터 저장할 내용은 지문에 묶인다 —
        //    준비 파일은 로그인 사용자 소유라 창이 떠 있는 동안 바뀔 수 있지만, 이 문자열은 못 바꾼다.
        let command: String
        do {
            command = try PrivilegedShell.adminCommand(
                helper: helperPath, staged: staged.file, digest: staged.digest)
        } catch {
            // 지문은 우리가 방금 계산한 값이라 여기까지 오는 길은 경로뿐이다.
            try? FileManager.default.removeItem(atPath: staged.directory)
            throw SaveError.unsafeStagedPath(helperPath)
        }

        // 7) 인증 → root 로 실행. 실패하면 준비한 파일을 **남겨 둔다** (터미널에서 이어서 저장 가능).
        switch authorize(command) {
        case .success:
            try? FileManager.default.removeItem(atPath: staged.directory)
            return .savedWithAuthorization
        case .cancelled:
            throw SaveError.cancelled(stagedPath: staged.file, digest: staged.digest)
        case .failed(let message):
            throw SaveError.helperFailed(message: message, stagedPath: staged.file, digest: staged.digest)
        }
    }

    // MARK: - 설치된 스크립트의 계약 확인

    /// 설치된 `save-config` 가 지문 인자를 아는가.
    ///
    /// `--capabilities` 는 root 가 필요 없고 아무것도 건드리지 않는다 — 그래서 **인증 창을
    /// 띄우기 전에** 물어볼 수 있다. 예전 스크립트는 이 인자를 저장할 파일 경로로 읽고
    /// "절대 경로여야 합니다" 로 죽으므로(exit 2), 대답 자체가 곧 버전 판별이 된다.
    ///
    /// 판단이 서지 않으면 **아직 모르는 것으로 본다**(fail closed). 지문을 모르는 스크립트에
    /// 인자를 하나 더 넘기면 어차피 exit 2 로 죽고, 그때는 사용자가 암호까지 입력한 뒤다.
    public static func helperAcceptsDigest(_ helperPath: String) -> Bool {
        guard let result = try? SystemCommand.run([helperPath, "--capabilities"]) else { return false }
        guard result.succeeded else { return false }
        return result.standardOutput
            .split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
            .contains("sha256")
    }

    // MARK: - 임시 파일

    /// 임시 파일을 두는 자리.
    ///
    /// `/private/var/tmp` 를 쓰는 이유는 **경로가 항상 ASCII** 라서다. 사용자별 임시 디렉터리
    /// (`/var/folders/…`)도 되지만 경로에 무엇이 들어올지 우리가 못 정한다. 여기에 이름을
    /// 무작위로 지은 0700 디렉터리를 새로 만들므로(이미 있으면 실패한다) 다른 사용자는 들여다볼 수 없다.
    static let stagingRoot = "/private/var/tmp"

    /// 지문은 **우리가 인코딩한 그 바이트**에서 낸다. 써 놓은 파일을 다시 읽어 계산하면
    /// 그 사이에 바뀐 내용의 지문을 스스로 인증해 주는 꼴이 되어 막으려던 것을 그대로 통과시킨다.
    private func stage(_ config: AppConfig) throws -> (directory: String, file: String, digest: String) {
        let directory = "\(Self.stagingRoot)/exem-wifi-switcher-\(UUID().uuidString)"
        let file = directory + "/config.json"
        let digest: String
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            digest = ContentDigest.sha256Hex(of: data)
            guard FileManager.default.createFile(
                atPath: file, contents: data, attributes: [.posixPermissions: 0o600]
            ) else {
                throw SaveError.stagingFailed("임시 파일을 만들지 못했습니다: \(file)")
            }
        } catch let error as SaveError {
            throw error
        } catch {
            throw SaveError.stagingFailed("\(error)")
        }
        return (directory, file, digest)
    }

    // MARK: - 실제 인증

    /// `NSAppleScript` 로 관리자 인증 창을 띄운다.
    ///
    /// 앱 프로세스 안에서 부르므로 인증 창이 **이 앱의 이름으로** 뜬다.
    /// 메인 스레드에서 불러야 한다.
    public static func runWithAdministratorPrivileges(_ command: String) -> AuthorizationResult {
        // 스크립트 본문을 여기서 다시 조립하지 않는다 — 두 벌이 되면 반드시 어긋난다.
        guard let script = NSAppleScript(source: PrivilegedShell.appleScript(command: command)) else {
            return .failed(message: "관리자 인증 스크립트를 준비하지 못했습니다")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .success }

        let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        // -128 = 사용자가 인증 창을 닫았다 (errAEEventUserCancelled)
        if number == -128 { return .cancelled }
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "알 수 없는 오류 (코드 \(number))"
        return .failed(message: message)
    }
}

/// 화면·진단에 경로를 적을 때의 다듬기.
public enum PathDisplay {

    /// 홈 디렉터리를 `~` 로 줄인다.
    ///
    /// `--diagnose` 출력은 문제 보고 시 그대로 붙여넣으라고 만든 것이다.
    /// 거기에 홈 디렉터리 절대경로가 찍히면 사용자 계정 이름이 함께 나간다.
    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        guard path.hasPrefix(prefix) else { return path }
        return "~/" + path.dropFirst(prefix.count)
    }

    /// 글 **안에 섞여 있는** 홈 디렉터리를 전부 `~` 로 줄인다.
    ///
    /// 설치 계획(`--dry-run` 출력)처럼 여러 경로가 문장에 섞여 나오는 글에 쓴다.
    /// 그 글은 문제를 보고할 때 그대로 복사되기도 하므로 계정 이름을 남기지 않는다.
    public static func abbreviate(in text: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, home != "/" else { return text }
        let trimmed = home.hasSuffix("/") ? String(home.dropLast()) : home
        return text.replacingOccurrences(of: trimmed, with: "~")
    }
}
