import Foundation

/// 설정 창 맨 위 한 줄. **지금 보고 있는 값이 무엇인지**를 말한다.
///
/// 이 줄이 필요한 이유는 칸에 값이 들어 있다고 해서 그 값이 저장된 값은 아니기 때문이다.
/// 사내에서 창을 열면 앱이 **지금 시스템 구성을 읽어** 다섯 칸을 채운다 — 화면만 보면
/// 설정이 끝난 것과 구별되지 않는다. 실기에서 그 일이 났다: 칸은 다 차 있고 권한도 다
/// 갖춰졌는데 메뉴는 계속 '초기 설정하기' 였다. 저장을 누른 적이 없었고, 메뉴가 옳았다.
///
/// **그래서 저장 전과 저장 후를 이 줄이 갈라 준다.**
public enum SettingsIntro: Equatable, Sendable {

    /// 저장된 사내 프로필을 보고 있다.
    case saved
    /// 지금 고정 IP 로 연결돼 있고 그 구성을 읽어 칸을 채웠다. **아직 저장 전이다.**
    case unsavedFromCurrentConfiguration
    /// 칸에 값은 있는데 아직 저장 전이다 (사외에서 손으로 넣는 중 등).
    case unsaved
    /// 지금 채울 수 있는 값이 없다 — 사외다.
    case nothingToFillYet
    /// 설정 파일이 있는데 읽지 못했다. 이것은 남은 일이 아니라 고장이라 그대로 알린다.
    case unreadableConfig(String)

    public var text: String {
        switch self {
        case .saved:
            return "저장된 사내 고정 IP 값 · 고치면 다음 전환부터 적용"
        case .unsavedFromCurrentConfiguration:
            return "지금 고정 IP 로 연결됨 · 아직 저장 안 됨 · 저장하면 이 값이 사내 프로필이 됨"
        case .unsaved:
            return "아직 저장 안 됨 · 저장하면 이 값이 사내 프로필이 됨"
        case .nothingToFillYet:
            // **행동을 말한다.** '사내에서 열면' 은 이 사람이 창을 여닫아야 하는 것처럼 읽혔는데,
            // 실제로는 창을 열어 둔 채 사내 Wi-Fi 에 붙기만 하면 그 자리에서 값이 들어온다.
            // 줄바꿈은 뜻 단위로 못박는다 — 맡겨 두면 '지금 / 입력해도 됨' 처럼 한 구가 갈린다.
            return "지금은 고정 IP 구성이 아님 · 사내 Wi-Fi 에 연결하면 값이 자동으로 채워짐"
                + "\n값을 미리 알면 지금 입력해도 됨"
        case .unreadableConfig(let reason):
            return "설정 파일을 읽지 못함 — \(reason)"
        }
    }

    /// - Parameters:
    ///   - hasSavedProfile: 저장된 사내 프로필의 값을 칸에 실었는가.
    ///   - isOfficeConfiguration: 지금 고정 IP 로 돌고 있는가. 칸을 채운 값의 **출처**를 가른다.
    ///   - hasValues: 칸에 무엇이든 들어 있는가.
    ///   - configFailure: 설정 파일을 읽지 못한 사유. 있으면 그것이 먼저다 —
    ///     읽지 못한 파일을 두고 저장 여부를 말하면 둘 다 믿을 수 없게 된다.
    public static func resolve(
        hasSavedProfile: Bool,
        isOfficeConfiguration: Bool,
        hasValues: Bool,
        configFailure: String?
    ) -> SettingsIntro {
        if let configFailure { return .unreadableConfig(configFailure) }
        if hasSavedProfile { return .saved }
        guard hasValues else { return .nothingToFillYet }
        return isOfficeConfiguration ? .unsavedFromCurrentConfiguration : .unsaved
    }
}
