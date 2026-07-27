import Foundation
import Testing
@testable import WifiSwitcherCore

@Suite("프로필 이름 화이트리스트")
struct ProfileNameTests {

    @Test("허용되는 이름", arguments: [
        "office", "dhcp", "home", "a", "A", "Z0", "x-y_z", "office2", "abcdefghijklmnop",
    ])
    func acceptsValidNames(_ name: String) {
        #expect(ProfileName.isValid(name))
    }

    // 이 목록이 곧 "권한 상승을 막는 경계"다. 하나라도 통과하면 root 스크립트에 그대로 전달된다.
    @Test("막아야 하는 이름", arguments: [
        "office; rm -rf /",
        "office;id",
        "office && id",
        "office|id",
        "$(id)",
        "`id`",
        "${HOME}",
        "../../etc/passwd",
        "/etc/sudoers",
        "./apply",
        "office name",
        "office\nrm -rf /",
        "office\trm",
        "office*",
        "office?",
        "office~",
        "-office",
        "_office",
        ".office",
        "office.json",
        "",
        "abcdefghijklmnopq",   // 17자
        "사무실",
        "office>out",
        "office<in",
        "*",
        "office\u{0000}",
    ])
    func rejectsDangerousNames(_ name: String) {
        #expect(!ProfileName.isValid(name))
    }

    @Test("길이 상한은 sudoers 패턴 개수와 같다")
    func maxLengthIsSixteen() {
        #expect(ProfileName.maxLength == 16)
        #expect(ProfileName.isValid(String(repeating: "a", count: 16)))
        #expect(!ProfileName.isValid(String(repeating: "a", count: 17)))
    }
}

@Suite("프로필 검증")
struct NetworkProfileValidationTests {

    @Test("정상적인 고정 IP 프로필")
    func acceptsValidManualProfile() {
        let profile = NetworkProfile(
            name: "office",
            mode: .manual,
            ip: "192.0.2.10",
            subnet: "255.255.255.0",
            router: "192.0.2.1",
            dns: ["192.0.2.53"],
            ssids: ["EXAMPLE-AP"]
        )
        #expect(profile.validate().isEmpty)
        #expect(profile.manualConfiguration != nil)
    }

    @Test("정상적인 DHCP 프로필")
    func acceptsValidDHCPProfile() {
        let profile = NetworkProfile(name: "auto", mode: .dhcp)
        #expect(profile.validate().isEmpty)
        #expect(profile.manualConfiguration == nil)
    }

    @Test("이름이 규칙에 어긋나면 잡는다")
    func rejectsBadName() {
        let profile = NetworkProfile(name: "of fice", mode: .dhcp)
        #expect(profile.validate().contains(.invalidProfileName("of fice")))
    }

    @Test("고정 IP 인데 값이 빠지면 잡는다")
    func rejectsMissingManualFields() {
        let profile = NetworkProfile(name: "office", mode: .manual, ip: "192.0.2.10")
        #expect(profile.validate().contains(.missingField(profile: "office", field: "subnet")))
    }

    @Test("DHCP 인데 고정 IP 값이 남아 있으면 잡는다")
    func rejectsUnexpectedFieldsOnDHCP() {
        let profile = NetworkProfile(name: "auto", mode: .dhcp, ip: "192.0.2.10")
        #expect(profile.validate().contains(.unexpectedField(profile: "auto", field: "ip")))
    }

    @Test("주소 형식이 틀리면 잡는다", arguments: ["192.0.2.300", "192.0.2", "192.0.2.10;id", ""])
    func rejectsMalformedIP(_ ip: String) {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: ip, subnet: "255.255.255.0", router: "192.0.2.1"
        )
        #expect(profile.validate().contains(.invalidAddress(profile: "office", field: "ip", value: ip)))
    }

    @Test("서브넷 마스크가 연속이 아니면 잡는다")
    func rejectsNonContiguousMask() {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.0.255", router: "192.0.2.1"
        )
        #expect(profile.validate().contains(.invalidAddress(profile: "office", field: "subnet", value: "255.255.0.255")))
    }

    @Test("라우터가 대역 밖이면 잡는다")
    func rejectsRouterOutsideSubnet() {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0", router: "198.51.100.1"
        )
        #expect(profile.validate().contains(.routerOutsideSubnet(profile: "office")))
    }

    @Test("좁은 마스크에서는 인접해 보여도 대역 밖이다")
    func rejectsRouterOutsideNarrowSubnet() {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.128", router: "192.0.2.200"
        )
        #expect(profile.validate().contains(.routerOutsideSubnet(profile: "office")))
    }

    @Test("네트워크·브로드캐스트 주소는 호스트로 못 쓴다", arguments: ["192.0.2.0", "192.0.2.255"])
    func rejectsReservedAddresses(_ ip: String) {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: ip, subnet: "255.255.255.0", router: "192.0.2.1"
        )
        #expect(profile.validate().contains(.reservedAddress(profile: "office", field: "ip", value: ip)))
    }

    @Test("IP 와 라우터가 같으면 잡는다")
    func rejectsIdenticalIPAndRouter() {
        let profile = NetworkProfile(
            name: "office", mode: .manual, ip: "192.0.2.1", subnet: "255.255.255.0", router: "192.0.2.1"
        )
        #expect(profile.validate().contains(.duplicateAddress(profile: "office")))
    }

    @Test("DNS 주소 형식·개수·중복을 본다")
    func validatesDNSServers() {
        let malformed = NetworkProfile(name: "auto", mode: .dhcp, dns: ["192.0.2.53", "nope"])
        #expect(malformed.validate().contains(.invalidAddress(profile: "auto", field: "dns", value: "nope")))

        let duplicated = NetworkProfile(name: "auto", mode: .dhcp, dns: ["192.0.2.53", "192.0.2.53"])
        #expect(duplicated.validate().contains(.duplicateDNSServer(profile: "auto", value: "192.0.2.53")))

        let tooMany = NetworkProfile(
            name: "auto", mode: .dhcp, dns: (1...9).map { "192.0.2.\($0)" }
        )
        #expect(tooMany.validate().contains(.tooManyDNSServers(profile: "auto", count: 9)))
    }

    @Test("SSID 는 32바이트 이하의 제어문자 없는 값이어야 한다")
    func validatesSSIDs() {
        #expect(!NetworkProfile(name: "a", mode: .dhcp, ssids: [""]).validate().isEmpty)
        #expect(!NetworkProfile(name: "a", mode: .dhcp, ssids: [String(repeating: "x", count: 33)]).validate().isEmpty)
        #expect(!NetworkProfile(name: "a", mode: .dhcp, ssids: ["bad\u{0000}ssid"]).validate().isEmpty)
        #expect(!NetworkProfile(name: "a", mode: .dhcp, ssids: ["dup", "dup"]).validate().isEmpty)
        #expect(NetworkProfile(name: "a", mode: .dhcp, ssids: ["사내-와이파이"]).validate().isEmpty)
    }
}

@Suite("프로필 JSON 해석")
struct NetworkProfileDecodingTests {

    private func decode(_ json: String) throws -> NetworkProfile {
        try JSONDecoder().decode(NetworkProfile.self, from: Data(json.utf8))
    }

    @Test("mode 를 생략하면 고정 IP 값의 유무로 추론한다")
    func infersMode() throws {
        let manual = try decode("""
        { "name": "office", "ip": "192.0.2.10", "subnet": "255.255.255.0", "router": "192.0.2.1" }
        """)
        #expect(manual.mode == .manual)

        let dhcp = try decode("""
        { "name": "auto" }
        """)
        #expect(dhcp.mode == .dhcp)
        #expect(dhcp.dns.isEmpty)
        #expect(dhcp.ssids.isEmpty)
    }

    @Test("모르는 키는 무시한다 (예시 파일의 설명문이 들어와도 깨지지 않는다)")
    func ignoresUnknownKeys() throws {
        let profile = try decode("""
        { "name": "auto", "mode": "dhcp", "_note": "설명" }
        """)
        #expect(profile.name == "auto")
    }

    @Test("이름이 없으면 해석에 실패한다")
    func requiresName() {
        #expect(throws: (any Error).self) {
            try decode("""
            { "mode": "dhcp" }
            """)
        }
    }
}
