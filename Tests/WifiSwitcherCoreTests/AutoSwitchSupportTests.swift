import Foundation
import Testing
@testable import WifiSwitcherCore

/// SSID 판독 결과를 화면·판정이 어떻게 읽는가.
@Suite("SSID 판독 결과")
struct SSIDReadingTests {

    @Test("접속한 Wi-Fi 이름만 이름을 갖는다")
    func onlyConnectedHasName() {
        #expect(SSIDReading.connected("OFFICE-WIFI").name == "OFFICE-WIFI")
        #expect(SSIDReading.notAssociated.name == nil)
        #expect(SSIDReading.wifiOff.name == nil)
        #expect(SSIDReading.permissionDenied.name == nil)
        #expect(SSIDReading.permissionNotDetermined.name == nil)
        #expect(SSIDReading.unavailable("이유").name == nil)
    }

    @Test("권한 때문에 못 읽은 경우를 따로 구분한다")
    func distinguishesPermissionProblems() {
        #expect(SSIDReading.permissionDenied.isPermissionProblem)
        #expect(SSIDReading.permissionNotDetermined.isPermissionProblem)
        #expect(!SSIDReading.notAssociated.isPermissionProblem)
        #expect(!SSIDReading.connected("X").isPermissionProblem)
    }

    @Test("모든 결과에 사람이 읽을 한 줄이 있다 — 조용히 사라지는 상태를 만들지 않는다")
    func everyReadingExplainsItself() {
        for reading in Self.everyReading {
            #expect(!reading.statusText.isEmpty)
            #expect(!reading.diagnosticText.isEmpty)
        }
        #expect(SSIDReading.permissionDenied.statusText.contains("위치"))
    }

    /// 메뉴에 올라가는 줄은 **짧은 명사구**다. 문장을 올리면 그 한 줄이 메뉴 폭을 정한다.
    @Test("메뉴에 올릴 한 줄은 문장이 아니다")
    func statusTextIsANounPhrase() {
        #expect(SSIDReading.connected("OFFICE-WIFI").statusText == "Wi-Fi OFFICE-WIFI")
        #expect(SSIDReading.wifiOff.statusText == "Wi-Fi 꺼짐")
        #expect(SSIDReading.notAssociated.statusText == "Wi-Fi 미접속")
        for reading in Self.everyReading {
            #expect(!reading.statusText.contains("습니다"), "문장이다: \(reading.statusText)")
            #expect(reading.statusText.count <= 24)
        }
    }

    /// 진단은 폭이 아니라 사실이 중요하다 — 메뉴에서 덜어낸 원인을 여기서는 끝까지 적는다.
    @Test("진단 한 줄은 못 읽은 이유를 끝까지 남긴다")
    func diagnosticTextKeepsTheCause() {
        #expect(SSIDReading.connected("OFFICE-WIFI").diagnosticText == "OFFICE-WIFI")
        #expect(SSIDReading.unavailable("인터페이스 없음").diagnosticText.contains("인터페이스 없음"))
    }

    private static let everyReading: [SSIDReading] = [
        .connected("OFFICE-WIFI"), .notAssociated, .wifiOff,
        .permissionDenied, .permissionNotDetermined, .unavailable("인터페이스 없음"),
    ]
}

/// 이벤트 묶기(디바운스) — 무한 루프를 막는 첫 겹.
@Suite("이벤트 묶기")
struct EventCoalescerTests {

    private let coalescer = EventCoalescer(quietPeriod: 1.2, maximumDelay: 6)
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// `Date` 는 기준 시각으로부터의 초를 Double 로 담는다. 값이 클수록 마지막 자리가 흔들리므로
    /// 시간 계산은 정확히 같기를 요구하지 않는다.
    private func expect(_ actual: TimeInterval, near expected: TimeInterval) {
        #expect(abs(actual - expected) < 0.001, "기대 \(expected), 실제 \(actual)")
    }

    @Test("첫 이벤트는 조용해질 때까지 기다린다")
    func waitsForQuiet() {
        expect(coalescer.delay(now: Self.t0, burstStartedAt: nil), near: 1.2)
    }

    @Test("이벤트가 이어지면 그때마다 다시 미룬다")
    func extendsWhileEventsKeepComing() {
        let later = Self.t0.addingTimeInterval(1)
        expect(coalescer.delay(now: later, burstStartedAt: Self.t0), near: 1.2)
    }

    @Test("첫 이벤트로부터 상한을 넘겨 미루지는 않는다")
    func doesNotPostponeForever() {
        // 첫 이벤트로부터 5.5초. 여기서 1.2초를 더 기다리면 상한(6초)을 넘는다.
        let late = Self.t0.addingTimeInterval(5.5)
        expect(coalescer.delay(now: late, burstStartedAt: Self.t0), near: 0.5)
    }

    @Test("상한을 이미 지났으면 곧바로 처리한다")
    func firesImmediatelyPastTheLimit() {
        let tooLate = Self.t0.addingTimeInterval(30)
        #expect(coalescer.delay(now: tooLate, burstStartedAt: Self.t0) == 0)
    }
}

/// 자동 전환 on/off 는 껐다 켠 뒤에도 유지돼야 한다.
@Suite("자동 전환 설정 보관")
struct AutoSwitchPreferencesTests {

    private final class MemoryStore: AutoSwitchStore {
        var values: [String: Bool] = [:]
        func boolValue(forKey key: String) -> Bool? { values[key] }
        func setBool(_ value: Bool, forKey key: String) { values[key] = value }
    }

    @Test("한 번도 정한 적이 없으면 켜져 있다")
    func defaultsToEnabled() {
        #expect(AutoSwitchPreferences.isEnabled(in: MemoryStore()))
    }

    @Test("끄면 꺼진 채로 남는다")
    func remembersDisabled() {
        let store = MemoryStore()
        AutoSwitchPreferences.setEnabled(false, in: store)
        #expect(!AutoSwitchPreferences.isEnabled(in: store))

        AutoSwitchPreferences.setEnabled(true, in: store)
        #expect(AutoSwitchPreferences.isEnabled(in: store))
    }
}

/// 전환 알림 문구.
///
/// 사용자 모르게 IP 가 바뀌면 안 된다. 그렇다고 호들갑 떨 일도 아니다 —
/// **무엇이 왜 바뀌었는지 사실만** 적는다.
@Suite("전환 알림 문구")
struct SwitchAnnouncementTests {

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")

    @Test("고정 IP 로 바꿨으면 어떤 Wi-Fi 에서 어떤 주소가 됐는지 알린다")
    func announcesManualSwitch() {
        let message = SwitchAnnouncement.applied(profile: Self.office, ssid: "OFFICE-WIFI")
        #expect(message.title == "사내 고정 IP 적용")
        #expect(message.body.contains("OFFICE-WIFI"))
        #expect(message.body.contains("192.0.2.10"))
    }

    @Test("DHCP 로 돌아갔으면 그렇게 알린다")
    func announcesDHCPSwitch() {
        let message = SwitchAnnouncement.applied(profile: Self.auto, ssid: "SOME-CAFE")
        #expect(message.title == "자동 (DHCP) 적용")
        #expect(message.body.contains("SOME-CAFE"))
    }

    @Test("Wi-Fi 이름을 모르면 이름 없이 적는다")
    func announcesWithoutSSID() {
        let message = SwitchAnnouncement.applied(profile: Self.auto, ssid: nil)
        #expect(!message.body.isEmpty)
        #expect(!message.body.contains("nil"))
    }

    @Test("실패 알림은 이유를 담되 길게 늘어놓지 않는다")
    func announcesFailure() {
        let long = String(repeating: "가", count: 500)
        let message = SwitchAnnouncement.failed(profile: Self.office, ssid: "OFFICE-WIFI", reason: long)
        #expect(message.title.contains("전환 실패"))
        #expect(message.body.count <= SwitchAnnouncement.bodyLengthLimit)
    }

    @Test("자동 전환을 멈췄으면 멈춘 사실과 다시 시도할 조건을 알린다")
    func announcesStop() {
        let message = SwitchAnnouncement.stopped(profile: Self.office, failures: 5)
        #expect(message.title.contains("중단"))
        #expect(message.body.contains("5"))
        #expect(message.body.contains("Wi-Fi"))
    }

    @Test("위치 권한이 없으면 무엇을 해야 하는지까지 적는다")
    func announcesLocationPermission() {
        let message = SwitchAnnouncement.locationPermissionNeeded()
        #expect(message.title.contains("위치"))
        #expect(message.body.contains("시스템 설정"))
    }

    @Test("느낌표로 호들갑 떨지 않는다")
    func staysPlain() {
        let messages = [
            SwitchAnnouncement.applied(profile: Self.office, ssid: "OFFICE-WIFI"),
            SwitchAnnouncement.failed(profile: Self.office, ssid: nil, reason: "권한 없음"),
            SwitchAnnouncement.stopped(profile: Self.office, failures: 5),
            SwitchAnnouncement.locationPermissionNeeded(),
        ]
        for message in messages {
            #expect(!message.title.contains("!"))
            #expect(!message.body.contains("!"))
        }
    }
}
