import Foundation
import Testing
@testable import WifiSwitcherCore

/// 온보딩 입력값 처리.
///
/// 화면은 AppKit 이지만 **판단은 전부 여기**에 있다. 어떤 칸이 왜 잘못됐는지까지
/// 이 계층에서 정하므로, 창을 띄우지 않고도 온보딩의 행동을 검증할 수 있다.
@Suite("온보딩 입력")
struct ProfileDraftTests {

    // MARK: - 현재 구성에서 뽑아오기

    @Test("현재가 수동 구성이면 그 값을 초안으로 제안한다")
    func suggestsDraftFromManualConfiguration() {
        let info = InterfaceInfo(
            configMethod: .manual,
            ip: IPv4Address("192.0.2.10"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        let draft = ManualProfileDraft.from(info, dns: .servers(["192.0.2.53"]), ssid: .connected("EXAMPLE-AP"))
        #expect(draft?.ip == "192.0.2.10")
        #expect(draft?.subnet == "255.255.255.0")
        #expect(draft?.router == "192.0.2.1")
        #expect(draft?.dns == "192.0.2.53")
        // 지금 고정 IP 로 붙어 있는 자리가 곧 이 프로필을 쓸 자리다 — Wi-Fi 이름까지 끌어온다.
        // 이 칸이 비면 값이 다 맞아도 자동 전환이 이 프로필을 고르지 못한다.
        #expect(draft?.ssids == "EXAMPLE-AP")
    }

    @Test("Wi-Fi 이름을 읽지 못했으면 그 칸만 비워 둔다")
    func leavesSSIDEmptyWhenUnreadable() {
        let info = InterfaceInfo(
            configMethod: .manual,
            ip: IPv4Address("192.0.2.10"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        for reading in [SSIDReading.permissionDenied, .permissionNotDetermined, .notAssociated, .wifiOff] {
            let draft = ManualProfileDraft.from(info, dns: .servers(["192.0.2.53"]), ssid: reading)
            // 나머지 값은 그대로 제안한다 — 이름 하나 못 읽었다고 온보딩 전체를 막지 않는다.
            #expect(draft?.ip == "192.0.2.10")
            #expect(draft?.ssids == "", "\(reading) 에서 엉뚱한 이름이 들어갔다")
        }
    }

    @Test("현재가 DHCP 면 제안할 값이 없다 — 직접 입력받아야 한다")
    func hasNoSuggestionOnDHCP() {
        let info = InterfaceInfo(
            configMethod: .dhcp,
            ip: IPv4Address("192.0.2.77"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        // Wi-Fi 이름이 읽히더라도 마찬가지다. DHCP 로 도는 자리는 사내가 아닐 수 있고,
        // 집·카페 이름을 사내 프로필에 적어 두면 **그 자리에서 사내 고정 IP 가 걸린다.**
        #expect(ManualProfileDraft.from(info, dns: .servers([]), ssid: .connected("HOME-AP")) == nil)
    }

    @Test("수동이어도 값이 덜 채워졌으면 제안하지 않는다")
    func hasNoSuggestionWhenIncomplete() {
        let info = InterfaceInfo(configMethod: .manual, ip: IPv4Address("192.0.2.10"))
        #expect(ManualProfileDraft.from(info, dns: .servers([]), ssid: .connected("EXAMPLE-AP")) == nil)
    }

    // MARK: - 검증

    private func issues(_ draft: ManualProfileDraft) -> [DraftIssue] {
        switch draft.makeProfile(name: "office", label: "사내 고정 IP") {
        case .success: return []
        case .failure(let failure): return failure.issues
        }
    }

    /// 지금 보려는 칸 하나만 남기고 나머지는 정상값으로 채운 초안.
    /// 고정 IP 프로필은 DNS 가 필수라, 채우지 않으면 어느 테스트든 DNS 사유가 함께 딸려 나온다.
    private func draft(ip: String = "192.0.2.10", subnet: String = "255.255.255.0",
                       router: String = "192.0.2.1", dns: String = "192.0.2.53",
                       ssids: String = "EXAMPLE-AP") -> ManualProfileDraft {
        ManualProfileDraft(ip: ip, subnet: subnet, router: router, dns: dns, ssids: ssids)
    }

    @Test("정상 입력은 프로필이 된다")
    func buildsProfile() throws {
        let draft = ManualProfileDraft(
            ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1",
            dns: "192.0.2.53, 192.0.2.54", ssids: "EXAMPLE-AP"
        )
        let profile = try draft.makeProfile(name: "office", label: "사내 고정 IP").get()
        #expect(profile.mode == .manual)
        #expect(profile.ip == "192.0.2.10")
        #expect(profile.dns == ["192.0.2.53", "192.0.2.54"])
        #expect(profile.ssids == ["EXAMPLE-AP"])
        #expect(profile.label == "사내 고정 IP")
        #expect(profile.validate().isEmpty)
    }

    // MARK: - Wi-Fi 이름 칸
    //
    // 이 칸 하나가 자동 전환의 방아쇠다. 비어 있으면 값이 다 맞아도 프로필이 선택되지 않고,
    // 잘못 들어가면 엉뚱한 자리에서 사내 고정 IP 가 걸린다.

    @Test("Wi-Fi 이름은 쉼표로 여럿 적을 수 있다")
    func acceptsSeveralNetworkNames() throws {
        let profile = try draft(ssids: "EXAMPLE-AP, EXAMPLE-GUEST").makeProfile(name: "office", label: nil).get()
        #expect(profile.ssids == ["EXAMPLE-AP", "EXAMPLE-GUEST"])
    }

    @Test("Wi-Fi 이름 안의 공백은 이름의 일부다 — 쪼개지 않는다")
    func keepsSpacesInsideNetworkNames() throws {
        // DNS 처럼 공백으로 끊으면 'EXAMPLE AP' 가 둘로 갈라져 어느 쪽도 실제 Wi-Fi 와 맞지 않는다.
        let profile = try draft(ssids: "  EXAMPLE AP ,  EXAMPLE GUEST  ").makeProfile(name: "office", label: nil).get()
        #expect(profile.ssids == ["EXAMPLE AP", "EXAMPLE GUEST"])
    }

    @Test("Wi-Fi 이름을 비워 두는 것은 막지 않는다 — 손으로만 쓰는 길이 있다")
    func allowsEmptyNetworkNames() throws {
        // 자동 전환은 못 걸리지만 메뉴에서 직접 고르는 쓰임은 그대로다.
        // 대신 그 사실은 창이 자리표시자로 미리 말한다 (조용히 비우지 않는다).
        let profile = try draft(ssids: "  ").makeProfile(name: "office", label: nil).get()
        #expect(profile.ssids.isEmpty)
    }

    @Test("쓸 수 없는 Wi-Fi 이름은 그 칸을 지목한다")
    func reportsBadNetworkNames() {
        // 규칙은 NetworkProfile.validate() 것을 그대로 쓴다 — 여기서 새로 만들지 않는다.
        for bad in [String(repeating: "x", count: 33), "EXAMPLE-AP, EXAMPLE-AP", "bad\u{0000}name"] {
            let found = issues(draft(ssids: bad))
            #expect(found.map(\.field) == [.ssids], "'\(bad)' 가 Wi-Fi 이름 칸으로 지목되지 않았다")
        }
    }

    @Test("앞뒤 공백은 입력 실수로 보고 다듬는다")
    func trimsWhitespace() throws {
        let input = ManualProfileDraft(ip: "  192.0.2.10 ", subnet: " 255.255.255.0",
                                       router: "192.0.2.1  ", dns: "  192.0.2.53 ")
        let profile = try input.makeProfile(name: "office", label: nil).get()
        #expect(profile.ip == "192.0.2.10")
        #expect(profile.dns == ["192.0.2.53"])
    }

    @Test("빈 칸은 빈 칸이라고 알린다")
    func reportsEmptyFields() {
        let found = issues(ManualProfileDraft(ip: "", subnet: "", router: "", dns: ""))
        // DNS 도 고정 IP 프로필의 필수 항목이다 — 빈 칸이면 함께 지목한다.
        #expect(found.map(\.field) == [.ip, .subnet, .router, .dns])
        #expect(found.allSatisfy { $0.message.contains("입력") })
    }

    @Test("잘못된 칸만 지목한다")
    func pinpointsInvalidField() {
        let found = issues(draft(ip: "192.0.2.999"))
        #expect(found.count == 1)
        #expect(found.first?.field == .ip)
        // "잘못된 입력" 이 아니라 무엇이 왜 잘못됐는지를 말해야 한다.
        #expect(found.first?.message.contains("192.0.2.10") == true)
    }

    @Test("서브넷 마스크는 왜 마스크가 아닌지까지 말한다")
    func explainsSubnetMask() {
        let found = issues(draft(subnet: "255.0.255.0"))
        #expect(found.map(\.field) == [.subnet])
        #expect(found.first?.message.contains("연속") == true)
    }

    @Test("라우터가 대역 밖이면 라우터 칸에 붙인다")
    func attachesSubnetMismatchToRouter() {
        let found = issues(draft(router: "198.51.100.1"))
        #expect(found.map(\.field) == [.router])
        #expect(found.first?.message.contains("192.0.2") == true)
    }

    @Test("IP 와 라우터가 같으면 잡는다")
    func rejectsSameAddress() {
        let found = issues(draft(ip: "192.0.2.1", router: "192.0.2.1"))
        #expect(found.map(\.field) == [.router])
    }

    @Test("네트워크·브로드캐스트 주소는 호스트로 쓸 수 없다고 알린다")
    func rejectsReservedAddress() {
        let found = issues(draft(ip: "192.0.2.255"))
        #expect(found.map(\.field) == [.ip])
        #expect(found.first?.message.contains("브로드캐스트") == true)
    }

    @Test("DNS 는 쉼표·공백·줄바꿈 어느 쪽으로 나눠도 받는다")
    func splitsDNSLiberally() throws {
        let draft = ManualProfileDraft(ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1",
                                       dns: "192.0.2.53,192.0.2.54\n192.0.2.55 192.0.2.56")
        let profile = try draft.makeProfile(name: "office", label: nil).get()
        #expect(profile.dns.count == 4)
    }

    @Test("DNS 주소가 이상하면 그 값을 짚어준다")
    func reportsBadDNS() {
        let found = issues(draft(dns: "192.0.2.53, dns.example"))
        #expect(found.map(\.field) == [.dns])
        #expect(found.first?.message.contains("dns.example") == true)
    }

    @Test("DNS 개수 상한을 넘기면 잡는다")
    func rejectsTooManyDNS() {
        let many = (1...9).map { "192.0.2.\($0)" }.joined(separator: ",")
        let found = issues(draft(dns: many))
        #expect(found.map(\.field) == [.dns])
    }

    // MARK: - 설정 조립

    @Test("온보딩 결과는 고정 IP + DHCP 두 프로필짜리 설정이 된다")
    func buildsConfigurationFromScratch() throws {
        let office = try draft().makeProfile(name: OnboardingSetup.officeProfileName,
                                             label: "사내 고정 IP").get()

        let config = OnboardingSetup.makeConfig(service: "Wi-Fi", office: office, existing: nil)
        #expect(config.validate().isEmpty)
        #expect(config.profiles.map(\.name) == ["office", "auto"])
        #expect(config.profile(named: "auto")?.mode == .dhcp)
        // 어느 SSID 에도 걸리지 않으면 DHCP 로 둔다 — 사외에서 인터넷이 끊기지 않는 쪽이 안전하다.
        #expect(config.defaultProfile == "auto")
        #expect(config.service == "Wi-Fi")
    }

    /// 저장을 여러 번 해도 사용자가 손으로 만든 것이 사라지지 않아야 한다.
    private static let existingConfig = AppConfig(
        service: "Wi-Fi",
        profiles: [
            NetworkProfile(name: "office", mode: .manual, ip: "198.51.100.10", subnet: "255.255.255.0",
                           router: "198.51.100.1", dns: ["198.51.100.53"], ssids: ["OLD-AP"]),
            NetworkProfile(name: "auto", mode: .dhcp),
            NetworkProfile(name: "lab", mode: .dhcp, ssids: ["LAB-AP"]),
        ],
        defaultProfile: "auto"
    )

    @Test("고정 IP 프로필은 넘어온 값으로 덮고, 그 밖의 프로필은 건드리지 않는다")
    func preservesExistingConfiguration() throws {
        let office = try draft(ssids: "EXAMPLE-AP").makeProfile(name: OnboardingSetup.officeProfileName,
                                                                label: "사내 고정 IP").get()

        let config = OnboardingSetup.makeConfig(service: "Wi-Fi", office: office, existing: Self.existingConfig)
        #expect(config.validate().isEmpty)
        #expect(config.profile(named: "office")?.ip == "192.0.2.10")
        // 창이 들고 있던 값이 그대로 저장된다 — 옛 이름이 섞여 들지 않는다.
        #expect(config.profile(named: "office")?.ssids == ["EXAMPLE-AP"])
        #expect(config.profile(named: "lab") != nil)
        #expect(config.profiles.count == 3)
    }

    @Test("Wi-Fi 이름을 지우고 저장하면 지워진 채로 남는다")
    func honoursClearedNetworkNames() throws {
        // 예전에는 넘어온 목록이 비면 옛 목록을 되살렸다. 화면에 그 칸이 없던 시절의 보호막인데,
        // 칸이 생긴 지금은 **지운 이름을 되돌려 놓는 짓**이 된다 — 지웠는데 그대로면 그것은 고장이다.
        let office = try draft(ssids: "").makeProfile(name: OnboardingSetup.officeProfileName,
                                                      label: "사내 고정 IP").get()

        let config = OnboardingSetup.makeConfig(service: "Wi-Fi", office: office, existing: Self.existingConfig)
        #expect(config.profile(named: "office")?.ssids.isEmpty == true)
        // 다른 프로필의 이름 목록은 그대로다 — 지운 것은 이 프로필의 칸뿐이다.
        #expect(config.profile(named: "lab")?.ssids == ["LAB-AP"])
    }
}
