import Testing
@testable import WifiSwitcherCore

// networksetup 출력 픽스처. 주소는 문서용 예약 대역, MAC 은 문서용 대역(RFC 7042, 00:00:5E:00:53:xx).

@Suite("networksetup -getinfo 파싱")
struct InterfaceInfoParsingTests {

    @Test("고정 IP 구성")
    func parsesManualConfiguration() throws {
        let output = """
        Manual Configuration
        IP address: 192.0.2.10
        Subnet mask: 255.255.255.0
        Router: 192.0.2.1
        Wi-Fi ID: 00:00:5e:00:53:01
        IPv6: Automatic
        IPv6 IP address: none
        IPv6 Router: none

        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .manual)
        #expect(info.isManual)
        #expect(info.hasAddress)
        #expect(info.ip?.description == "192.0.2.10")
        #expect(info.subnet?.description == "255.255.255.0")
        #expect(info.router?.description == "192.0.2.1")
        // 값에 콜론이 들어가는 줄도 첫 콜론에서만 잘라야 한다.
        #expect(info.hardwareAddress == "00:00:5e:00:53:01")
    }

    @Test("DHCP 구성 — IPv6 줄이 IPv4 값을 덮지 않는다")
    func parsesDHCPConfiguration() throws {
        let output = """
        DHCP Configuration
        IP address: 198.51.100.42
        Subnet mask: 255.255.255.0
        Router: 198.51.100.1
        Client ID:
        IPv6: Automatic
        IPv6 IP address: 2001:db8::1
        IPv6 Router: 2001:db8::1
        Wi-Fi ID: 00:00:5e:00:53:02
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .dhcp)
        #expect(!info.isManual)
        #expect(info.ip?.description == "198.51.100.42")
        #expect(info.router?.description == "198.51.100.1")
    }

    @Test("주소를 못 받은 상태 — IP 줄이 아예 없다")
    func parsesDisconnectedDHCP() throws {
        let output = """
        DHCP Configuration
        Client ID:
        IPv6: Automatic
        IPv6 IP address: none
        IPv6 Router: none
        Wi-Fi ID: 00:00:5e:00:53:03
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .dhcp)
        #expect(!info.hasAddress)
        #expect(info.ip == nil)
        #expect(info.subnet == nil)
        #expect(info.router == nil)
    }

    @Test("주소를 못 받은 상태 — 값이 none")
    func parsesManualWithNoneValues() throws {
        let output = """
        Manual Configuration
        IP address: none
        Subnet mask: none
        Router: none
        Wi-Fi ID: 00:00:5e:00:53:04
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .manual)
        #expect(info.isManual)
        #expect(!info.hasAddress)
        #expect(info.ip == nil)
    }

    @Test("수동 IP + DHCP 라우터")
    func parsesManualWithDHCPRouter() throws {
        let output = """
        Manually Using DHCP Router Configuration
        IP address: 192.0.2.20
        Subnet mask: 255.255.255.0
        Router: 192.0.2.1
        Wi-Fi ID: 00:00:5e:00:53:05
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .manualWithDHCPRouter)
        #expect(info.isManual)
    }

    @Test("유선 인터페이스의 Ethernet Address 줄")
    func parsesEthernetAddress() throws {
        let output = """
        BOOTP Configuration
        IP address: 203.0.113.5
        Subnet mask: 255.255.255.0
        Router: 203.0.113.1
        Ethernet Address: 00:00:5e:00:53:06
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.configMethod == .bootp)
        #expect(!info.isManual)
        #expect(info.hardwareAddress == "00:00:5e:00:53:06")
    }

    @Test("모르는 구성 방식은 원문을 보존한다")
    func keepsUnknownConfigurationMethod() throws {
        let info = try NetworkSetupOutput.parseInterfaceInfo("Off Configuration\nWi-Fi ID: 00:00:5e:00:53:07")
        #expect(info.configMethod == .unknown("Off Configuration"))
    }

    @Test("서비스 이름이 틀리면 오류로 알린다")
    func throwsOnCommandError() {
        #expect(throws: NetworkSetupOutput.ParseError.self) {
            try NetworkSetupOutput.parseInterfaceInfo("** Error: The parameters were not valid.")
        }
    }

    @Test("구성 방식 줄이 없으면 오류로 알린다", arguments: ["", "   \n\n", "IP address: 192.0.2.10"])
    func throwsOnUnrecognizedOutput(_ output: String) {
        #expect(throws: NetworkSetupOutput.ParseError.unrecognizedOutput) {
            try NetworkSetupOutput.parseInterfaceInfo(output)
        }
    }

    @Test("형식이 깨진 주소는 값을 채우지 않는다")
    func ignoresMalformedAddresses() throws {
        let output = """
        Manual Configuration
        IP address: 192.0.2.999
        Subnet mask: 255.255.0.255
        Router: not-an-ip
        """
        let info = try NetworkSetupOutput.parseInterfaceInfo(output)
        #expect(info.ip == nil)
        #expect(info.subnet == nil)
        #expect(info.router == nil)
    }
}

@Suite("현재 구성과 프로필 대조")
struct InterfaceConformanceTests {

    private let manualProfile = NetworkProfile(
        name: "office",
        mode: .manual,
        ip: "192.0.2.10",
        subnet: "255.255.255.0",
        router: "192.0.2.1"
    )
    private let dhcpProfile = NetworkProfile(name: "auto", mode: .dhcp)

    @Test("값이 모두 같아야 일치로 본다")
    func matchesIdenticalManualConfiguration() throws {
        let info = try NetworkSetupOutput.parseInterfaceInfo("""
        Manual Configuration
        IP address: 192.0.2.10
        Subnet mask: 255.255.255.0
        Router: 192.0.2.1
        """)
        #expect(info.conforms(to: manualProfile))
        #expect(!info.conforms(to: dhcpProfile))
    }

    @Test("IP 가 하나라도 다르면 불일치")
    func detectsDifferentAddress() throws {
        let info = try NetworkSetupOutput.parseInterfaceInfo("""
        Manual Configuration
        IP address: 192.0.2.11
        Subnet mask: 255.255.255.0
        Router: 192.0.2.1
        """)
        #expect(!info.conforms(to: manualProfile))
    }

    @Test("같은 값이어도 구성 방식이 다르면 불일치")
    func detectsDifferentMethod() throws {
        let info = try NetworkSetupOutput.parseInterfaceInfo("""
        DHCP Configuration
        IP address: 192.0.2.10
        Subnet mask: 255.255.255.0
        Router: 192.0.2.1
        """)
        #expect(!info.conforms(to: manualProfile))
        #expect(info.conforms(to: dhcpProfile))
    }
}

@Suite("DNS·서비스 목록 파싱")
struct DNSAndServiceListTests {

    @Test("설정된 DNS 가 없을 때")
    func parsesEmptyDNS() {
        #expect(NetworkSetupOutput.parseDNSServers("There aren't any DNS Servers set on Wi-Fi.") == [])
    }

    @Test("DNS 목록")
    func parsesDNSList() {
        let output = """
        192.0.2.53
        198.51.100.53
        """
        #expect(NetworkSetupOutput.parseDNSServers(output) == ["192.0.2.53", "198.51.100.53"])
    }

    @Test("네트워크 서비스 목록 — 안내 문구와 비활성 표시를 걷어낸다")
    func parsesNetworkServices() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        *Thunderbolt Bridge
        USB 10/100/1000 LAN
        """
        #expect(NetworkSetupOutput.parseNetworkServices(output) == ["Wi-Fi", "Thunderbolt Bridge", "USB 10/100/1000 LAN"])
    }
}
