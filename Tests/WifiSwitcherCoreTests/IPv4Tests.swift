import Testing
@testable import WifiSwitcherCore

// 이 파일을 포함한 모든 테스트는 문서용 예약 대역만 쓴다 (RFC 5737: 192.0.2.0/24,
// 198.51.100.0/24, 203.0.113.0/24). 실제 네트워크 값은 어떤 형태로도 넣지 않는다.

@Suite("IPv4 주소 파싱")
struct IPv4AddressTests {

    @Test("정상 표기를 받아들인다", arguments: [
        "192.0.2.1", "198.51.100.254", "203.0.113.7", "0.0.0.0", "255.255.255.255", "203.0.113.254",
    ])
    func acceptsValidAddresses(_ text: String) {
        #expect(IPv4Address(text) != nil)
    }

    @Test("잘못된 표기를 거부한다", arguments: [
        "192.0.2",            // 옥텟 부족
        "192.0.2.1.5",        // 옥텟 초과
        "192.0.2.256",        // 범위 초과
        "192.0.2.01",         // 앞자리 0 — 8진수로 해석될 여지
        "192.0.02.1",
        "192.0.2.-1",
        " 192.0.2.1",
        "192.0.2.1 ",
        "192.0.2.1;id",
        "192.0.2.1$(id)",
        "192.0.2.x",
        "0xC0.0.2.1",
        "192.0.2.1\n",
        "",
        "localhost",
        "::1",
    ])
    func rejectsInvalidAddresses(_ text: String) {
        #expect(IPv4Address(text) == nil)
    }

    @Test("32비트 값으로 옳게 환산한다")
    func convertsToRawValue() {
        #expect(IPv4Address("0.0.0.1")?.rawValue == 1)
        #expect(IPv4Address("192.0.2.1")?.rawValue == 3_221_225_985)
        #expect(IPv4Address("255.255.255.255")?.rawValue == 4_294_967_295)
    }

    @Test("32비트 값에서 표기를 복원한다")
    func restoresDescription() {
        #expect(IPv4Address(rawValue: 3_221_225_985).description == "192.0.2.1")
        #expect(IPv4Address(rawValue: 0).description == "0.0.0.0")
    }
}

@Suite("서브넷 마스크")
struct SubnetMaskTests {

    @Test("1비트가 연속인 마스크만 받아들인다", arguments: [
        "255.255.255.0", "255.255.255.128", "255.255.0.0", "255.0.0.0", "255.255.254.0", "128.0.0.0",
    ])
    func acceptsContiguousMasks(_ text: String) {
        #expect(SubnetMask(text) != nil)
    }

    @Test("연속이 아니거나 의미 없는 마스크를 거부한다", arguments: [
        "255.255.0.255",      // 중간이 끊겼다
        "255.0.255.0",
        "0.0.0.0",            // /0 — 구성 값으로 무의미
        "255.255.255.255",    // /32 — 호스트 단독
        "192.0.2.1",
        "255.255.255",
    ])
    func rejectsInvalidMasks(_ text: String) {
        #expect(SubnetMask(text) == nil)
    }

    @Test("접두 길이를 센다")
    func computesPrefixLength() {
        #expect(SubnetMask("255.255.255.0")?.prefixLength == 24)
        #expect(SubnetMask("255.255.0.0")?.prefixLength == 16)
        #expect(SubnetMask("255.255.255.128")?.prefixLength == 25)
    }

    @Test("같은 대역인지 판정한다")
    func detectsSameSubnet() {
        let mask = SubnetMask("255.255.255.0")!
        let host = IPv4Address("192.0.2.10")!
        #expect(mask.isSameSubnet(host, IPv4Address("192.0.2.1")!))
        #expect(!mask.isSameSubnet(host, IPv4Address("192.0.3.1")!))
        #expect(!mask.isSameSubnet(host, IPv4Address("198.51.100.1")!))

        // 옥텟 경계와 어긋나는 마스크에서도 옳게 갈라야 한다 (/25 는 .0~.127 과 .128~.255).
        let narrow = SubnetMask("255.255.255.128")!
        #expect(narrow.isSameSubnet(host, IPv4Address("192.0.2.100")!))
        #expect(!narrow.isSameSubnet(host, IPv4Address("192.0.2.200")!))
    }

    @Test("네트워크·브로드캐스트 주소를 호스트로 쓰지 못하게 한다")
    func rejectsReservedHostAddresses() {
        let mask = SubnetMask("255.255.255.0")!
        #expect(mask.networkAddress(of: IPv4Address("192.0.2.10")!).description == "192.0.2.0")
        #expect(mask.broadcastAddress(of: IPv4Address("192.0.2.10")!).description == "192.0.2.255")
        #expect(!mask.isAssignableHost(IPv4Address("192.0.2.0")!))
        #expect(!mask.isAssignableHost(IPv4Address("192.0.2.255")!))
        #expect(mask.isAssignableHost(IPv4Address("192.0.2.10")!))
    }
}
