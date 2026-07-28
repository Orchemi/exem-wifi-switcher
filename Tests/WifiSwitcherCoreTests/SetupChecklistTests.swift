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

    /// 사외 — DHCP 로 돌고 있다. 사내 값을 여기서는 알 수 없다.
    private static let outsideInfo = InterfaceInfo(
        configMethod: .dhcp,
        ip: IPv4Address("198.51.100.24"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("198.51.100.1")
    )

    /// 초기 설정이 **끝난** 상태. 여기서 하나씩 빼면서 본다.
    private func input(
        config: ConfigStatus = .ready(SetupChecklistTests.config),
        helperInstalled: Bool = true,
        sudoersInstalled: Bool = true,
        saveConfigInstalled: Bool = true,
        location: LocationAuthorizationState = .granted,
        ssid: SSIDReading? = nil,
        action: ActionState = .idle,
        notifications: NotificationPermission = .allowed,
        interface: InterfaceInfo? = SetupChecklistTests.officeInfo
    ) -> StatusInput {
        StatusInput(
            config: config,
            interface: interface,
            helperInstalled: helperInstalled,
            sudoersInstalled: sudoersInstalled,
            saveConfigInstalled: saveConfigInstalled,
            location: location,
            action: action,
            ssid: ssid,
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
        // **끝난 상태에는 딸린 줄이 없다.** 남은 일도 없고 문제도 없으면 적을 것이 없다 —
        // 지금 어느 설정인지는 머리말과 아이콘·체크 표시가 이미 말한다.
        #expect(model.detail == nil)
    }

    @Test("위치 권한이 없으면 — 값이 다 있어도 — 초기 설정하기")
    func locationPermissionIsRequired() {
        // 위치 권한이 없으면 Wi-Fi 이름을 읽지 못하고, 그러면 사용자가 사내 Wi-Fi 이름을
        // **손으로** 넣어야 한다. 이 도구의 목적이 "사람이 아무것도 누르지 않는 것" 인데
        // 시작부터 그 반대를 시키는 셈이라, 선택이 아니라 필수로 둔다 (2026-07-28 오너 판단).
        let denied = StatusModel.resolve(input(location: .denied, ssid: .permissionDenied))
        #expect(denied.setupGaps == [.locationPermissionDenied])
        #expect(denied.headline == Self.setupHeadline)
        #expect(denied.detail == "위치 권한 없음")

        let notAsked = StatusModel.resolve(input(location: .notDetermined, ssid: .permissionNotDetermined))
        #expect(notAsked.setupGaps == [.locationPermissionNotAsked])
        #expect(notAsked.headline == Self.setupHeadline)
        #expect(notAsked.detail == "위치 권한 미승인")
    }

    @Test("필수라고 해서 기능을 잠그지는 않는다")
    func requiredLocationDoesNotLockTheApp() {
        // 자동 전환을 포기하고 손으로 쓰겠다는 사용자의 길까지 막을 이유는 없다.
        // 체크리스트에 남아 계속 안내하되, 프로필은 그대로 누를 수 있어야 한다.
        let denied = StatusModel.resolve(input(location: .denied, ssid: .permissionDenied))
        #expect(denied.canSwitch)
        #expect(denied.profiles.count == 2)
        #expect(denied.activeProfileName == "office")
        // 창을 자동으로 띄우지도 않는다 — 거부한 사람에게 로그인마다 창이 뜨면 그것은 소음이다.
        #expect(!denied.needsSetup)
    }

    @Test("Wi-Fi 이름이 읽히고 있으면 권한은 갖춰진 것으로 본다")
    func wifiNameIsProofOfPermission() {
        // `CLLocationManager` 는 만든 직후 '아직 묻지 않음' 을 돌려준다. 그 값을 그대로 믿으면
        // 이름을 읽고 있는데도 '위치 권한 미승인' 이 뜬다 — 관측된 사실이 상태 값을 이긴다.
        let model = StatusModel.resolve(input(location: .notDetermined, ssid: .connected("OFFICE-WIFI")))
        #expect(model.setupGaps.isEmpty)
        #expect(model.headline != Self.setupHeadline)
    }

    @Test("알림 권한은 여전히 선택이다")
    func notificationPermissionStaysOptional() {
        // 알림을 뜻해서 거부한 사용자에게 '초기 설정하기' 가 영영 떠 있으면 잘못된 신호다.
        // 없어도 전환은 그대로 되므로, 그쪽은 보조 줄과 조치 항목이 안내한다.
        let denied = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo,
            autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .alreadyApplied(profile: "office"), notifications: .denied
        ))
        #expect(denied.setupGaps.isEmpty)
        #expect(denied.headline != Self.setupHeadline)
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

        // 갈래가 다르면 묶이지 않는다. 설치와 승인은 사용자가 하는 일이 서로 다르다.
        let installAndApprove = StatusModel.resolve(input(helperInstalled: false, location: .denied))
        #expect(installAndApprove.setupGaps == [.switchingPermission, .locationPermissionDenied])
        #expect(installAndApprove.detail == nil)

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
            [.locationPermissionNotAsked], [.locationPermissionDenied],
        ]
        for combination in gaps {
            for interface in [Self.officeInfo, Self.outsideInfo, nil] {
                guard let line = SetupChecklist.shortfall(combination, interface: interface) else { continue }
                #expect(line.count <= authoredLimit, "너무 길다(\(line.count)자): \(line)")
                #expect(!line.hasSuffix("."), "마침표로 끝난다: \(line)")
                for ending in ["습니다", "하세요", "됩니다", "합니다", "입니다"] {
                    #expect(!line.contains(ending), "문장이다: \(line)")
                }
            }
        }
    }

    // MARK: - 사외에서 설치한 사람

    /// 집·카페에서 먼저 설치한 동료가 겪는 자리다. 사내 IP·서브넷·라우터를 알 길이 없어
    /// **지금 채울 수 있는 것이 없고**, 사내에 가면 대개 이미 고정 IP 로 구성돼 있어 앱이
    /// 그 값을 읽어 넣는다. 그러니 남은 일을 적을 것이 아니라 **곧 일어날 일**을 적어야 한다.
    @Test("사외에서 값만 남았으면 언제 채워지는지 적는다")
    func tellsWhenValuesWillArriveOutsideOffice() {
        let outside = StatusModel.resolve(input(
            config: .missing(path: "/tmp/none.json"), interface: SetupChecklistTests.outsideInfo
        ))
        #expect(outside.setupGaps == [.profiles])
        #expect(outside.detail == SetupChecklist.valuesArriveInOffice)

        // 예시 그대로인 경우도, Wi-Fi 이름만 없는 경우도 같은 자리다.
        let example = StatusModel.resolve(input(
            config: .pristineExample(path: "/tmp/x.json"), interface: SetupChecklistTests.outsideInfo
        ))
        #expect(example.detail == SetupChecklist.valuesArriveInOffice)

        let noNames = StatusModel.resolve(input(
            config: .ready(SetupChecklistTests.configWithoutWiFiNames),
            interface: SetupChecklistTests.outsideInfo
        ))
        #expect(noNames.detail == SetupChecklist.valuesArriveInOffice)
    }

    /// 사내에서는 값을 채울 수 있다 — 곧 채워진다고 말할 자리가 아니다.
    @Test("사내에서는 그 줄을 적지 않는다")
    func doesNotPromiseAutoFillInsideOffice() {
        #expect(StatusModel.resolve(input(config: .missing(path: "/tmp/none.json"))).detail == nil)
        #expect(
            StatusModel.resolve(input(config: .ready(SetupChecklistTests.configWithoutWiFiNames))).detail
                == "사내 Wi-Fi 이름 미설정"
        )
    }

    /// 구성을 못 읽었으면 어디에 있는지 모른다. 모르는 것을 안다고 말하지 않는다.
    @Test("구성을 읽지 못했으면 짐작하지 않는다")
    func doesNotGuessWhenConfigurationIsUnknown() {
        let unknown = StatusModel.resolve(input(config: .missing(path: "/tmp/none.json"), interface: nil))
        #expect(unknown.detail == nil)
    }

    /// 사외에서도 권한 설치는 지금 할 수 있다. 그것이 남아 있으면 그쪽이 먼저다.
    @Test("권한이 남아 있으면 사외에서도 권한을 먼저 말한다")
    func permissionsComeFirstEvenOutsideOffice() {
        let outsideWithoutPermissions = StatusModel.resolve(input(
            config: .missing(path: "/tmp/none.json"),
            helperInstalled: false,
            sudoersInstalled: false,
            saveConfigInstalled: false,
            interface: SetupChecklistTests.outsideInfo
        ))
        // 갈래가 둘(설치·값)이라 목록이 되지 않게 아무 줄도 적지 않는다 —
        // 곧 채워진다는 말을 여기서 하면 지금 할 수 있는 설치를 미루게 한다.
        #expect(outsideWithoutPermissions.detail == nil)
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

        // 위치 권한도 같은 잣대다 — '아직 묻지 않음' 은 문제로 세지 않지만 갖춰진 것도 아니다.
        // 두 화면이 그 경계를 다르게 그으면 한쪽은 끝났다 하고 한쪽은 남았다고 한다.
        for location in [LocationAuthorizationState.granted, .denied, .notDetermined] {
            for reading in [SSIDReading.connected("OFFICE-WIFI"), .permissionDenied] {
                let gaps = SetupChecklist.gaps(input(location: location, ssid: reading))
                let report = PermissionReport.resolve(PermissionInput(
                    applyInstalled: true,
                    sudoersInstalled: true,
                    saveConfigInstalled: true,
                    isAdministrator: true,
                    installerAvailable: true,
                    location: location,
                    wifiNameVisible: reading.name != nil,
                    notifications: .allowed
                ))
                #expect(
                    gaps.contains(where: { $0.task == .approve })
                        == (report.item(.location).state != .satisfied),
                    "위치 권한 판정이 갈렸다 (\(location), 이름 읽힘: \(reading.name != nil))"
                )
            }
        }
    }
}
