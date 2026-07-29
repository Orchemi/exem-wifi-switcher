import Foundation

/// 설정 창에서 시스템 설정으로 **보냈다가 돌아오는 길**.
///
/// 이 앱은 `.accessory` 라 Dock 아이콘이 없다. 설정 창이 다른 앱 창 뒤로 밀리면 되돌릴 손잡이가
/// 없어, 사용자에게는 창이 꺼진 것과 구별되지 않는다. [로그인 항목 열기…] · [허용 요청] 처럼
/// **우리가 직접 시스템 설정으로 보낸 길**이 그 자리를 만든다 — 보냈으면 데려와야 한다.
///
/// 그렇다고 창을 늘 위에 띄우면(`level = .floating`) 시스템 설정을 가려 버린다. 실기에서 거부당한
/// 동작이 그것이다. 덮이는 것은 정상이고, **덮은 것이 사라졌을 때 다시 보이는 것**이 필요했다.
///
/// 그래서 되돌리는 조건을 값으로 못박는다. 어려운 것은 창을 앞으로 내는 일이 아니라
/// **언제 내지 않을지**다 — 조건 하나를 빠뜨리면 사용자가 다른 앱에서 일하는 중에 창이 튀어나온다.
///
///   - **우리가 보낸 길에만** 응답한다. 사용자가 직접 열어 둔 시스템 설정은 우리 일이 아니다
///   - **한 번만** 돌아온다. 표식이 남아 있으면 다음 번 남의 시스템 설정에 얹혀 튀어나온다
///   - 설정 창이 **아직 열려 있을 때만** 돌아온다. 닫은 창을 되살리지 않는다
///
/// 신호로 종료(`didTerminateApplicationNotification`)를 쓰는 이유는 실측이다 —
/// 시스템 설정은 **창을 닫으면 프로세스가 끝난다**(macOS 26.5). 비활성화를 신호로 삼으면
/// 사용자가 다른 앱으로 잠깐 옮기기만 해도 창이 앞으로 튀어나온다.
public struct SystemSettingsTrip: Equatable, Sendable {

    /// 시스템 설정의 번들 식별자. 창을 닫으면 이 앱이 끝나고, 그것이 우리가 기다리는 신호다.
    public static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    /// 우리가 보낸 사람이 아직 돌아오지 않았다.
    private var isAway = false

    public init() {}

    /// 시스템 설정을 우리가 열었다.
    public mutating func didOpenSystemSettings() {
        isAway = true
    }

    /// 설정 창이 닫혔다 — 돌아올 자리가 없어졌으므로 길도 접는다.
    public mutating func didCloseWindow() {
        isAway = false
    }

    /// 앱 하나가 끝났다. 설정 창을 다시 앞으로 낼 자리인가.
    ///
    /// 우리가 보낸 시스템 설정이 끝났다면 **되돌리든 아니든 길은 그 자리에서 접는다** —
    /// 다녀온 것은 다녀온 것이고, 표식을 남겨 두면 나중에 엉뚱한 시점에 튀어나온다.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: 끝난 앱의 번들 식별자. 알 수 없으면 `nil` 이고, 그때는 신호가 아니다.
    ///   - isWindowOpen: 설정 창이 아직 살아 있는가.
    public mutating func shouldBringWindowBack(terminatedApp bundleIdentifier: String?, isWindowOpen: Bool) -> Bool {
        guard bundleIdentifier == Self.systemSettingsBundleIdentifier, isAway else { return false }
        isAway = false
        return isWindowOpen
    }
}
