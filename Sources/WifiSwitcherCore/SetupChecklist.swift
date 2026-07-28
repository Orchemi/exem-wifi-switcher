import Foundation

/// 초기 설정이 아직 끝나지 않았다고 말하는 것 하나.
///
/// 앱 안에서 이것들은 서로 다른 자리에서 판정된다 — 권한은 설치된 파일이, 값은 설정 파일이.
/// 그런데 **사용자가 겪는 것은 하나다**: 아직 내가 할 일이 남았는가. 그래서 한자리에 모은다.
public enum SetupGap: Equatable, Sendable {
    /// 전환 권한이 없다 — `apply` 스크립트나 무암호 규칙이 빠져 전환 자체가 되지 않는다
    case switchingPermission
    /// 설정 저장 권한이 없다 — `save-config` 가 빠져 값을 저장할 수 없다
    case savingPermission
    /// 설정 파일이 아직 없다 — 사내 프로필이 하나도 등록되지 않았다
    case profiles
    /// 파일은 있지만 설치 스크립트가 복사한 예시 그대로다 — 아직 사용자의 값이 아니다
    case exampleProfiles
    /// 값은 다 있는데 사내 Wi-Fi 이름이 하나도 없다 — 자동 전환이 걸릴 자리가 없다
    case wifiNames

    /// 권한 쪽인가. 권한은 설치 한 번이 함께 놓고, 값은 설정 창에서 채운다 —
    /// 사용자가 하는 일이 갈리는 자리다.
    var isPermission: Bool {
        switch self {
        case .switchingPermission, .savingPermission: return true
        case .profiles, .exampleProfiles, .wifiNames: return false
        }
    }

    /// 이것 하나만 남았을 때 보조 줄에 적을 짧은 명사구. 적을 것이 없으면 nil.
    var shortfall: String? {
        switch self {
        case .switchingPermission: return "전환 권한 미설치"
        case .savingPermission: return "설정 저장 권한 미설치"
        case .profiles:
            // 설정 파일이 아예 없는 것은 **머리말이 이미 말한 그 상태**다. 아무것도 시작되지
            // 않았다는 사실을 크기만 줄여 한 번 더 적으면 줄만 늘고 읽을 것은 늘지 않는다.
            return nil
        case .exampleProfiles: return "예시 설정 그대로"
        case .wifiNames: return "사내 Wi-Fi 이름 미설정"
        }
    }
}

/// **초기 설정이 끝났는가를 판정하는 한 자리.**
///
/// 권한이 없어서 안 되는 것과 값이 없어서 안 되는 것은 앱에게는 다른 일이지만,
/// 사용자에게는 똑같이 "아직 설정이 안 끝난 것"이다. 그래서 머리말도 하나로 묶는다 —
/// **하나라도 남아 있으면 '초기 설정하기', 전부 갖춰지면 사라진다.**
///
/// 판정 기준은 설정 창의 권한 표(`PermissionReport`)와 같아야 한다. 두 화면이 같은 시스템을
/// 두고 다른 답을 내면 어느 쪽을 믿어야 할지 알 수 없다 (`SetupChecklistTests` 가 조합마다 대조한다).
///
/// **여기 넣지 않은 것 둘.**
///   - **위치·알림 권한**: 없어도 수동 전환은 된다. 알림을 뜻해서 끈 사용자에게 '초기 설정하기'
///     가 영영 떠 있으면 그것은 잘못된 신호다 — 그쪽은 보조 줄과 조치 항목이 안내한다
///   - **관리자 계정 여부**: 설치로 해결되지 않는다. 손쓸 수 없는 것을 할 일로 적어 두면
///     그 계정에서는 머리말이 영영 내려가지 않는다
public enum SetupChecklist {

    /// 아직 남아 있는 것. 비어 있으면 초기 설정이 끝났다.
    ///
    /// 순서는 사용자가 하는 순서다 — 권한을 먼저 놓아야 값을 저장할 수 있다.
    /// 설정 파일이 **깨진** 경우(`unusable`)는 세지 않는다. 그것은 남은 일이 아니라 고장이고,
    /// 고장은 고장이라고 말해야 한다 (머리말은 '설정 파일 오류' 로 남는다).
    public static func gaps(_ input: StatusInput) -> [SetupGap] {
        var gaps: [SetupGap] = []

        // 스크립트만 있고 무암호 규칙이 없으면 겉보기에는 설치된 상태다 — 전환할 때마다 암호를 물어 실패한다.
        if !(input.helperInstalled && input.sudoersInstalled) {
            gaps.append(.switchingPermission)
        }
        if !input.saveConfigInstalled {
            gaps.append(.savingPermission)
        }

        switch input.config {
        case .missing:
            gaps.append(.profiles)
        case .pristineExample:
            gaps.append(.exampleProfiles)
        case .unusable:
            break
        case .ready(let config):
            // 어느 프로필에도 Wi-Fi 이름이 없으면 판정이 늘 기본 프로필로만 간다 —
            // 값이 다 들어 있어도 자동 전환은 성립하지 않는다.
            if !config.profiles.contains(where: { !$0.ssids.isEmpty }) {
                gaps.append(.wifiNames)
            }
        }
        return gaps
    }

    /// 머리말('초기 설정하기') 아래에 붙일 보조 줄.
    ///
    /// **남은 일이 한 가지일 때만 그 일을 적는다.** 여럿이면 그 줄은 목록이 되는데,
    /// 메뉴는 문서가 아니다 — 무엇무엇이 남았는지는 눌러서 여는 설정 창이 전부 들고 있다.
    ///
    /// 권한 둘은 설치 한 번(`install.sh`)이 함께 놓는다. 앱에게는 두 항목이지만
    /// 사용자에게는 한 가지 일이라, 둘 다 빠졌으면 '권한 미설치' 한 줄로 적는다.
    public static func shortfall(_ gaps: [SetupGap]) -> String? {
        let permissions = gaps.filter(\.isPermission)
        let values = gaps.filter { !$0.isPermission }

        if !permissions.isEmpty && !values.isEmpty { return nil }
        if values.isEmpty {
            guard let only = permissions.first else { return nil }
            return permissions.count == 1 ? only.shortfall : "권한 미설치"
        }
        // 값 쪽 셋은 서로 배타적이다 (파일 없음 · 예시 그대로 · 값은 있는데 Wi-Fi 이름 없음).
        return values.first?.shortfall
    }
}
