import Foundation
import Testing
@testable import WifiSwitcherCore

/// 설정 창의 **사내 Wi-Fi 이름 칸**이 어떤 값을 들고 어떤 상태여야 하는가.
///
/// 이 판정이 코어에 있는 이유는 창이 이것을 **한 번만** 하면 안 되기 때문이다.
/// 창을 여는 순간에는 위치 권한을 아직 안 받아 이름을 못 읽는 일이 흔하고(첫 실행),
/// 이름은 그 뒤에 들어온다. 그때 다시 판정하지 않으면 자동으로 채워진 이름이
/// **편집 가능한 채로** 남는다 — 실기에서 나온 고장이 그것이다.
@Suite("사내 Wi-Fi 이름 칸")
struct SSIDFieldStateTests {

    private static let office = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )
    /// IP 는 수동, 라우터만 DHCP 가 알려준 구성. 이것도 고정 IP 구성이다.
    private static let officeWithDHCPRouter = InterfaceInfo(configMethod: .manualWithDHCPRouter)
    private static let outside = InterfaceInfo(
        configMethod: .dhcp,
        ip: IPv4Address("198.51.100.24"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("198.51.100.1")
    )

    // MARK: - 사내에서는 잠근다

    @Test("사내에서 이름이 채워지면 잠근다")
    func locksWhenNameIsFilledInOffice() {
        let state = SSIDFieldState.resolve(
            typed: "OFFICE-WIFI", reading: .connected("OFFICE-WIFI"), interface: Self.office
        )
        #expect(state.name == "OFFICE-WIFI")
        #expect(state.isEditable == false)
    }

    /// **실기에서 나온 고장.** 창을 열 때는 위치 권한이 없어 칸이 비어 있었고,
    /// 권한을 허용한 뒤에야 이름이 들어왔다. 그 순간에도 잠겨야 한다.
    @Test("권한을 늦게 허용해 이름이 그제야 들어와도 잠근다")
    func locksWhenNameArrivesAfterPermission() {
        let state = SSIDFieldState.resolve(
            typed: "", reading: .connected("OFFICE-WIFI"), interface: Self.office
        )
        #expect(state.name == "OFFICE-WIFI")
        #expect(state.isEditable == false)
    }

    /// 설정을 저장한 적이 있든 없든 판정은 같다 — 판정에 설정이 아예 들어오지 않는다.
    /// (저장된 이름이 칸에 실려 온 경우와 지금 읽어 넣은 경우, 둘 다 잠긴다)
    @Test("설정 저장 여부는 판정에 들어오지 않는다")
    func ignoresWhetherConfigWasSaved() {
        let saved = SSIDFieldState.resolve(
            typed: "OFFICE-WIFI", reading: .permissionDenied, interface: Self.office
        )
        let firstRun = SSIDFieldState.resolve(
            typed: "", reading: .connected("OFFICE-WIFI"), interface: Self.office
        )
        #expect(saved.isEditable == false)
        #expect(firstRun.isEditable == false)
    }

    @Test("라우터만 DHCP 인 고정 IP 구성도 사내로 본다")
    func treatsManualWithDHCPRouterAsOffice() {
        let state = SSIDFieldState.resolve(
            typed: "OFFICE-WIFI", reading: .connected("OFFICE-WIFI"), interface: Self.officeWithDHCPRouter
        )
        #expect(state.isEditable == false)
    }

    // MARK: - 잠그면 안 되는 자리

    /// 사외에서는 사내 이름을 넣을 자리가 여기뿐이고, 잘못 넣은 이름을 고칠 자리도 여기뿐이다.
    @Test("사외(DHCP)에서는 이름이 채워져 있어도 편집할 수 있다")
    func keepsFieldEditableOutsideOffice() {
        let state = SSIDFieldState.resolve(
            typed: "OFFICE-WIFI", reading: .connected("CAFE"), interface: Self.outside
        )
        #expect(state.isEditable)
    }

    /// 위치 권한을 끝내 거부하면 이름을 읽을 수 없다. 그 칸까지 잠그면 넣을 방법이 사라진다.
    @Test("사내인데 이름을 못 읽어 칸이 비면 편집할 수 있다")
    func keepsFieldEditableWhenNameIsUnknownInOffice() {
        let state = SSIDFieldState.resolve(typed: "", reading: .permissionDenied, interface: Self.office)
        #expect(state.name.isEmpty)
        #expect(state.isEditable)
    }

    @Test("공백만 적힌 칸은 빈 칸과 같다")
    func treatsWhitespaceAsEmpty() {
        let state = SSIDFieldState.resolve(typed: "   ", reading: .wifiOff, interface: Self.office)
        #expect(state.isEditable)
    }

    /// 아직 구성을 읽지 못한 상태에서 잠그면, 읽기에 실패한 기기에서 칸이 영영 잠긴다.
    @Test("구성을 읽지 못했으면 잠그지 않는다")
    func keepsFieldEditableWhenConfigurationIsUnknown() {
        let state = SSIDFieldState.resolve(typed: "OFFICE-WIFI", reading: .connected("OFFICE-WIFI"), interface: nil)
        #expect(state.isEditable)
    }

    // MARK: - 읽은 이름을 넣는 자리

    /// 사외에서 읽은 이름은 **집·카페 이름**이다. 사내 프로필의 이름 칸에 넣으면
    /// 그 자리에서 사내 고정 IP 가 걸린다.
    @Test("사외에서 읽은 이름은 빈 칸에도 넣지 않는다")
    func neverAdoptsNameReadOutsideOffice() {
        let state = SSIDFieldState.resolve(typed: "", reading: .connected("CAFE"), interface: Self.outside)
        #expect(state.name.isEmpty)
        #expect(state.isEditable)
    }

    @Test("이미 적힌 이름은 읽은 이름으로 덮지 않는다")
    func keepsWhatIsAlreadyInTheField() {
        let state = SSIDFieldState.resolve(
            typed: "OFFICE-GUEST", reading: .connected("OFFICE-WIFI"), interface: Self.office
        )
        #expect(state.name == "OFFICE-GUEST")
    }
}
