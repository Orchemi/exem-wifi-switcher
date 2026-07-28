import Foundation
import Testing
@testable import WifiSwitcherCore

/// **메뉴에 어떤 무리가 서는가.**
///
/// 규율 하나로 정리된다 — 항목을 하나도 내지 않는 무리는 서지 않는다.
/// 자리표시자('등록된 프로필 없음')로 빈 자리를 채우지 않고, 켜고 끌 수 없는 스위치도 두지 않는다.
///
/// 구분선은 그리는 쪽이 **무리와 무리 사이에만** 넣는다. 그래서 여기서 무리 목록이 성하면
/// 구분선이 연달아 붙거나 맨 위·맨 아래에 남는 일은 원리적으로 생기지 않는다 —
/// 이 스위트가 지키는 것이 그 전제다.
@Suite("메뉴 무리 구성")
struct MenuLayoutTests {

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")
    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")
    private static let officeWithoutWiFiNames = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", label: "사내 고정 IP"
    )
    private static let configWithoutWiFiNames = AppConfig(
        profiles: [officeWithoutWiFiNames, auto], defaultProfile: "auto"
    )
    private static let officeInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )

    private func sections(
        config: ConfigStatus = .ready(MenuLayoutTests.config),
        helperInstalled: Bool = true,
        sudoersInstalled: Bool = true,
        saveConfigInstalled: Bool = true,
        location: LocationAuthorizationState = .granted,
        ssid: SSIDReading = .connected("OFFICE-WIFI"),
        action: ActionState = .idle
    ) -> [MenuSection] {
        MenuLayout.sections(StatusModel.resolve(StatusInput(
            config: config,
            interface: MenuLayoutTests.officeInfo,
            helperInstalled: helperInstalled,
            sudoersInstalled: sudoersInstalled,
            saveConfigInstalled: saveConfigInstalled,
            location: location,
            action: action,
            autoSwitchEnabled: true,
            ssid: ssid
        )))
    }

    // MARK: - 빈 무리는 서지 않는다

    @Test("프로필이 없으면 그 자리에 아무 항목도 없다")
    func noPlaceholderForEmptyProfiles() {
        // 머리말이 이미 '초기 설정하기' 라고 말한 상태를 바로 아래에서 되풀이하지 않는다.
        for config in [
            ConfigStatus.missing(path: "/tmp/none.json"),
            .pristineExample(path: "/tmp/x.json"),
            .unusable(path: "/tmp/x.json", reason: "기본 프로필 'x' 이 프로필 목록에 없습니다"),
        ] {
            #expect(!sections(config: config).contains(.profiles), "\(config) 에서 빈 프로필 무리가 섰다")
        }
        #expect(sections().contains(.profiles))
    }

    @Test("초기 설정이 끝나지 않았으면 진입점 하나만 남는다")
    func setupStateOffersOneDoor() {
        // 사용자가 할 일이 하나뿐인데 선택지를 여럿 보여줄 이유가 없다.
        // 자동 전환은 전환할 대상도 판단할 근거도 없어 아무 일도 하지 못한다.
        #expect(sections(config: .missing(path: "/tmp/none.json")) == [.status, .app])
        #expect(sections(config: .pristineExample(path: "/tmp/x.json")) == [.status, .app])
    }

    @Test("전환 권한·위치 권한이 없으면 자동 전환 무리를 세우지 않는다")
    func hidesAutoSwitchWhenItCannotAct() {
        // 값은 다 있어 프로필은 보여주되, 켜고 끌 수 없는 스위치는 두지 않는다.
        for blocked in [
            sections(helperInstalled: false),
            sections(sudoersInstalled: false),
            // 권한이 막혀 있으면 이름도 읽히지 않는다 — 관측을 맞춰 넣는다.
            sections(location: .denied, ssid: .permissionDenied),
            sections(location: .notDetermined, ssid: .permissionNotDetermined),
        ] {
            #expect(blocked == [.status, .profiles, .app])
        }

        // 반대로 **이름이 읽히고 있다면** 권한은 있는 것이다(`SetupChecklist`). 그때는
        // 자동 전환이 그대로 돌고 있으므로 스위치를 감추지 않는다.
        #expect(sections(location: .notDetermined) == MenuSection.allCases)
    }

    @Test("지금 일하고 있는 자동 전환의 스위치는 감추지 않는다")
    func keepsAutoSwitchWhenItStillRuns() {
        // **감추는 쪽이 더 위험한 경우가 있다.** 이 둘은 초기 설정이 안 끝난 상태이지만
        // 자동 전환은 그대로 돌고 있다 — 스위치를 감추면 끄지도 못하는 채로 계속 돈다.
        //
        // 저장 권한 없음: 값을 저장만 못 할 뿐 전환은 그대로 된다.
        let savingOnly = sections(saveConfigInstalled: false)
        #expect(savingOnly == [.status, .profiles, .autoSwitch, .app])

        // 사내 Wi-Fi 이름 없음: 어디서도 사내로 걸리지 않을 뿐, 기본 프로필은 계속 적용된다.
        let namesOnly = sections(config: .ready(Self.configWithoutWiFiNames))
        #expect(namesOnly == [.status, .profiles, .autoSwitch, .app])
    }

    // MARK: - 정상·문제 상태

    @Test("전부 갖춰지면 네 무리가 다 선다")
    func fullMenuWhenReady() {
        #expect(sections() == MenuSection.allCases)
    }

    @Test("전환 중·전환 실패는 무리를 줄이지 않는다")
    func actionStatesKeepTheMenu() {
        // 지금 벌어진 일이 머리말을 차지할 뿐, 고를 것도 끌 것도 그대로 있다.
        #expect(sections(action: .switching(profile: "office")) == MenuSection.allCases)
        #expect(sections(action: .failed(profile: "office", message: "sudo: a password is required"))
            == MenuSection.allCases)
    }

    // MARK: - 구분선이 성립하는 전제

    @Test("무리 목록은 비지 않고, 겹치지 않고, 차례를 지킨다")
    func sectionListIsWellFormed() {
        let states: [[MenuSection]] = [
            sections(),
            sections(config: .missing(path: "/tmp/none.json")),
            sections(config: .pristineExample(path: "/tmp/x.json")),
            sections(config: .unusable(path: "/tmp/x.json", reason: "깨짐")),
            sections(helperInstalled: false),
            sections(sudoersInstalled: false),
            sections(saveConfigInstalled: false),
            sections(location: .denied, ssid: .permissionDenied),
            sections(location: .notDetermined, ssid: .permissionNotDetermined),
            sections(config: .ready(Self.configWithoutWiFiNames)),
            sections(action: .switching(profile: "office")),
            sections(action: .failed(profile: "office", message: "실패")),
        ]
        for sections in states {
            // 구분선은 무리 **사이에만** 들어간다. 무리가 하나도 없으면 메뉴가 통째로 비고,
            // 같은 무리가 두 번 서면 그 사이에 아무것도 나누지 않는 선이 생긴다.
            #expect(!sections.isEmpty)
            #expect(Set(sections).count == sections.count, "무리가 겹친다: \(sections)")
            #expect(sections == MenuSection.allCases.filter(sections.contains), "차례가 어긋났다: \(sections)")
            // 어떤 상태에서도 들어갈 문과 나가는 문은 남는다.
            #expect(sections.first == .status)
            #expect(sections.last == .app)
        }
    }
}
