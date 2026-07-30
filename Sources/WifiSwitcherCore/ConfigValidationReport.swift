import Foundation

/// CLI `validate` 가 내놓는 답.
///
/// **여기 있는 이유는 앱과 CLI 가 같은 답을 말하게 하는 것이다.**
///
/// 예전에는 CLI 가 `AppConfig.load` 만 보고 `설정 파일이 유효합니다` 라고 답했다.
/// `load` 는 알 수 없는 키를 무시하므로, 설치 직후 예시 그대로인 파일(`_readme` 가 남아 있는 파일)도
/// 그 말을 들었다. 그런데 같은 파일을 앱은 `.pristineExample` 로 보고 `아직 저장 안 됨` 이라고 말한다.
/// 한 시스템을 두 도구가 다르게 말하면, 손으로 값을 고친 사람은 CLI 를 믿고 앱이 왜 안 도는지 알 길이 없다.
///
/// 그래서 판정을 새로 만들지 않고 **앱이 쓰는 `AppConfig.inspect` 를 그대로 쓴다.**
/// 판정이 하나뿐이면 두 도구가 갈라질 자리가 없다.
public struct ConfigValidationReport: Equatable, Sendable {

    /// 앱이 본 것과 **같은** 판정. 이 값이 곧 두 도구가 한 답을 말한다는 근거다.
    public let status: AppConfig.Status

    /// 화면에 그대로 옮길 줄들.
    public let lines: [String]

    /// 앱이 이 설정으로 자동 전환까지 할 수 있는가.
    ///
    /// `.ready` 하나만 참이다. 형식이 유효해도 예시 그대로면 앱은 쓰지 않으므로,
    /// 여기서도 "유효하다" 고 답하지 않는다.
    public var isReadyForApp: Bool { if case .ready = status { return true } else { return false } }

    public static func make(path: String = InstallPaths.configFile) -> ConfigValidationReport {
        let status = AppConfig.inspect(path: path)
        return ConfigValidationReport(status: status, lines: lines(for: status, path: path))
    }

    private static func lines(for status: AppConfig.Status, path: String) -> [String] {
        switch status {

        case .missing(let path):
            return [
                "설정 파일이 없습니다: \(path)",
                "  앱 판정: 아직 설정 전입니다 — 전환 권한을 설치하지 않았거나 파일이 지워졌습니다.",
                "  설정 창의 권한 항목에서 [설치] 를 누르면 예시 설정이 놓입니다.",
            ]

        case .pristineExample(let path):
            // 형식까지 함께 말해 준다 — "형식은 맞는데 아직 당신의 값이 아니다" 가 이 상태의 전부다.
            var lines = ["설정 파일 형식은 유효합니다: \(path)"]
            if let config = try? AppConfig.load(from: path) {
                lines.append(contentsOf: describe(config))
            }
            lines.append(contentsOf: [
                "  앱 판정: 아직 사용자 값이 아닙니다 (설치 스크립트가 복사한 예시 그대로입니다).",
                "  설명용 \"_readme\" 블록이 남아 있으면 앱은 '아직 저장 안 됨' 으로 보고,",
                "  자동 전환도 이 상태에서는 돌지 않습니다.",
                "  손으로 고쳤다면 \"_readme\" 블록을 지우세요.",
                "  앱의 설정 창에서 [저장]하면 그 블록까지 함께 사라집니다.",
            ])
            return lines

        case .unusable(let path, let reason):
            return [
                "설정 파일을 쓸 수 없습니다: \(path)",
                "  이유: \(reason)",
                "  앱 판정: 이 상태에서는 앱도 설정을 읽지 못합니다.",
            ]

        case .ready(let config):
            return ["설정 파일이 유효합니다: \(path)"]
                + describe(config)
                + ["  앱 판정: 그대로 쓸 수 있습니다."]
        }
    }

    private static func describe(_ config: AppConfig) -> [String] {
        [
            "  네트워크 서비스: \(config.service)",
            "  프로필 \(config.profiles.count)개, 기본 프로필: \(config.defaultProfile)",
        ]
    }
}
