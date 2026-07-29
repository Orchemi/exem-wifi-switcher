import Foundation

/// **전환이 가능한 상태인가를 판정하는 한 자리.**
///
/// 이 판정을 쓰는 곳이 넷이다 — 초기 설정 체크리스트(`SetupChecklist`) · 메뉴의 전환 가능 여부
/// (`StatusModel.canSwitch`) · 설정 창의 권한 표(`PermissionReport.switching`) · 자동 전환
/// (`AutoSwitchPolicy`). 넷이 각자 판단하면 같은 시스템을 두고 다른 답을 내는 날이 온다.
///
/// **실제로 왔다** (2026-07-29). 자동 전환만 `apply` 파일 유무를 보고 있어서, 무암호 규칙만 빠진
/// 상태(macOS 업데이트가 `/etc/sudoers.d/` 를 정리하는 일이 있다)에서 **메뉴는 전환을 잠그는데
/// 자동 전환은 시도했다.** `sudo -n` 이 그 자리에서 거부하므로 결과는 뻔했고, 실패 다섯 번과
/// 그만큼의 알림을 쌓은 뒤에야 멈췄다. 하지 않아도 될 시도였다.
public struct SwitchingPermission: Equatable, Sendable {

    /// 권한 스크립트(`apply`)가 실행 가능한 상태로 놓여 있는가.
    public var applyInstalled: Bool
    /// 무암호 sudoers 규칙이 놓여 있는가.
    public var sudoersInstalled: Bool

    public init(applyInstalled: Bool, sudoersInstalled: Bool) {
        self.applyInstalled = applyInstalled
        self.sudoersInstalled = sudoersInstalled
    }

    /// 전환을 걸어도 되는 상태인가.
    ///
    /// **둘 다 있어야 한다.** 스크립트만 있으면 겉보기에는 설치된 상태지만, 앱은 `sudo -n`
    /// (암호를 묻지 않는 sudo)으로 부르므로 규칙이 없으면 실행 자체가 거부된다.
    ///
    /// **`save-config` 는 여기 들어오지 않는다.** 그것이 없으면 값을 저장할 수 없을 뿐,
    /// 이미 저장된 설정으로 전환하는 것은 그대로 된다 — 전환의 조건이 아니다
    /// (`SetupGap.savingPermission` 이 따로 안내한다).
    public var isSatisfied: Bool { applyInstalled && sudoersInstalled }

    /// 둘 다 갖춰진 상태. 전환 권한이 시나리오의 관심사가 아닐 때 쓴다.
    public static let satisfied = SwitchingPermission(applyInstalled: true, sudoersInstalled: true)
}
