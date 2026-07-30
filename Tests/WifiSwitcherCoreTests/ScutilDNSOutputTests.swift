import Testing
@testable import WifiSwitcherCore

// scutil --dns 출력 픽스처.
// 주소는 전부 문서용 예약 대역(RFC 5737: 192.0.2.x · 198.51.100.x · 203.0.113.x)이다.
// 실기에서 읽은 값은 이 파일에 들어오지 않는다.

/// 사내에서 DHCP 로 붙어 있을 때의 전형적인 모양.
/// 앞 절에 일반 리졸버 하나, 뒤 절(scoped)에 같은 서버의 사본이 있다.
private let dhcpOutput = """
DNS configuration

resolver #1
  search domain[0] : example.
  nameserver[0] : 192.0.2.53
  nameserver[1] : 192.0.2.54
  flags    : Request A records
  reach    : 0x00000002 (Reachable)
  order    : 200000

resolver #2
  domain   : local
  options  : mdns
  timeout  : 5
  flags    : Request A records
  reach    : 0x00000000 (Not Reachable)
  order    : 300000

DNS configuration (for scoped queries)

resolver #1
  nameserver[0] : 192.0.2.53
  nameserver[1] : 192.0.2.54
  if_index : 15 (en0)
  flags    : Scoped, Request A records
  reach    : 0x00000002 (Reachable)
"""

@Suite("scutil --dns 파싱")
struct ScutilDNSOutputTests {

    @Test("일반 리졸버의 서버를 순서대로 읽는다")
    func readsDefaultResolver() {
        #expect(ScutilDNSOutput.activeResolvers(dhcpOutput) == ["192.0.2.53", "192.0.2.54"])
    }

    @Test("같은 서버가 여러 절에 나와도 한 번만 남고 순서는 그대로다")
    func removesDuplicatesKeepingOrder() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 198.51.100.53
          nameserver[1] : 192.0.2.53
          nameserver[2] : 198.51.100.53
          flags    : Request A records

        DNS configuration (for scoped queries)

        resolver #1
          nameserver[0] : 192.0.2.53
          if_index : 15 (en0)
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["198.51.100.53", "192.0.2.53"])
    }

    @Test("IPv6 리졸버는 읽지 않는다 — 설정 스키마가 IPv4 만 받는다")
    func skipsIPv6() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 2001:db8::53
          nameserver[1] : 192.0.2.53
          flags    : Request A records, Request AAAA records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }

    @Test("루프백은 제안하지 않는다 — 프로필에 박히면 사내에서 이름 해석이 끊긴다")
    func skipsLoopback() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 127.0.0.1
          nameserver[1] : 127.53.0.1
          nameserver[2] : 192.0.2.53
          flags    : Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }

    @Test("루프백뿐이면 아무것도 제안하지 않는다")
    func loopbackOnlyYieldsNothing() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 127.0.0.1
          flags    : Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output).isEmpty)
    }

    @Test("상한을 넘으면 앞에서부터 8개까지만 제안한다")
    func capsAtMaximum() {
        var lines = ["DNS configuration", "", "resolver #1"]
        for index in 0..<12 {
            lines.append("  nameserver[\(index)] : 192.0.2.\(index + 1)")
        }
        lines.append("  flags    : Request A records")

        let servers = ScutilDNSOutput.activeResolvers(lines.joined(separator: "\n"))
        #expect(servers.count == ScutilDNSOutput.maxServers)
        #expect(servers.count == 8)
        #expect(servers.first == "192.0.2.1")
        #expect(servers.last == "192.0.2.8")
    }

    @Test("도메인에 묶인 리졸버는 일반 이름 해석에 쓰이지 않으므로 제안하지 않는다")
    func skipsDomainScopedResolver() {
        let output = """
        DNS configuration

        resolver #1
          domain   : vpn.example
          nameserver[0] : 203.0.113.53
          if_index : 23 (utun4)
          flags    : Supplemental, Request A records
          order    : 100600

        resolver #2
          nameserver[0] : 192.0.2.53
          flags    : Request A records
          order    : 200000
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }

    @Test("보조(Supplemental) 리졸버는 도메인 줄이 없어도 제안하지 않는다")
    func skipsSupplementalResolver() {
        let output = """
        DNS configuration

        resolver #1
          search domain[0] : vpn.example
          nameserver[0] : 203.0.113.53
          flags    : Supplemental, Request A records
          order    : 100600

        resolver #2
          nameserver[0] : 192.0.2.53
          flags    : Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }

    @Test("search domain 만 있는 리졸버는 일반 리졸버다 — 접미사일 뿐이라 범위를 좁히지 않는다")
    func searchDomainDoesNotScope() {
        #expect(ScutilDNSOutput.activeResolvers(dhcpOutput).isEmpty == false)
    }

    @Test("일반 리졸버가 없으면 출력 전체로 물러선다")
    func fallsBackToEveryResolver() {
        let output = """
        DNS configuration

        resolver #1
          domain   : local
          options  : mdns
          timeout  : 5
          flags    : Request A records

        DNS configuration (for scoped queries)

        resolver #1
          nameserver[0] : 198.51.100.53
          if_index : 15 (en0)
          flags    : Scoped, Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["198.51.100.53"])
    }

    @Test("빈 출력에서는 아무것도 읽지 않는다")
    func handlesEmptyOutput() {
        #expect(ScutilDNSOutput.activeResolvers("").isEmpty)
        #expect(ScutilDNSOutput.activeResolvers("DNS configuration\n").isEmpty)
    }

    @Test("리졸버 블록 밖의 nameserver 줄은 줍지 않는다")
    func ignoresLinesOutsideResolverBlocks() {
        let output = """
        DNS configuration
          nameserver[0] : 203.0.113.53

        resolver #1
          nameserver[0] : 192.0.2.53
          flags    : Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }

    @Test("잘못된 표기는 걸러낸다")
    func skipsMalformedAddresses() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 192.0.2.999
          nameserver[1] : 192.0.2.053
          nameserver[2] : 192.0.2.53
          flags    : Request A records
        """
        #expect(ScutilDNSOutput.activeResolvers(output) == ["192.0.2.53"])
    }
}

@Suite("DNS 칸 상태")
struct DNSFieldStateTests {

    @Test("수동 지정 값이 있으면 그것이 이긴다")
    func manualWins() {
        let state = DNSFieldState.resolve(
            manual: .servers(["192.0.2.53"]),
            activeResolvers: ["198.51.100.53"]
        )
        #expect(state == .configured(["192.0.2.53"]))
        #expect(state.fieldText == "192.0.2.53")
        #expect(state.notice == nil)
    }

    @Test("수동 지정이 없으면 지금 쓰이는 값을 제안한다")
    func suggestsActiveResolvers() {
        let state = DNSFieldState.resolve(
            manual: .servers([]),
            activeResolvers: ["192.0.2.53", "192.0.2.54"]
        )
        #expect(state == .suggested(["192.0.2.53", "192.0.2.54"]))
        #expect(state.fieldText == "192.0.2.53, 192.0.2.54")
    }

    @Test("수동 지정을 읽지 못했을 때도 쓰이는 값이 있으면 제안한다")
    func suggestsEvenWhenManualUnreadable() {
        let state = DNSFieldState.resolve(
            manual: .unreadable("조회 실패"),
            activeResolvers: ["192.0.2.53"]
        )
        #expect(state == .suggested(["192.0.2.53"]))
    }

    @Test("제안 안내는 출처와 '확인하고 저장' 을 함께 말한다. 오류가 아니다")
    func suggestionNoticeExplainsItself() throws {
        let state = DNSFieldState.resolve(manual: .servers([]), activeResolvers: ["192.0.2.53"])
        let notice = try #require(state.notice)
        #expect(notice.isError == false)
        #expect(notice.text.contains("scutil --dns"))
        #expect(notice.text.contains("확인하고 저장"))
    }

    @Test("아무것도 읽지 못하면 빈 칸으로 두되 그 사실을 말한다")
    func unavailableSpeaksUp() throws {
        let state = DNSFieldState.resolve(manual: .servers([]), activeResolvers: [])
        #expect(state == .unavailable(reason: nil))
        #expect(state.servers.isEmpty)
        #expect(state.fieldText.isEmpty)
        let notice = try #require(state.notice)
        #expect(notice.isError)
        #expect(notice.text.contains("직접 입력"))
    }

    @Test("읽지 못한 사유가 있으면 그대로 옮긴다")
    func unavailableKeepsReason() throws {
        let state = DNSFieldState.resolve(manual: .unreadable("종료 코드 4"), activeResolvers: [])
        #expect(state == .unavailable(reason: "종료 코드 4"))
        let notice = try #require(state.notice)
        #expect(notice.isError)
        #expect(notice.text.contains("종료 코드 4"))
    }

    @Test("세 상태가 화면에서 서로 다르게 보인다")
    func threeStatesLookDifferent() throws {
        let configured = DNSFieldState.resolve(manual: .servers(["192.0.2.53"]), activeResolvers: [])
        let suggested = DNSFieldState.resolve(manual: .servers([]), activeResolvers: ["192.0.2.53"])
        let unavailable = DNSFieldState.resolve(manual: .servers([]), activeResolvers: [])

        // 값이 같아도(칸만 보면 똑같다) 아래 줄이 다르다. 그것이 유일한 구별 근거다.
        #expect(configured.fieldText == suggested.fieldText)
        #expect(configured.notice == nil)

        let suggestionNotice = try #require(suggested.notice)
        let failureNotice = try #require(unavailable.notice)
        #expect(suggestionNotice.text != failureNotice.text)
        // 제안은 오류가 아니다. 빨갛게 쓰면 값이 들어와 있는데도 고장으로 읽힌다.
        #expect(suggestionNotice.isError == false)
        #expect(failureNotice.isError)
    }

    @Test("제안한 값은 현재 구성 초안의 DNS 칸으로 들어간다")
    func suggestionFillsDraft() {
        let info = InterfaceInfo(
            configMethod: .manual,
            ip: IPv4Address("192.0.2.10"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        let draft = ManualProfileDraft.from(
            info,
            dns: .suggested(["192.0.2.53", "192.0.2.54"]),
            ssid: .connected("EXAMPLE-AP")
        )
        #expect(draft?.dns == "192.0.2.53, 192.0.2.54")
    }

    @Test("제안한 값은 그대로 고정 IP 프로필로 저장할 수 있다")
    func suggestionSavesAsProfile() throws {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 127.0.0.1
          nameserver[1] : 192.0.2.53
          nameserver[2] : 192.0.2.53
          flags    : Request A records
        """
        let state = DNSFieldState.resolve(
            manual: .servers([]),
            activeResolvers: ScutilDNSOutput.activeResolvers(output)
        )
        let draft = ManualProfileDraft(
            ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1",
            dns: state.fieldText, ssids: "EXAMPLE-AP"
        )
        let profile = try draft.makeProfile(name: "office", label: nil).get()
        #expect(profile.dns == ["192.0.2.53"])
    }
}
