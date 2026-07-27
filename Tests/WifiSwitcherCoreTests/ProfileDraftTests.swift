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
        let draft = ManualProfileDraft.from(info, dns: .servers(["192.0.2.53"]))
        #expect(draft?.ip == "192.0.2.10")
        #expect(draft?.subnet == "255.255.255.0")
        #expect(draft?.router == "192.0.2.1")
        #expect(draft?.dns == "192.0.2.53")
    }

    @Test("현재가 DHCP 면 제안할 값이 없다 — 직접 입력받아야 한다")
    func hasNoSuggestionOnDHCP() {
        let info = InterfaceInfo(
            configMethod: .dhcp,
            ip: IPv4Address("192.0.2.77"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        #expect(ManualProfileDraft.from(info, dns: .servers([])) == nil)
    }

    @Test("수동이어도 값이 덜 채워졌으면 제안하지 않는다")
    func hasNoSuggestionWhenIncomplete() {
        let info = InterfaceInfo(configMethod: .manual, ip: IPv4Address("192.0.2.10"))
        #expect(ManualProfileDraft.from(info, dns: .servers([])) == nil)
    }

    // MARK: - 검증

    private func issues(_ draft: ManualProfileDraft) -> [DraftIssue] {
        switch draft.makeProfile(name: "office", label: "사내 고정 IP", ssids: []) {
        case .success: return []
        case .failure(let failure): return failure.issues
        }
    }

    /// 지금 보려는 칸 하나만 남기고 나머지는 정상값으로 채운 초안.
    /// 고정 IP 프로필은 DNS 가 필수라, 채우지 않으면 어느 테스트든 DNS 사유가 함께 딸려 나온다.
    private func draft(ip: String = "192.0.2.10", subnet: String = "255.255.255.0",
                       router: String = "192.0.2.1", dns: String = "192.0.2.53") -> ManualProfileDraft {
        ManualProfileDraft(ip: ip, subnet: subnet, router: router, dns: dns)
    }

    @Test("정상 입력은 프로필이 된다")
    func buildsProfile() throws {
        let draft = ManualProfileDraft(ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1", dns: "192.0.2.53, 192.0.2.54")
        let profile = try draft.makeProfile(name: "office", label: "사내 고정 IP", ssids: ["EXAMPLE-AP"]).get()
        #expect(profile.mode == .manual)
        #expect(profile.ip == "192.0.2.10")
        #expect(profile.dns == ["192.0.2.53", "192.0.2.54"])
        #expect(profile.ssids == ["EXAMPLE-AP"])
        #expect(profile.label == "사내 고정 IP")
        #expect(profile.validate().isEmpty)
    }

    @Test("앞뒤 공백은 입력 실수로 보고 다듬는다")
    func trimsWhitespace() throws {
        let input = ManualProfileDraft(ip: "  192.0.2.10 ", subnet: " 255.255.255.0",
                                       router: "192.0.2.1  ", dns: "  192.0.2.53 ")
        let profile = try input.makeProfile(name: "office", label: nil, ssids: []).get()
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
        let profile = try draft.makeProfile(name: "office", label: nil, ssids: []).get()
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
                                             label: "사내 고정 IP", ssids: []).get()

        let config = OnboardingSetup.makeConfig(service: "Wi-Fi", office: office, existing: nil)
        #expect(config.validate().isEmpty)
        #expect(config.profiles.map(\.name) == ["office", "auto"])
        #expect(config.profile(named: "auto")?.mode == .dhcp)
        // 어느 SSID 에도 걸리지 않으면 DHCP 로 둔다 — 사외에서 인터넷이 끊기지 않는 쪽이 안전하다.
        #expect(config.defaultProfile == "auto")
        #expect(config.service == "Wi-Fi")
    }

    @Test("이미 있던 설정의 SSID 목록과 그 밖의 프로필은 건드리지 않는다")
    func preservesExistingConfiguration() throws {
        let existing = AppConfig(
            service: "Wi-Fi",
            profiles: [
                NetworkProfile(name: "office", mode: .manual, ip: "198.51.100.10", subnet: "255.255.255.0",
                               router: "198.51.100.1", dns: ["198.51.100.53"], ssids: ["EXAMPLE-AP"]),
                NetworkProfile(name: "auto", mode: .dhcp),
                NetworkProfile(name: "lab", mode: .dhcp, ssids: ["LAB-AP"]),
            ],
            defaultProfile: "auto"
        )
        let office = try draft().makeProfile(name: OnboardingSetup.officeProfileName,
                                             label: "사내 고정 IP", ssids: []).get()

        let config = OnboardingSetup.makeConfig(service: "Wi-Fi", office: office, existing: existing)
        #expect(config.validate().isEmpty)
        #expect(config.profile(named: "office")?.ip == "192.0.2.10")
        #expect(config.profile(named: "office")?.ssids == ["EXAMPLE-AP"])
        #expect(config.profile(named: "lab") != nil)
        #expect(config.profiles.count == 3)
    }
}
