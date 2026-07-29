import Foundation
import Testing
@testable import WifiSwitcherCore

/// 자동 전환 판정.
///
/// 이 판정에는 시스템 호출이 없다 — 관측값(설정·SSID·현재 구성)과 지난 시도 기록을 넣으면
/// "지금 전환할 것인가, 하지 않는다면 왜인가" 가 결정된다.
///
/// 여기서 가장 중요한 것은 **전환하지 않는 경우들**이다. 자동 전환이 스스로를 다시 부르는
/// 구조를 만들면 네트워크가 끊임없이 흔들린다. 그래서 no-op·정착 대기·백오프·중단을
/// 전부 이 자리에서 못박는다.
@Suite("자동 전환 판정")
struct AutoSwitchPolicyTests {

    // MARK: - 고정 값

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", dns: ["192.0.2.53"], ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")
    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")

    /// 고정 IP 프로필이 요구하는 DNS 가 그대로 걸려 있는 상태.
    private static let officeDNS = DNSReading.servers(["192.0.2.53"])
    /// DHCP 프로필이 기대하는 상태 — 수동으로 지정된 DNS 가 없다.
    private static let noDNS = DNSReading.servers([])

    private static let officeInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )
    private static let dhcpInfo = InterfaceInfo(
        configMethod: .dhcp,
        ip: IPv4Address("198.51.100.23"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("198.51.100.1")
    )

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// DNS 가 시나리오의 관심사가 아닐 때의 기본값.
    /// **읽지 못한 상태**로 두면 판정에서 제외되므로, 그 시나리오가 보려는 것만 남는다.
    private static let dnsNotInScope = DNSReading.unreadable("이 시나리오에서는 DNS 를 보지 않습니다")

    private func context(
        enabled: Bool = true,
        config: ConfigStatus = .ready(AutoSwitchPolicyTests.config),
        switching: SwitchingPermission = .satisfied,
        ssid: SSIDReading = .connected("OFFICE-WIFI"),
        interface: InterfaceInfo? = AutoSwitchPolicyTests.dhcpInfo,
        dns: DNSReading = AutoSwitchPolicyTests.dnsNotInScope,
        isBusy: Bool = false
    ) -> AutoSwitchContext {
        AutoSwitchContext(
            isEnabled: enabled,
            config: config,
            switching: switching,
            ssid: ssid,
            interface: interface,
            dns: dns,
            isBusy: isBusy
        )
    }

    /// 판정 + 그 결과를 기록까지 한 상태를 함께 돌려준다 (연속 시나리오를 짧게 쓰기 위한 도우미).
    private func decide(
        _ context: AutoSwitchContext,
        _ state: AutoSwitchState,
        _ now: Date = AutoSwitchPolicyTests.t0
    ) -> AutoSwitchDecision {
        var state = state
        state.adopt(ssid: context.ssid.name)
        return AutoSwitchPolicy.decide(context, state: state, now: now)
    }

    // MARK: - 전환하는 경우

    @Test("등록된 SSID 에 접속했고 구성이 다르면 그 프로필로 전환한다")
    func appliesMatchingProfile() {
        #expect(decide(context(), AutoSwitchState()) == .apply(profile: "office"))
    }

    @Test("등록되지 않은 SSID 에서는 기본 프로필로 돌아간다")
    func fallsBackToDefaultProfile() {
        let outside = context(ssid: .connected("SOME-CAFE"), interface: Self.officeInfo)
        #expect(decide(outside, AutoSwitchState()) == .apply(profile: "auto"))
    }

    @Test("현재 구성을 읽지 못했으면 확인할 길이 없으므로 한 번은 시도한다")
    func appliesWhenCurrentStateUnknown() {
        #expect(decide(context(interface: nil), AutoSwitchState()) == .apply(profile: "office"))
    }

    // MARK: - 전환하지 않는 경우 (무한 루프 방지의 핵심)

    @Test("이미 목표 구성이면 아무것도 하지 않는다")
    func noOpWhenAlreadyApplied() {
        let settled = context(interface: Self.officeInfo)
        #expect(decide(settled, AutoSwitchState()) == .hold(.alreadyApplied(profile: "office")))
    }

    @Test("등록되지 않은 SSID 에서 이미 DHCP 면 아무것도 하지 않는다")
    func noOpWhenAlreadyDHCP() {
        let outside = context(ssid: .connected("SOME-CAFE"), interface: Self.dhcpInfo)
        #expect(decide(outside, AutoSwitchState()) == .hold(.alreadyApplied(profile: "auto")))
    }

    @Test("자동 전환이 꺼져 있으면 판정하지 않는다")
    func holdsWhenDisabled() {
        #expect(decide(context(enabled: false), AutoSwitchState()) == .hold(.disabled))
    }

    @Test("전환이 진행 중이면 겹쳐 부르지 않는다")
    func holdsWhileSwitching() {
        #expect(decide(context(isBusy: true), AutoSwitchState()) == .hold(.busy))
    }

    // MARK: - 위치 권한

    @Test("위치 권한이 거부됐으면 전환하지 않는다 — 어디에 있는지 모르는 채로 IP 를 바꾸지 않는다")
    func holdsWhenLocationDenied() {
        #expect(decide(context(ssid: .permissionDenied), AutoSwitchState()) == .hold(.locationPermissionDenied))
    }

    @Test("위치 권한을 아직 묻지 않았으면 기다린다")
    func holdsWhenLocationNotDetermined() {
        #expect(decide(context(ssid: .permissionNotDetermined), AutoSwitchState()) == .hold(.locationPermissionRequired))
    }

    @Test("Wi-Fi 가 꺼져 있거나 접속돼 있지 않으면 구성을 건드리지 않는다")
    func holdsWithoutWiFi() {
        #expect(decide(context(ssid: .wifiOff), AutoSwitchState()) == .hold(.wifiOff))
        #expect(decide(context(ssid: .notAssociated), AutoSwitchState()) == .hold(.notAssociated))
    }

    @Test("Wi-Fi 인터페이스 자체가 없으면 이유를 남기고 멈춘다")
    func holdsWhenUnsupported() {
        let reading = SSIDReading.unavailable("Wi-Fi 인터페이스를 찾지 못했습니다")
        #expect(decide(context(ssid: reading), AutoSwitchState())
            == .hold(.ssidUnavailable("Wi-Fi 인터페이스를 찾지 못했습니다")))
    }

    // MARK: - 준비되지 않은 환경

    @Test("설정이 준비되지 않았으면 전환하지 않는다")
    func holdsWithoutConfig() {
        #expect(decide(context(config: .missing(path: "/tmp/x.json")), AutoSwitchState()) == .hold(.configUnavailable))
        #expect(decide(context(config: .pristineExample(path: "/tmp/x.json")), AutoSwitchState()) == .hold(.configUnavailable))
    }

    // MARK: - 전환 권한
    //
    // **2026-07-29 판정의 뜻이 바뀌었다.** 전에는 `apply` 파일이 놓여 있으면 시도했다.
    // 그런데 전환은 무암호 sudoers 규칙이 함께 있어야 성립한다 — 규칙만 빠진 상태에서는
    // (macOS 업데이트가 `/etc/sudoers.d/` 를 정리하는 일이 있다) `sudo -n` 이 그 자리에서 거부한다.
    // 예전 정책은 그 뻔한 실패를 다섯 번 쌓은 뒤에야 멈췄고, 그동안 실패 알림이 뜨고 메뉴에 실패가 남았다.
    // 메뉴는 같은 상태에서 이미 전환을 잠그고 있었으므로(`SetupChecklist.switchingPermission`)
    // 자동 전환만 혼자 시도하고 있던 셈이다. **두 자리가 같은 판정을 쓰게 했다** (`SwitchingPermission`).

    @Test("전환 권한이 갖춰지지 않았으면 시도하지 않는다 — 실패가 뻔한 호출을 반복하지 않는다")
    func holdsWithoutSwitchingPermission() {
        // 스크립트가 없다.
        #expect(decide(context(switching: SwitchingPermission(applyInstalled: false, sudoersInstalled: true)),
                       AutoSwitchState()) == .hold(.switchingPermissionMissing))
        // 스크립트는 있는데 무암호 규칙이 없다 — 겉보기에는 설치된 상태다. 여기가 예전에 뚫려 있었다.
        #expect(decide(context(switching: SwitchingPermission(applyInstalled: true, sudoersInstalled: false)),
                       AutoSwitchState()) == .hold(.switchingPermissionMissing))
        #expect(decide(context(switching: SwitchingPermission(applyInstalled: false, sudoersInstalled: false)),
                       AutoSwitchState()) == .hold(.switchingPermissionMissing))
    }

    @Test("권한이 없는 동안에는 아무것도 쌓이지 않고, 복구되면 곧바로 다시 시도한다")
    func resumesWhenSwitchingPermissionIsRestored() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        let ruleMissing = context(switching: SwitchingPermission(applyInstalled: true, sudoersInstalled: false))

        // 판정이 몇 번을 오가도 시도가 없다. 시도가 없으므로 기록도 없다
        // (기록은 실제로 적용을 시작하는 자리에서만 남는다 — `StatusItemController.apply`).
        var now = Self.t0
        for _ in 0..<10 {
            #expect(AutoSwitchPolicy.decide(ruleMissing, state: state, now: now)
                == .hold(.switchingPermissionMissing))
            now = now.addingTimeInterval(60)
        }
        #expect(state.consecutiveFailures == 0)

        // 사용자가 설정 창에서 [설치] 를 다시 눌렀다. **중단 상태로 굳어 있으면 안 된다** —
        // 다음 판정에서 바로 되살아나야 한다 (관측값은 갱신 때마다 다시 읽힌다).
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: now) == .apply(profile: "office"))
    }

    @Test("걸리는 프로필도 기본 프로필도 없으면 멈춘다")
    func holdsWithoutAnyProfile() {
        let orphan = AppConfig(profiles: [Self.office], defaultProfile: "office")
        var broken = orphan
        broken.defaultProfile = "nowhere"
        let decision = decide(context(config: .ready(broken), ssid: .connected("SOME-CAFE")), AutoSwitchState())
        #expect(decision == .hold(.noMatchingProfile(ssid: "SOME-CAFE")))
    }

    // MARK: - 정착 대기 · 헛도는 전환

    @Test("전환에 성공한 직후에는 구성이 따라올 시간을 준다")
    func waitsForStateToSettle() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordSuccess(at: Self.t0)

        // 아직 -getinfo 는 이전 값을 보여준다. 여기서 다시 적용하면 서로를 물어뜯는다.
        let soon = Self.t0.addingTimeInterval(2)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: soon) == .hold(.settling(profile: "office")))
    }

    @Test("성공했다는데 구성이 끝내 따라오지 않으면 재적용을 멈춘다")
    func stopsWhenApplyHasNoEffect() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordSuccess(at: Self.t0)

        let later = Self.t0.addingTimeInterval(AutoSwitchPolicy.settleInterval + 1)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: later) == .hold(.ineffective(profile: "office")))
    }

    @Test("구성이 따라왔으면 정착 대기는 끝난다")
    func settledStateIsQuiet() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordSuccess(at: Self.t0)

        let applied = context(interface: Self.officeInfo, dns: Self.officeDNS)
        #expect(AutoSwitchPolicy.decide(applied, state: state, now: Self.t0.addingTimeInterval(1))
            == .hold(.alreadyApplied(profile: "office")))
    }

    // MARK: - 정착한 뒤 구성이 다시 어긋나는 경우
    //
    // 이 도구가 조용히 죽는 가장 흔한 길이다. 한 번 성공했다는 기록이 남아 있으면,
    // 나중에 사용자가 시스템 설정에서 IP 를 만지거나 macOS 업데이트가 구성을 되돌려도
    // "적용은 했는데 효과가 없다"(ineffective) 로 굳어 **그 Wi-Fi 를 떠날 때까지** 아무것도 하지 않는다.

    @Test("정착을 확인한 뒤 구성이 다시 어긋나면 재적용한다")
    func reappliesWhenConfigurationDriftsAfterSettling() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordSuccess(at: Self.t0)

        // 구성이 따라왔다. 이 순간 시도 기록은 정산된다.
        let settledAt = Self.t0.addingTimeInterval(3)
        #expect(AutoSwitchPolicy.decide(context(interface: Self.officeInfo, dns: Self.officeDNS),
                                        state: state, now: settledAt)
            == .hold(.alreadyApplied(profile: "office")))
        state.recordSettled(profile: "office", at: settledAt)

        // 한참 뒤 누군가 구성을 되돌렸다. 여기서 멈추면 Wi-Fi 가 바뀌기 전까지 영원히 멈춘다.
        let drifted = settledAt.addingTimeInterval(3_600)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: drifted) == .apply(profile: "office"))
    }

    @Test("정착을 확인한 직후의 어긋남은 낡은 관측일 수 있어 잠깐 기다린다")
    func waitsBrieflyAfterSettling() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordSettled(profile: "office", at: Self.t0)

        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0.addingTimeInterval(1))
            == .hold(.settling(profile: "office")))
    }

    @Test("한 번도 정착을 관측하지 못했을 때만 '적용했는데 효과가 없다' 로 멈춘다")
    func ineffectiveOnlyWithoutAnySettledObservation() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordSuccess(at: Self.t0)

        let later = Self.t0.addingTimeInterval(AutoSwitchPolicy.settleInterval + 1)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: later)
            == .hold(.ineffective(profile: "office")))

        // 한 번이라도 정착을 봤다면 같은 상황이 '효과 없음' 이 아니다 — 나중에 풀린 것이다.
        state.recordSettled(profile: "office", at: Self.t0.addingTimeInterval(1))
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: later) == .apply(profile: "office"))
    }

    // MARK: - 시도했는데 결과를 모르는 경우

    @Test("시도 기록만 있고 결과가 없으면 최소 정착 시간만큼은 다시 걸지 않는다")
    func holdsWhenAttemptOutcomeIsUnknown() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)

        // 성공도 실패도 기록되지 않았다. 아무 홀드도 내지 않으면 판정마다 다시 걸어 무한 재시도가 된다.
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0.addingTimeInterval(1))
            == .hold(.settling(profile: "office")))
        // 다만 영원히 묶어 두지는 않는다. 결과를 끝내 모르면 한 번 더 시도하는 편이 낫다.
        let later = Self.t0.addingTimeInterval(AutoSwitchPolicy.settleInterval + 1)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: later) == .apply(profile: "office"))
    }

    // MARK: - DNS 도 구성의 일부다
    //
    // IP·서브넷·라우터만 보면, 사내 DNS 가 그대로 남은 채 집에서 DHCP 로 돌고 있는 상태를
    // "이미 적용됨" 으로 판정한다. 그 상태에서는 도달할 수 없는 resolver 를 물고 있어 이름 해석이 끊긴다.

    @Test("IP 는 목표와 같아도 DNS 가 다르면 아직 적용된 것이 아니다")
    func detectsDNSMismatch() {
        let wrongDNS = context(interface: Self.officeInfo, dns: .servers(["198.51.100.53"]))
        #expect(decide(wrongDNS, AutoSwitchState()) == .apply(profile: "office"))
    }

    @Test("사내 DNS 가 남은 채 DHCP 로 돌고 있으면 기본 프로필을 다시 적용한다")
    func detectsLeftoverDNSOutsideOffice() {
        let outside = context(
            ssid: .connected("SOME-CAFE"), interface: Self.dhcpInfo, dns: .servers(["192.0.2.53"])
        )
        #expect(decide(outside, AutoSwitchState()) == .apply(profile: "auto"))
    }

    @Test("IP 와 DNS 가 모두 목표와 같으면 아무것도 하지 않는다")
    func noOpWhenDNSAlsoMatches() {
        let applied = context(interface: Self.officeInfo, dns: Self.officeDNS)
        #expect(decide(applied, AutoSwitchState()) == .hold(.alreadyApplied(profile: "office")))

        let outside = context(ssid: .connected("SOME-CAFE"), interface: Self.dhcpInfo, dns: Self.noDNS)
        #expect(decide(outside, AutoSwitchState()) == .hold(.alreadyApplied(profile: "auto")))
    }

    @Test("DNS 를 읽지 못한 것을 '다르다' 로 단정하지 않는다 — 읽기 실패가 무한 재적용이 되면 안 된다")
    func unreadableDNSDoesNotForceReapply() {
        let unreadable = context(interface: Self.officeInfo, dns: .unreadable("networksetup 실패"))
        #expect(decide(unreadable, AutoSwitchState()) == .hold(.alreadyApplied(profile: "office")))
    }

    @Test("DNS 순서까지 목표와 같아야 적용된 것으로 본다")
    func dnsOrderMatters() {
        let ordered = NetworkProfile(
            name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
            router: "192.0.2.1", dns: ["192.0.2.53", "198.51.100.53"], ssids: ["OFFICE-WIFI"]
        )
        #expect(DNSReading.servers(["192.0.2.53", "198.51.100.53"]).conformance(to: ordered) == .matches)
        #expect(DNSReading.servers(["198.51.100.53", "192.0.2.53"]).conformance(to: ordered) == .differs)
        #expect(DNSReading.unreadable("실패").conformance(to: ordered) == .undecidable)
    }

    // MARK: - 실패 백오프

    @Test("실패 직후에는 곧바로 다시 시도하지 않는다")
    func backsOffAfterFailure() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordFailure(message: "sudo: a password is required", at: Self.t0)

        let retryAt = Self.t0.addingTimeInterval(AutoSwitchPolicy.backoffInterval(consecutiveFailures: 1))
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0.addingTimeInterval(1))
            == .hold(.backoff(profile: "office", retryAt: retryAt)))
    }

    @Test("백오프가 지나면 다시 시도한다")
    func retriesAfterBackoff() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordFailure(message: "실패", at: Self.t0)

        let after = Self.t0.addingTimeInterval(AutoSwitchPolicy.backoffInterval(consecutiveFailures: 1) + 1)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: after) == .apply(profile: "office"))
    }

    @Test("대기 시간은 실패가 쌓일수록 길어지고 상한에서 멈춘다")
    func backoffGrowsAndIsCapped() {
        let intervals = (1...6).map { AutoSwitchPolicy.backoffInterval(consecutiveFailures: $0) }
        #expect(intervals == intervals.sorted())
        #expect(intervals.first == 10)
        #expect(intervals.allSatisfy { $0 <= AutoSwitchPolicy.maximumBackoff })
        #expect(intervals.last == AutoSwitchPolicy.maximumBackoff)
        // 실패가 없으면 기다릴 이유도 없다.
        #expect(AutoSwitchPolicy.backoffInterval(consecutiveFailures: 0) == 0)
    }

    @Test("연속 실패가 한도에 이르면 자동 전환을 멈춘다")
    func givesUpAfterRepeatedFailures() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        for _ in 0..<AutoSwitchPolicy.failureLimit {
            state.recordAttempt(profile: "office", at: Self.t0)
            state.recordFailure(message: "실패", at: Self.t0)
        }
        let muchLater = Self.t0.addingTimeInterval(86_400)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: muchLater)
            == .hold(.givenUp(profile: "office", failures: AutoSwitchPolicy.failureLimit)))
    }

    @Test("상한은 실제로 도달할 수 있는 값이다 — 문서와 상수가 어긋나지 않게")
    func backoffCapIsReachable() {
        // 마지막 재시도는 failureLimit - 1 회 실패 뒤에 온다. 그 뒤로는 멈추므로,
        // 그보다 큰 상한은 어디에도 쓰이지 않는 숫자다.
        #expect(AutoSwitchPolicy.backoffInterval(consecutiveFailures: AutoSwitchPolicy.failureLimit - 1)
            == AutoSwitchPolicy.maximumBackoff)
    }

    @Test("실패 기록을 지우면 멈춰 있던 자동 전환이 곧바로 다시 시도한다")
    func clearingAttemptsResumesAfterGivingUp() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        for _ in 0..<AutoSwitchPolicy.failureLimit {
            state.recordAttempt(profile: "office", at: Self.t0)
            state.recordFailure(message: "실패", at: Self.t0)
        }
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0)
            == .hold(.givenUp(profile: "office", failures: AutoSwitchPolicy.failureLimit)))

        // 같은 Wi-Fi 에 머무는 한 앱을 다시 띄우는 것 말고는 빠져나올 길이 없으면 안 된다.
        state.clearAttempts()
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0) == .apply(profile: "office"))
    }

    @Test("실패 기록을 지워도 사용자의 수동 선택은 남는다")
    func clearingAttemptsKeepsManualChoice() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordManualChoice(profile: "auto")
        state.clearAttempts()

        #expect(state.manualChoice == "auto")
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0)
            == .hold(.manualOverride(profile: "auto")))
    }

    @Test("Wi-Fi 가 바뀌면 실패 기록을 잊고 다시 시작한다")
    func forgetsFailuresWhenNetworkChanges() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        for _ in 0..<AutoSwitchPolicy.failureLimit {
            state.recordAttempt(profile: "office", at: Self.t0)
            state.recordFailure(message: "실패", at: Self.t0)
        }
        let elsewhere = context(ssid: .connected("SOME-CAFE"), interface: Self.officeInfo)
        #expect(decide(elsewhere, state, Self.t0.addingTimeInterval(5)) == .apply(profile: "auto"))
    }

    @Test("성공하면 실패 기록이 지워진다")
    func successClearsFailures() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordFailure(message: "실패", at: Self.t0)
        state.recordAttempt(profile: "office", at: Self.t0.addingTimeInterval(30))
        state.recordSuccess(at: Self.t0.addingTimeInterval(30))

        #expect(state.consecutiveFailures == 0)
        #expect(state.lastFailureMessage == nil)
    }

    // MARK: - 사용자의 수동 선택

    @Test("사용자가 손으로 고른 프로필을 자동 전환이 곧바로 되돌리지 않는다")
    func respectsManualChoice() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordManualChoice(profile: "auto")

        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0)
            == .hold(.manualOverride(profile: "auto")))
    }

    @Test("자동이 고를 프로필을 사용자가 직접 골랐다면 그대로 자동에 맡긴다")
    func manualChoiceMatchingAutomationIsNotAnOverride() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordManualChoice(profile: "office")

        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0) == .apply(profile: "office"))
    }

    @Test("Wi-Fi 가 바뀌면 수동 선택은 풀린다")
    func manualChoiceEndsWithTheNetwork() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordManualChoice(profile: "auto")
        state.adopt(ssid: "SOME-CAFE")

        #expect(state.manualChoice == nil)
        #expect(state.consecutiveFailures == 0)
    }

    @Test("접속이 잠깐 끊겼다고 실패 기록을 지우지 않는다")
    func keepsRecordWhileNetworkNameIsUnknown() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordFailure(message: "실패", at: Self.t0)

        // 끊김·권한 없음 등으로 이름을 모르는 순간이 끼어든다.
        state.adopt(ssid: nil)
        state.adopt(ssid: "OFFICE-WIFI")

        // 여기서 기록이 지워지면 '끊김 → 재접속' 이 반복될 때마다 백오프가 풀려 무한 재시도가 된다.
        #expect(state.consecutiveFailures == 1)
        #expect(AutoSwitchPolicy.decide(context(), state: state, now: Self.t0.addingTimeInterval(1))
            == .hold(.backoff(
                profile: "office",
                retryAt: Self.t0.addingTimeInterval(AutoSwitchPolicy.backoffInterval(consecutiveFailures: 1))
            )))
    }

    @Test("같은 Wi-Fi 에 머무는 동안에는 기록이 유지된다")
    func keepsRecordWhileOnSameNetwork() {
        var state = AutoSwitchState()
        state.adopt(ssid: "OFFICE-WIFI")
        state.recordAttempt(profile: "office", at: Self.t0)
        state.recordFailure(message: "실패", at: Self.t0)
        state.adopt(ssid: "OFFICE-WIFI")

        #expect(state.consecutiveFailures == 1)
    }
}
