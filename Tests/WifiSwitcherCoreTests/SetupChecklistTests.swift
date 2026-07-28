import Foundation
import Testing
@testable import WifiSwitcherCore

/// **초기 설정이 끝났는가**를 하나로 묶어 본다.
///
/// 앱에게는 권한과 값이 다른 일이지만 사용자에게는 하나다 — 아직 내가 할 일이 남았는가.
/// 그래서 메뉴 머리말도 하나다: **하나라도 빠지면 '초기 설정하기', 전부 갖춰지면 사라진다.**
///
/// 이 스위트가 지키는 것은 그 등가 관계다. 문구 하나하나를 박제하기보다,
/// **어떤 것이 빠졌을 때 머리말이 할 일로 바뀌는가**를 갈래마다 확인한다.
@Suite("초기 설정 판정")
struct SetupChecklistTests {

    // MARK: - 픽스처

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    /// 값은 다 맞는데 **사내 Wi-Fi 이름만 없는** 프로필. 자동 전환이 걸릴 자리가 없다.
    private static let officeWithoutWiFiNames = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")

    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")
    private static let configWithoutWiFiNames = AppConfig(
        profiles: [officeWithoutWiFiNames, auto], defaultProfile: "auto"
    )
    private static let officeInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )

    /// 초기 설정이 **끝난** 상태. 여기서 하나씩 빼면서 본다.
    private func input(
        config: ConfigStatus = .ready(SetupChecklistTests.config),
        helperInstalled: Bool = true,
        sudoersInstalled: Bool = true,
        saveConfigInstalled: Bool = true,
        action: ActionState = .idle,
        notifications: NotificationPermission = .allowed
    ) -> StatusInput {
        StatusInput(
            config: config,
            interface: SetupChecklistTests.officeInfo,
            helperInstalled: helperInstalled,
            sudoersInstalled: sudoersInstalled,
            saveConfigInstalled: saveConfigInstalled,
            action: action,
            notifications: notifications
        )
    }

    private static let setupHeadline = "초기 설정하기"

    // MARK: - 하나라도 빠지면 할 일이 남은 것이다

    @Test("권한만 없어도 — 값이 다 있어도 — 초기 설정하기")
    func permissionAloneKeepsSetupOpen() {
        // 전환 권한: 스크립트가 없는 경우와 무암호 규칙만 없는 경우 둘 다.
        // 규칙이 없으면 겉보기에는 설치된 상태인데 전환할 때마다 암호를 물어 실패한다.
        for missing in [
            input(helperInstalled: false),
            input(sudoersInstalled: false),
        ] {
            let model = StatusModel.resolve(missing)
            #expect(model.setupGaps == [.switchingPermission])
            #expect(model.headline == Self.setupHeadline)
            #expect(model.detail == "전환 권한 미설치")
            // 눌러도 실패할 것을 눌리게 두지 않는다.
            #expect(!model.canSwitch)
        }

        // 설정 저장 권한. 전환은 되지만 값을 저장할 수 없어 설정을 끝낼 수 없다.
        let noSave = StatusModel.resolve(input(saveConfigInstalled: false))
        #expect(noSave.setupGaps == [.savingPermission])
        #expect(noSave.headline == Self.setupHeadline)
        #expect(noSave.detail == "설정 저장 권한 미설치")
        // 저장이 막힌 것과 전환이 막힌 것은 별개다 — 전환은 그대로 열어 둔다.
        #expect(noSave.canSwitch)
    }

    @Test("사내 Wi-Fi 이름만 비어도 초기 설정하기")
    func missingWiFiNamesKeepsSetupOpen() {
        let model = StatusModel.resolve(input(config: .ready(Self.configWithoutWiFiNames)))
        #expect(model.setupGaps == [.wifiNames])
        #expect(model.headline == Self.setupHeadline)
        #expect(model.detail == "사내 Wi-Fi 이름 미설정")
        // 자동 전환이 걸릴 자리가 없을 뿐, 손으로 고르는 것은 아무 문제가 없다.
        #expect(model.canSwitch)
        #expect(model.profiles.count == 2)
    }

    @Test("설정 파일이 없거나 예시 그대로면 초기 설정하기")
    func unsetConfigKeepsSetupOpen() {
        let missing = StatusModel.resolve(input(config: .missing(path: "/tmp/none.json")))
        #expect(missing.setupGaps == [.profiles])
        #expect(missing.headline == Self.setupHeadline)
        #expect(!missing.canSwitch)

        let pristine = StatusModel.resolve(input(config: .pristineExample(path: "/tmp/x.json")))
        #expect(pristine.setupGaps == [.exampleProfiles])
        #expect(pristine.headline == Self.setupHeadline)
        #expect(!pristine.canSwitch)
    }

    // MARK: - 전부 갖춰지면 사라진다

    @Test("전부 갖춰지면 머리말이 지금 상태를 말한다")
    func completeSetupShowsState() {
        let model = StatusModel.resolve(input())
        #expect(model.setupGaps.isEmpty)
        #expect(model.headline == "사내 고정 IP 적용 중")
        #expect(model.headline != Self.setupHeadline)
        #expect(model.icon == .manual)
        #expect(model.canSwitch)
        #expect(!model.needsSetup)
        // 딸린 줄도 할 일이 아니라 지금 값이다.
        #expect(model.detail == "192.0.2.10 → 192.0.2.1")
    }

    @Test("위치·알림 권한은 초기 설정에 넣지 않는다")
    func optionalPermissionsAreNotSetup() {
        // 알림을 뜻해서 거부한 사용자에게 '초기 설정하기' 가 영영 떠 있으면 잘못된 신호다.
        // 없어도 수동 전환은 되므로, 그쪽은 보조 줄과 조치 항목이 안내한다.
        let denied = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo,
            autoSwitchEnabled: true, ssid: .permissionDenied,
            autoSwitchHold: .locationPermissionDenied, notifications: .denied
        ))
        #expect(denied.setupGaps.isEmpty)
        #expect(denied.headline != Self.setupHeadline)
        #expect(denied.needsLocationPermission)
        #expect(denied.needsNotificationPermission)
    }

    // MARK: - 초기 설정이 아닌 것 — 문제 상황

    @Test("고장은 초기 설정이 아니라 고장이라고 말한다")
    func problemsKeepTheirOwnHeadline() {
        // 설정 파일이 깨진 것은 남은 일이 아니라 고장이다. 권한까지 함께 빠져 있어도 그렇다.
        let broken = StatusModel.resolve(input(
            config: .unusable(path: "/tmp/x.json", reason: "기본 프로필 'x' 이 프로필 목록에 없습니다"),
            helperInstalled: false
        ))
        #expect(broken.headline == "설정 파일 오류")
        #expect(broken.detail?.contains("기본 프로필") == true)

        // 전환 실패도 마찬가지다 — 지금 벌어진 일이 먼저다.
        let failed = StatusModel.resolve(input(
            helperInstalled: false,
            action: .failed(profile: "office", message: "sudo: a password is required")
        ))
        #expect(failed.headline.contains("전환 실패"))
        // 남은 일이 사라진 것은 아니므로 판정에는 그대로 남는다.
        #expect(failed.setupGaps == [.switchingPermission])
    }

    // MARK: - 창을 자동으로 여는 것은 이보다 좁다

    @Test("권한만 빠진 상태로 설정 창을 자동으로 띄우지 않는다")
    func doesNotReopenWindowForPermissionsAlone() {
        // 로그인할 때마다 창이 튀어나오면 그것은 안내가 아니라 소음이다.
        // 자동으로 여는 것은 아직 사용자의 값이 하나도 없을 때뿐이다.
        #expect(!StatusModel.resolve(input(helperInstalled: false)).needsSetup)
        #expect(!StatusModel.resolve(input(saveConfigInstalled: false)).needsSetup)
        #expect(!StatusModel.resolve(input(config: .ready(Self.configWithoutWiFiNames))).needsSetup)

        #expect(StatusModel.resolve(input(config: .missing(path: "/tmp/none.json"))).needsSetup)
        #expect(StatusModel.resolve(input(config: .pristineExample(path: "/tmp/x.json"))).needsSetup)
    }

    // MARK: - 보조 줄

    @Test("보조 줄은 남은 일이 한 가지일 때만 그 일을 적는다")
    func shortfallOnlyWhenSingleTask() {
        // 권한 둘은 설치 한 번이 함께 놓는다 — 사용자에게는 한 가지 일이라 한 줄로 적는다.
        let noPermissions = StatusModel.resolve(input(helperInstalled: false, saveConfigInstalled: false))
        #expect(noPermissions.setupGaps == [.switchingPermission, .savingPermission])
        #expect(noPermissions.detail == "권한 미설치")

        // 권한도 값도 남았으면 그 줄은 목록이 된다. 메뉴는 문서가 아니므로 적지 않는다 —
        // 무엇무엇이 남았는지는 눌러서 여는 설정 창이 들고 있다.
        let nothingDone = StatusModel.resolve(input(
            config: .missing(path: "/tmp/none.json"), helperInstalled: false
        ))
        #expect(nothingDone.setupGaps.count == 2)
        #expect(nothingDone.detail == nil)

        // 설정 파일이 아예 없는 것은 머리말이 이미 말한 그 상태다. 되풀이하지 않는다.
        #expect(StatusModel.resolve(input(config: .missing(path: "/tmp/none.json"))).detail == nil)
    }

    @Test("앱이 짓는 보조 줄은 짧은 명사구다")
    func shortfallsAreShortNounPhrases() {
        // 우리가 고를 수 있는 문구까지 상한에 붙여 쓰면 그게 곧 메뉴 폭이 된다.
        let authoredLimit = 22
        let gaps: [[SetupGap]] = [
            [.switchingPermission], [.savingPermission], [.profiles],
            [.exampleProfiles], [.wifiNames], [.switchingPermission, .savingPermission],
        ]
        for combination in gaps {
            guard let line = SetupChecklist.shortfall(combination) else { continue }
            #expect(line.count <= authoredLimit, "너무 길다(\(line.count)자): \(line)")
            #expect(!line.hasSuffix("."), "마침표로 끝난다: \(line)")
            for ending in ["습니다", "하세요", "됩니다", "합니다", "입니다"] {
                #expect(!line.contains(ending), "문장이다: \(line)")
            }
        }
    }

    // MARK: - 설정 창과 같은 답을 낸다

    /// 메뉴와 설정 창이 같은 시스템을 두고 다른 답을 내면 어느 쪽을 믿어야 할지 알 수 없다.
    /// **판정 기준이 갈리지 않았는지**를 조합마다 대조한다 (`ProfileNameLayerParityTests` 와 같은 뜻).
    @Test("메뉴의 초기 설정 판정과 설정 창의 권한 표가 갈리지 않는다")
    func agreesWithPermissionReport() {
        for apply in [true, false] {
            for sudoers in [true, false] {
                for saveConfig in [true, false] {
                    let gaps = SetupChecklist.gaps(input(
                        helperInstalled: apply,
                        sudoersInstalled: sudoers,
                        saveConfigInstalled: saveConfig
                    ))
                    let report = PermissionReport.resolve(PermissionInput(
                        applyInstalled: apply,
                        sudoersInstalled: sudoers,
                        saveConfigInstalled: saveConfig,
                        // 관리자 계정 여부는 초기 설정 판정에 넣지 않는다 — 설치로 해결되지 않는 것을
                        // 할 일로 적어 두면 그 계정에서는 머리말이 영영 내려가지 않는다.
                        isAdministrator: true,
                        installerAvailable: true,
                        location: .granted,
                        wifiNameVisible: true,
                        notifications: .allowed
                    ))
                    #expect(
                        gaps.contains(.switchingPermission) == (report.item(.switching).state != .satisfied),
                        "전환 권한 판정이 갈렸다 (apply: \(apply), sudoers: \(sudoers))"
                    )
                    #expect(
                        gaps.contains(.savingPermission) == (report.item(.saving).state != .satisfied),
                        "저장 권한 판정이 갈렸다 (saveConfig: \(saveConfig))"
                    )
                }
            }
        }
    }
}
