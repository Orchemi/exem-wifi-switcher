import Foundation

/// 설치 경로 상수.
///
/// `scripts/install.sh` · `scripts/uninstall.sh` · `scripts/apply` 에 같은 값이 들어 있다.
/// **한 곳을 바꾸면 네 곳을 함께 바꿔야 한다.** (`swift test` 가 스크립트와의 일치를 검사한다)
public enum InstallPaths {

    /// root 권한 스크립트가 놓이는 디렉터리. 이 디렉터리와 상위 경로 전부 root 소유여야 한다.
    public static let libexecDirectory = "/usr/local/libexec/exem-wifi-switcher"

    /// 실제로 `networksetup` 을 호출하는 스크립트 (root:wheel 0755).
    /// **sudoers 가 이 경로만 NOPASSWD 로 연다.**
    public static let applyScript = libexecDirectory + "/apply"

    /// 설정 파일을 제자리에 놓는 스크립트 (root:wheel 0755).
    ///
    /// **sudoers 에 넣지 않는다.** 저장할 때마다 관리자 인증을 받는 것이 설정 파일을
    /// `root:wheel 0644` 로 잠근 이유이므로, 여기를 무암호로 열면 잠금이 무의미해진다.
    public static let saveConfigScript = libexecDirectory + "/save-config"

    /// 사용자 설정 디렉터리 (root:wheel 0755).
    public static let configDirectory = "/usr/local/etc/exem-wifi-switcher"

    /// 사용자 설정 파일 (root:wheel 0644). 레포에는 예시 파일만 둔다.
    ///
    /// 사용자 권한으로는 고칠 수 없다 — 값이 root 의 `networksetup` 인자가 되기 때문이다.
    /// 저장은 `ConfigInstaller` 가 관리자 인증을 받아 처리한다.
    public static let configFile = configDirectory + "/config.json"

    /// NOPASSWD 허용 규칙 (root:wheel 0440).
    public static let sudoersFile = "/etc/sudoers.d/exem-wifi-switcher"

    public static let sudoBinary = "/usr/bin/sudo"
    public static let networksetupBinary = "/usr/sbin/networksetup"

    /// 지금 쓰이는 리졸버를 읽을 때만 쓴다 (`scutil --dns`). **읽기 전용 호출이다.**
    public static let scutilBinary = "/usr/sbin/scutil"

    // MARK: - 앱 번들 (Phase 2)
    //
    // 이 값들은 계획 문서(docs/plan/001)의 "네이밍 (고정)" 표와 같아야 한다.
    // `scripts/build-app.sh` 가 만드는 Info.plist 와의 일치는 테스트가 검사한다.

    /// 제품 표시명. 번들 이름이자 번들 안 실행 파일의 이름이다.
    /// 실행 파일까지 같은 이름을 쓰는 이유: 시스템이 실행 파일 이름을 그대로 보여주는 자리가 있다.
    public static let appName = "EXEM Wifi Switcher"

    /// 번들 식별자. 위치 권한(TCC)이 이 값에 귀속된다 — 바꾸면 승인을 다시 받아야 한다.
    public static let bundleIdentifier = "com.horbis.exem-wifi-switcher"

    /// **0.1.0 이전** 로그인 항목(LaunchAgent)의 라벨. 지금 켜고 끄는 데는 쓰지 않는다.
    ///
    /// 로그인 항목은 `SMAppService.mainApp` 이 들고 있고 놓이는 파일이 없다 (`LoginItem.swift`).
    /// 이 값이 남아 있는 이유는 **옛 방식으로 켜 두었던 사람의 흔적을 걷어내는 것** 하나뿐이다 —
    /// `LoginItem.migrateLegacyAgent()` 와 `scripts/uninstall.sh` 가 같은 값으로 그 plist 를 지운다.
    public static let agentLabel = bundleIdentifier + ".agent"

    // MARK: - 번들이 품는 설치 스크립트
    //
    // 앱의 [설치] 버튼은 **터미널에서 쓰는 것과 같은 스크립트**를 관리자 인증을 거쳐 실행한다.
    // 설치 로직을 Swift 로 다시 구현하지 않는다 — 두 벌이 되면 반드시 어긋난다.
    // `scripts/build-app.sh` 가 아래 경로에 넣고, 그 뒤에 서명한다(내용이 서명에 봉인된다).

    /// 번들 안에서 설치 스크립트가 놓이는 자리. `build-app.sh` 와 같은 값이어야 한다.
    public static let bundledScriptsSubpath = "Contents/Resources/scripts"

    public static let installScriptName = "install.sh"
    public static let uninstallScriptName = "uninstall.sh"

    /// 번들 경로에서 설치 스크립트의 절대 경로를 만든다.
    ///
    /// 앱은 **자기 번들 경로만** 넘긴다. 임의 경로를 받는 자리가 없어야, 인증 창 뒤에서
    /// 실행되는 것이 무엇인지 코드만 읽고 알 수 있다.
    public static func bundledScript(_ name: String, inBundleAt bundlePath: String) -> String {
        let base = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        return "\(base)/\(bundledScriptsSubpath)/\(name)"
    }
}
