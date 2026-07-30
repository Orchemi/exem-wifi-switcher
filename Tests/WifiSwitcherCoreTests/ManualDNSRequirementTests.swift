import Foundation
import Testing
@testable import WifiSwitcherCore

/// 고정 IP 프로필에 DNS 가 비어 있으면 이름 해석이 통째로 끊긴다.
///
/// DHCP 프로필은 DNS 를 비워도 된다 — DHCP 서버가 알려준 값을 쓰기 때문이다.
/// 고정 IP 프로필에는 알려줄 주체가 없다. 비어 있으면 `networksetup -setdnsservers ... Empty`
/// 가 resolver 를 0개로 만들고, 사용자는 "인터넷이 안 된다" 를 겪는다.
/// 그래서 **비어 있는 것 자체를 설정 단계에서 막는다.**
@Suite("고정 IP 프로필의 DNS 는 필수")
struct ManualDNSRequirementTests {

    @Test("고정 IP 프로필에 DNS 가 없으면 거부한다")
    func rejectsManualProfileWithoutDNS() {
        let profile = NetworkProfile(
            name: "office", mode: .manual,
            ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1"
        )
        #expect(profile.validate().contains(.missingDNS(profile: "office")))
    }

    @Test("DHCP 프로필은 DNS 를 비워도 된다")
    func allowsEmptyDNSOnDHCP() {
        let profile = NetworkProfile(name: "auto", mode: .dhcp)
        #expect(!profile.validate().contains(.missingDNS(profile: "auto")))
        #expect(profile.validate().isEmpty)
    }

    @Test("DNS 를 하나라도 적으면 통과한다")
    func acceptsManualProfileWithDNS() {
        let profile = NetworkProfile(
            name: "office", mode: .manual,
            ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1",
            dns: ["192.0.2.53"]
        )
        #expect(profile.validate().isEmpty)
    }

    @Test("설정 전체 검증에서도 걸린다")
    func configValidationCatchesIt() {
        let config = AppConfig(
            profiles: [
                NetworkProfile(name: "office", mode: .manual, ip: "192.0.2.10",
                               subnet: "255.255.255.0", router: "192.0.2.1"),
                NetworkProfile(name: "auto", mode: .dhcp),
            ],
            defaultProfile: "auto"
        )
        #expect(config.validate().contains(.missingDNS(profile: "office")))
    }

    @Test("온보딩에서 DNS 칸을 비우면 그 칸에 사유를 붙인다")
    func draftReportsEmptyDNSOnItsOwnField() {
        let draft = ManualProfileDraft(ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1", dns: "")
        guard case .failure(let issues) = draft.makeProfile(name: "office", label: nil) else {
            Issue.record("DNS 가 비었으므로 실패해야 한다")
            return
        }
        #expect(issues.issues.map(\.field) == [.dns])
        // "잘못됐다" 가 아니라 왜 필요한지를 말해야 한다.
        #expect(issues.message(for: .dns)?.contains("DHCP") == true)
    }

    @Test("공백만 적은 것도 비운 것으로 본다")
    func treatsWhitespaceAsEmpty() {
        let draft = ManualProfileDraft(ip: "192.0.2.10", subnet: "255.255.255.0", router: "192.0.2.1", dns: "   \n ")
        guard case .failure(let issues) = draft.makeProfile(name: "office", label: nil) else {
            Issue.record("공백뿐인 DNS 는 비어 있는 것과 같다")
            return
        }
        #expect(issues.issues.map(\.field) == [.dns])
    }
}

/// "DNS 를 읽지 못했다" 와 "DNS 가 설정돼 있지 않다" 는 다른 사실이다.
///
/// 둘을 같은 `[]` 로 뭉개면, 조회에 실패한 상태에서 온보딩을 하는 사용자가
/// **빈 DNS 를 자기 값인 줄 알고 저장**하게 된다.
@Suite("DNS 조회 결과 구분")
struct DNSReadingTests {

    @Test("서버가 설정돼 있으면 목록으로 돌려준다")
    func parsesServers() {
        let reading = NetworkSetupOutput.parseDNSReading(
            output: "192.0.2.53\n198.51.100.53\n", exitCode: 0
        )
        #expect(reading == .servers(["192.0.2.53", "198.51.100.53"]))
        #expect(reading.servers == ["192.0.2.53", "198.51.100.53"])
    }

    @Test("설정된 서버가 없다는 안내는 '없음' 이다 (실패가 아니다)")
    func parsesEmptyAsServers() {
        let reading = NetworkSetupOutput.parseDNSReading(
            output: "There aren't any DNS Servers set on Wi-Fi.\n", exitCode: 0
        )
        #expect(reading == .servers([]))
        #expect(!reading.isUnreadable)
    }

    @Test("종료 코드가 0 이 아니면 읽지 못한 것이다")
    func parsesFailure() {
        let reading = NetworkSetupOutput.parseDNSReading(
            output: "NoSuch is not a recognized network service.\n** Error: The parameters were not valid.\n",
            exitCode: 4
        )
        #expect(reading.isUnreadable)
        #expect(reading.servers.isEmpty)
    }

    @Test("해석할 수 없는 출력도 '없음' 이 아니라 '읽지 못함' 이다")
    func parsesUnrecognizedOutputAsFailure() {
        let reading = NetworkSetupOutput.parseDNSReading(output: "무슨 말인지 모르겠는 출력\n", exitCode: 0)
        #expect(reading.isUnreadable)
    }

    @Test("읽지 못했으면 현재 구성에서 초안을 만들지 않는다")
    func doesNotSuggestDraftWhenDNSUnreadable() {
        let info = InterfaceInfo(
            configMethod: .manual,
            ip: IPv4Address("192.0.2.10"),
            subnet: SubnetMask("255.255.255.0"),
            router: IPv4Address("192.0.2.1")
        )
        let draft = ManualProfileDraft.from(info, dns: .unavailable(reason: "조회 실패"), ssid: .connected("EXAMPLE-AP"))
        // 주소는 제안하되 DNS 칸은 비워둔다. 그리고 그 사실을 창이 알린다.
        #expect(draft?.dns == "")
        #expect(draft?.ip == "192.0.2.10")
    }
}
