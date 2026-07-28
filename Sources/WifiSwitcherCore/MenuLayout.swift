import Foundation

/// 메뉴에 올라가는 무리 하나. 순서는 이 열거형의 차례 그대로다.
///
/// 메뉴는 네 무리로 읽힌다 — **지금 상태 · 고를 프로필 · 자동 전환 · 앱.**
/// 무리마다 구분선을 넣어 어디까지가 한 이야기인지 눈으로 끊는다.
public enum MenuSection: Equatable, Sendable, CaseIterable {
    /// 머리말 한 줄(과 딸린 보조 줄). 언제나 있다 — 상태를 말하지 않는 순간이 없다.
    case status
    /// 눌러서 고르는 프로필 목록. **없으면 무리째 사라진다.**
    case profiles
    /// 자동 전환 토글과 그 아래 딸린 것들(상태 줄 · 지금 다시 시도 · 권한 열기).
    case autoSwitch
    /// 설정·종료. 언제나 있다.
    case app
}

/// **메뉴에 어떤 무리가 서는가.**
///
/// 빈 무리를 자리표시자로 채우지 않는다. 예전에는 프로필이 없을 때 그 자리에
/// '등록된 프로필 없음' 을 세워 뒀는데, 머리말이 이미 '초기 설정하기' 라고 말한 상태를
/// 바로 아래에서 한 번 더 말하는 것이었다 — 줄만 늘고 읽을 것은 늘지 않는다.
/// **할 수 있는 것이 없으면 자리도 차지하지 않는다.**
///
/// **구분선은 여기서 정하지 않는다.** 그리는 쪽이 무리와 무리 **사이에만** 넣으면
/// 구분선이 연달아 붙거나 맨 위·맨 아래에 남는 일이 원리적으로 생기지 않는다.
/// 그래서 이 목록의 규율은 하나다 — **항목을 하나도 내지 않는 무리는 여기 들어오지 않는다.**
public enum MenuLayout {

    public static func sections(_ model: StatusModel) -> [MenuSection] {
        MenuSection.allCases.filter { section in
            switch section {
            case .status, .app:
                // 이 둘은 상태와 무관하게 낼 항목이 있다 (머리말 · 설정/종료).
                //
                // 초기 설정 중에는 머리말과 '설정…' 이 같은 창을 연다. 그래도 '설정…' 을 빼지
                // 않는 것은 **⌘, 가 그 창으로 가는 유일한 열쇠**이고, 머리말이 눌리는 자리라는
                // 사실은 눌러 봐야 아는 것이기 때문이다. 같은 목적지가 둘인 값은 한 줄이지만,
                // 첫 실행에서 들어갈 문을 못 찾는 값은 그보다 크다.
                return true
            case .profiles:
                return !model.profiles.isEmpty
            case .autoSwitch:
                return autoSwitchCanAct(model)
            }
        }
    }

    /// 자동 전환이 **지금 손을 쓸 수 있는 상태인가.**
    ///
    /// 켜고 끌 수 없는 스위치를 메뉴에 두지 않는다 — 초기 설정이 끝나지 않았으면 전환할
    /// 대상도, 판단할 근거(Wi-Fi 이름)도 없어서 토글은 아무 일도 하지 않는다.
    ///
    /// **다만 반대쪽이 더 위험하다: 지금 일하고 있는 기능의 스위치를 감추는 것.**
    /// 그래서 "초기 설정이 안 끝났으면 무조건 숨김" 이 아니라, **그 항목이 자동 전환을
    /// 실제로 막는지**로 가른다.
    ///   - 막는다: 전환 권한(전환 자체가 안 된다) · 위치 권한(Wi-Fi 이름을 못 읽는다) ·
    ///     설정 값 없음(고를 프로필이 없다)
    ///   - 막지 않는다: **설정 저장 권한**(저장만 못 할 뿐 전환은 그대로 돈다) ·
    ///     **사내 Wi-Fi 이름 없음**(어디서도 사내로 걸리지 않을 뿐, 기본 프로필은 계속 적용된다)
    ///
    /// 뒤의 둘에서 토글을 감추면 자동 전환이 **끄지도 못하는 채로 계속 돈다.**
    private static func autoSwitchCanAct(_ model: StatusModel) -> Bool {
        guard !model.profiles.isEmpty else { return false }
        return !model.setupGaps.contains { $0.blocksAutoSwitch }
    }
}

extension SetupGap {

    /// 이 항목이 빠져 있으면 자동 전환이 아예 성립하지 않는가.
    var blocksAutoSwitch: Bool {
        switch self {
        case .switchingPermission, .locationPermissionNotAsked, .locationPermissionDenied,
             .profiles, .exampleProfiles:
            return true
        case .savingPermission, .wifiNames:
            return false
        }
    }
}
