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
    /// 위치 권한을 아직 묻지 않았다 — 승인 창 한 번으로 풀린다
    case locationPermissionNotAsked
    /// 위치 권한이 거부됐다 — Wi-Fi 이름을 읽을 수 없어 자동 전환이 성립하지 않는다
    case locationPermissionDenied
    /// 설정 파일이 아직 없다 — 사내 프로필이 하나도 등록되지 않았다
    case profiles
    /// 파일은 있지만 설치 스크립트가 복사한 예시 그대로다 — 아직 사용자의 값이 아니다
    case exampleProfiles
    /// 값은 다 있는데 사내 Wi-Fi 이름이 하나도 없다 — 자동 전환이 걸릴 자리가 없다
    case wifiNames

    /// 사용자가 **한 번에 처리하는 단위.** 보조 줄을 적을지 말지가 이 단위로 갈린다.
    enum Task: Equatable {
        /// 설치 한 번(`install.sh`)이 함께 놓는 것들
        case install
        /// 승인 한 번으로 풀리는 것 (승인 창 또는 시스템 설정)
        case approve
        /// 설정 창에서 값을 채우는 일
        case fillIn
    }

    var task: Task {
        switch self {
        case .switchingPermission, .savingPermission: return .install
        case .locationPermissionNotAsked, .locationPermissionDenied: return .approve
        case .profiles, .exampleProfiles, .wifiNames: return .fillIn
        }
    }

    /// 이것 하나만 남았을 때 보조 줄에 적을 짧은 명사구. 적을 것이 없으면 nil.
    var shortfall: String? {
        switch self {
        case .switchingPermission: return "전환 권한 미설치"
        case .savingPermission: return "설정 저장 권한 미설치"
        // 메뉴가 자동 전환 아래에 쓰는 말과 같은 낱말을 쓴다 (`SSIDReading.statusText`) —
        // 같은 상태를 두 자리에서 다른 이름으로 부르면 다른 문제로 읽힌다.
        case .locationPermissionNotAsked: return "위치 권한 미승인"
        case .locationPermissionDenied: return "위치 권한 없음"
        case .profiles:
            // 설정 파일이 아예 없는 것은 **머리말이 이미 말한 그 상태**다. 아무것도 시작되지
            // 않았다는 사실을 크기만 줄여 한 번 더 적으면 줄만 늘고 읽을 것은 늘지 않는다.
            return nil
        // '예시 설정 그대로' 라고 적었었다. 그것은 **설치 스크립트 쪽 사정**이지 사용자가 아는
        // 말이 아니다 — 실기에서 이 줄을 보고도 무엇을 해야 하는지 읽히지 않았다(값은 다 차
        // 있었고, 저장을 누른 적이 없었다). 남은 일을 그대로 적는다.
        case .exampleProfiles: return "아직 저장 안 됨"
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
/// **위치 권한은 필수다** (2026-07-28 오너 판단 — 자세한 경위는 `docs/plan/001` "뒤집힌 결정").
/// 없어도 수동 전환은 되니 선택으로 뒀었는데, 그러면 사용자가 사내 Wi-Fi 이름을 **손으로**
/// 넣어야 한다. 이 도구의 목적이 "사람이 아무것도 누르지 않는 것" 인데 시작부터 그 반대를 시킨다.
///
/// **여기 넣지 않은 것 둘.**
///   - **알림 권한**: 없어도 전환은 그대로 된다. 알림을 뜻해서 끈 사용자에게 '초기 설정하기'
///     가 영영 떠 있으면 그것은 잘못된 신호다 — 그쪽은 보조 줄과 조치 항목이 안내한다
///   - **관리자 계정 여부**: 설치로 해결되지 않는다. 손쓸 수 없는 것을 할 일로 적어 두면
///     그 계정에서는 머리말이 영영 내려가지 않는다
///
/// **필수라는 것이 기능을 잠근다는 뜻은 아니다.** 위치 권한이 없어도 메뉴에서 프로필을 골라
/// 전환하는 것은 그대로 된다 (`StatusModel` 의 `canSwitch`). 체크리스트에 남아 계속 안내할 뿐이다 —
/// 자동 전환을 포기하고 손으로 쓰겠다는 사용자의 길까지 막을 이유는 없다.
public enum SetupChecklist {

    /// 아직 남아 있는 것. 비어 있으면 초기 설정이 끝났다.
    ///
    /// 순서는 사용자가 하는 순서다 — 권한을 먼저 놓아야 값을 저장할 수 있다.
    /// 설정 파일이 **깨진** 경우(`unusable`)는 세지 않는다. 그것은 남은 일이 아니라 고장이고,
    /// 고장은 고장이라고 말해야 한다 (머리말은 '설정 파일 오류' 로 남는다).
    public static func gaps(_ input: StatusInput) -> [SetupGap] {
        var gaps: [SetupGap] = []

        // 스크립트만 있고 무암호 규칙이 없으면 겉보기에는 설치된 상태다 — 전환할 때마다 암호를 물어 실패한다.
        // **자동 전환도 같은 판정을 본다** (`SwitchingPermission`) — 한쪽만 시도하고 실패를 쌓지 않게.
        if !input.switching.isSatisfied {
            gaps.append(.switchingPermission)
        }
        if !input.saveConfigInstalled {
            gaps.append(.savingPermission)
        }

        // Wi-Fi 이름이 읽히고 있다면 권한은 있는 것이다 — **관측된 사실이 아직 정해지지 않은
        // 상태 값을 이긴다** (`PermissionReport.location` 과 같은 규칙. `CLLocationManager` 는
        // 만든 직후 '아직 묻지 않음' 을 돌려준다).
        switch input.location {
        case .granted:
            break
        case .notDetermined:
            if input.ssid?.name == nil { gaps.append(.locationPermissionNotAsked) }
        case .denied:
            gaps.append(.locationPermissionDenied)
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

    /// 사외에서 값만 남았을 때 적는 한 줄. **남은 일이 아니라 곧 일어날 일이다.**
    /// 설정 창 머리말(`SettingsIntro.nothingToFillYet`)과 같은 낱말을 쓴다.
    public static let valuesArriveInOffice = "사내 Wi-Fi 에 연결하면 채워짐"

    /// 머리말('초기 설정하기') 아래에 붙일 보조 줄.
    ///
    /// **남은 일이 한 가지일 때만 그 일을 적는다.** 여럿이면 그 줄은 목록이 되는데,
    /// 메뉴는 문서가 아니다 — 무엇무엇이 남았는지는 눌러서 여는 설정 창이 전부 들고 있다.
    ///
    /// **일의 갈래는 셋이다** — 설치 한 번(`install.sh`)으로 놓는 것 · 승인 한 번으로 푸는 것 ·
    /// 설정 창에서 채우는 것. 갈래 하나만 남았을 때 적고, 둘 이상 남았으면 적지 않는다.
    /// 설치 쪽은 한 번에 둘이 함께 놓이므로 둘 다 빠졌으면 '권한 미설치' 한 줄로 묶는다.
    ///
    /// - Parameter interface: 지금 IPv4 구성. **사외에서 설치한 사람** 때문에 필요하다.
    ///   그 사람에게는 사내 IP·서브넷·라우터를 알 길이 없어 값을 채울 방법이 지금 없다.
    ///   그런데 사내에 가면 대개 이미 고정 IP 로 구성돼 있어 앱이 그 값을 그대로 읽어 넣는다 —
    ///   **지금 할 일이 사실 없다.** 그 사실을 적지 않으면 '초기 설정하기' 가 며칠씩 떠 있는 동안
    ///   무엇을 빠뜨렸는지 찾게 된다. 구성을 읽지 못했으면(nil) 짐작하지 않고 원래대로 적는다.
    public static func shortfall(_ gaps: [SetupGap], interface: InterfaceInfo?) -> String? {
        let tasks = Set(gaps.map(\.task))
        guard tasks.count == 1, let task = tasks.first else { return nil }

        switch task {
        case .install:
            guard let only = gaps.first else { return nil }
            return gaps.count == 1 ? only.shortfall : "권한 미설치"
        case .approve:
            // 이 갈래 안의 갈림은 서로 배타적이라 남는 것이 언제나 하나다 (묻지 않음 ↔ 거부됨).
            return gaps.first?.shortfall
        case .fillIn:
            guard let interface, !interface.isManual else { return gaps.first?.shortfall }
            return valuesArriveInOffice
        }
    }
}
