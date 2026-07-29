import Foundation

/// 메뉴에 올라가는 무리 하나. 순서는 이 열거형의 차례 그대로다.
///
/// 메뉴는 네 무리로 읽힌다 — **지금 상태 · 고를 프로필 · 자동 전환 · 앱.**
/// 무리마다 구분선을 넣어 어디까지가 한 이야기인지 눈으로 끊는다.
public enum MenuSection: Equatable, Sendable, CaseIterable {
    /// 머리말 한 줄(과 딸린 보조 줄). **체크마크가 이미 말하고 있으면 서지 않는다.**
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
            case .status:
                return !isToldByCheckmark(model)
            case .app:
                // 상태와 무관하게 낼 항목이 있다 (설정 · 종료).
                //
                // 초기 설정 중에는 머리말과 '설정…' 이 같은 창을 연다. 그래도 '설정…' 을 빼지
                // 않는 것은 **⌘, 가 그 창으로 가는 유일한 열쇠**이고, 머리말이 눌리는 자리라는
                // 사실은 눌러 봐야 아는 것이기 때문이다. 같은 목적지가 둘인 값은 한 줄이지만,
                // 첫 실행에서 들어갈 문을 못 찾는 값은 그보다 크다.
                // (머리말이 사라지는 정상 상태에서는 이 줄이 설정 창으로 가는 유일한 자리다)
                return true
            case .profiles:
                return !model.profiles.isEmpty
            case .autoSwitch:
                return autoSwitchCanAct(profiles: model.profiles, setupGaps: model.setupGaps)
            }
        }
    }

    /// 머리말이 **프로필의 체크 표시가 이미 말한 것**을 되풀이하는가.
    ///
    /// `사내 고정 IP 적용 중` 은 정상 상태에서 세 번째로 같은 말을 하는 줄이다 —
    /// 메뉴바 아이콘이 말하고, 그 아래 프로필에 체크가 서 있고, 그리고 이 줄이 있었다
    /// (2026-07-28 오너 판단: "아래 체크와 겹치는 것 같은데 굳이 있어야 하나?").
    /// 보조 줄에 세운 기준(정상 상태에는 줄을 두지 않는다)을 머리말에도 그대로 적용한다.
    ///
    /// **넷을 다 만족해야 지운다.** 하나라도 어긋나면 머리말은 체크마크가 말할 수 없는 것을
    /// 말하고 있는 것이라 남긴다.
    ///   - 남은 일이 없다 — 있으면 머리말은 '초기 설정하기' 이고, 그 줄은 **설정 창으로 가는 문**이다
    ///     (그 상태에서는 프로필이 아예 없어 체크마크도 없다)
    ///   - 딸린 줄이 없다 — 전환 실패 사유 · 설정 파일 오류 · 아직 저장 안 됨은 체크마크가 못 말한다
    ///   - 체크가 실제로 서 있다 — 어느 프로필도 서 있지 않으면(`프로필 없음 — DHCP`) 말할 사람이 없다
    ///   - 전환 중이 아니다 — **진행 중이라는 사실은 체크마크로 말할 수 없다**
    ///
    /// 마지막 조건은 `canSwitch` 로 대신 보지 않는다. 그 값에는 **자동 전환이 켜져 있어 잠갔다**는
    /// 다른 사유가 섞여 있어(2026-07-29), 그것을 보면 아무 문제 없는 정상 상태에서 머리말이 되살아난다 —
    /// 지워 두기로 한 그 줄이다. 묻는 것이 '진행 중인가' 이므로 그대로 묻는다(`isSwitching`).
    private static func isToldByCheckmark(_ model: StatusModel) -> Bool {
        model.setupGaps.isEmpty
            && model.detail == nil
            && model.activeProfileName != nil
            && !model.isSwitching
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
    ///
    /// **켜져 있는지는 보지 않는다** — 꺼 둔 사용자에게도 켤 스위치는 있어야 한다.
    /// 이 판정을 `StatusModel` 도 쓴다: 자동 전환이 손을 쓸 수 없는 상태라면 프로필을 잠글 이유도
    /// 없기 때문이다(잠그면 스위치가 감춰진 채로 아무것도 못 하는 자리가 생긴다).
    static func autoSwitchCanAct(profiles: [NetworkProfile], setupGaps: [SetupGap]) -> Bool {
        guard !profiles.isEmpty else { return false }
        return !setupGaps.contains { $0.blocksAutoSwitch }
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
