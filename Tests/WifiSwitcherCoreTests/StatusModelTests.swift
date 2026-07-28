import Foundation
import Testing
@testable import WifiSwitcherCore

/// 메뉴바가 보여줄 상태를 만드는 규칙.
///
/// 이 계산에는 시스템 호출이 없다 — 관측값(설정·현재 구성·설치 여부·진행 중 동작)을
/// 넣으면 아이콘·머리말·전환 가능 여부가 결정된다. 그래서 그대로 테스트할 수 있다.
@Suite("메뉴바 상태 판정")
struct StatusModelTests {

    /// **초기 설정을 끝낸** 프로필이다 — 사내 Wi-Fi 이름까지 들어 있다.
    /// 이 이름이 비면 '아직 설정이 안 끝난 상태' 가 되어 머리말이 상태가 아니라 할 일을 말한다
    /// (`SetupChecklistTests` 가 그 갈래를 따로 본다).
    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")
    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")

    private func input(
        config: ConfigStatus = .ready(StatusModelTests.config),
        interface: InterfaceInfo? = nil,
        interfaceError: String? = nil,
        helperInstalled: Bool = true,
        action: ActionState = .idle
    ) -> StatusInput {
        StatusInput(
            config: config,
            interface: interface,
            interfaceError: interfaceError,
            helperInstalled: helperInstalled,
            action: action
        )
    }

    private static let manualInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )
    private static let dhcpInfo = InterfaceInfo(
        configMethod: .dhcp,
        ip: IPv4Address("192.0.2.77"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )

    @Test("현재 구성과 같은 프로필을 현재 상태로 보여준다")
    func showsMatchingProfile() {
        let model = StatusModel.resolve(input(interface: Self.manualInfo))
        #expect(model.icon == .manual)
        #expect(model.headline == "사내 고정 IP 적용 중")
        #expect(model.activeProfileName == "office")
        #expect(model.canSwitch)
        // 표시 이름이 없는 프로필은 이름을 그대로 쓴다.
        #expect(Self.office.displayName == "사내 고정 IP")
        #expect(NetworkProfile(name: "office", mode: .dhcp).displayName == "office")
    }

    @Test("DHCP 프로필과 일치하면 DHCP 아이콘을 쓴다")
    func showsDHCPProfile() {
        let model = StatusModel.resolve(input(interface: Self.dhcpInfo))
        #expect(model.icon == .dhcp)
        #expect(model.activeProfileName == "auto")
    }

    @Test("어떤 프로필과도 다르면 프로필 없음으로 표시한다")
    func reportsUnmanagedConfiguration() {
        let other = InterfaceInfo(
            configMethod: .manual,
            ip: IPv4Address("198.51.100.5"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("198.51.100.1")
        )
        let model = StatusModel.resolve(input(interface: other))
        #expect(model.activeProfileName == nil)
        #expect(model.icon == .manual)
        #expect(model.headline.contains("프로필 없음"))
        #expect(model.canSwitch)
    }

    @Test("설정이 없으면 설정을 먼저 하라고 알린다")
    func requiresSetupWhenConfigMissing() {
        let model = StatusModel.resolve(input(config: .missing(path: "/tmp/none.json"), interface: Self.dhcpInfo))
        #expect(model.icon == .error)
        #expect(model.needsSetup)
        #expect(!model.canSwitch)
        #expect(model.profiles.isEmpty)
        // 이 상태의 머리말은 상태가 아니라 **할 일**이다 — 메뉴에서 그 줄이 곧 설정 창으로
        // 들어가는 문이라, '설정 필요' 라고만 적으면 문이라는 것이 읽히지 않는다.
        #expect(model.headline == "초기 설정하기")
        // 설정 파일이 없다는 것은 머리말이 이미 말한 그 상태다. 딸린 줄을 붙이지 않는다.
        #expect(model.detail == nil)
    }

    @Test("설치 스크립트가 복사한 예시 그대로면 설정이 필요한 것으로 본다")
    func treatsPristineExampleAsUnset() {
        let model = StatusModel.resolve(input(config: .pristineExample(path: "/tmp/config.json"), interface: Self.dhcpInfo))
        #expect(model.needsSetup)
        #expect(!model.canSwitch)
    }

    @Test("설정 파일이 깨졌으면 이유를 그대로 보여준다")
    func surfacesConfigProblem() {
        let model = StatusModel.resolve(
            input(config: .unusable(path: "/tmp/config.json", reason: "기본 프로필 'x' 이 프로필 목록에 없습니다"))
        )
        #expect(model.icon == .error)
        #expect(model.detail?.contains("기본 프로필") == true)
        #expect(!model.canSwitch)
    }

    @Test("권한 스크립트가 없으면 아직 설정이 안 끝난 것으로 본다")
    func reportsMissingHelper() {
        let model = StatusModel.resolve(input(interface: Self.manualInfo, helperInstalled: false))
        #expect(model.icon == .error)
        #expect(!model.canSwitch)
        // 값이 다 있어도 권한이 없으면 사용자에게는 "아직 설정이 안 끝난 것" 이다.
        #expect(model.headline == "초기 설정하기")
        // 머리말은 무엇이 남았는지까지는 말하지 않는다. 그 하나를 딸린 줄이 적는다.
        #expect(model.detail == "전환 권한 미설치")
        // 프로필 목록 자체는 그대로 보여준다 (무엇이 있는지는 알 수 있어야 한다).
        #expect(model.profiles.count == 2)
    }

    @Test("현재 구성을 읽지 못하면 조용히 넘어가지 않는다")
    func reportsUnreadableInterface() {
        let model = StatusModel.resolve(input(interface: nil, interfaceError: "networksetup 이 오류를 반환했습니다"))
        #expect(model.icon == .error)
        #expect(model.detail?.contains("networksetup") == true)
        // 읽지 못한 것과 전환하지 못하는 것은 별개다. 전환은 여전히 시도할 수 있다.
        #expect(model.canSwitch)
    }

    @Test("전환 중에는 진행 중임을 보여주고 다른 전환을 막는다")
    func showsSwitchingState() {
        let model = StatusModel.resolve(input(interface: Self.dhcpInfo, action: .switching(profile: "office")))
        #expect(model.headline.contains("전환 중"))
        #expect(!model.canSwitch)
    }

    @Test("전환에 실패하면 실패와 이유를 남긴다")
    func showsFailure() {
        let model = StatusModel.resolve(
            input(interface: Self.dhcpInfo, action: .failed(profile: "office", message: "sudo: a password is required"))
        )
        #expect(model.icon == .error)
        #expect(model.headline.contains("전환 실패"))
        #expect(model.detail?.contains("password") == true)
        // 실패했다고 다음 시도까지 막지는 않는다.
        #expect(model.canSwitch)
    }

    @Test("진행 중 동작은 관측 상태보다 우선한다")
    func actionTakesPrecedence() {
        let idle = StatusModel.resolve(input(interface: Self.manualInfo))
        let failed = StatusModel.resolve(input(interface: Self.manualInfo, action: .failed(profile: "auto", message: "x")))
        #expect(idle.icon == .manual)
        #expect(failed.icon == .error)
    }
}
