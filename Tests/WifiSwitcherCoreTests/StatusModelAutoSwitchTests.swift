import Foundation
import Testing
@testable import WifiSwitcherCore

/// 자동 전환이 메뉴에 어떻게 드러나는가.
///
/// 자동 전환은 눈에 보이지 않는 기능이라, **지금 무엇을 보고 있고 왜 멈춰 있는지**가
/// 메뉴에 드러나지 않으면 사용자는 고장과 구분할 수 없다.
@Suite("메뉴바 자동 전환 표시")
struct StatusModelAutoSwitchTests {

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")
    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")
    private static let officeInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )

    private func input(
        autoSwitchEnabled: Bool = true,
        ssid: SSIDReading? = .connected("OFFICE-WIFI"),
        hold: AutoSwitchHold? = nil,
        notifications: NotificationPermission = .allowed
    ) -> StatusInput {
        StatusInput(
            config: .ready(StatusModelAutoSwitchTests.config),
            interface: StatusModelAutoSwitchTests.officeInfo,
            helperInstalled: true,
            autoSwitchEnabled: autoSwitchEnabled,
            ssid: ssid,
            autoSwitchHold: hold,
            notifications: notifications
        )
    }

    @Test("켜져 있으면 지금 보고 있는 Wi-Fi 이름을 보여준다")
    func showsObservedNetwork() {
        let model = StatusModel.resolve(input(hold: .alreadyApplied(profile: "office")))
        #expect(model.autoSwitchEnabled)
        #expect(model.autoSwitchNotes == ["Wi-Fi OFFICE-WIFI"])
        #expect(!model.needsLocationPermission)
    }

    @Test("꺼져 있으면 군더더기를 붙이지 않는다")
    func silentWhenDisabled() {
        let model = StatusModel.resolve(input(autoSwitchEnabled: false, hold: .disabled))
        #expect(!model.autoSwitchEnabled)
        #expect(model.autoSwitchNotes.isEmpty)
        #expect(!model.needsLocationPermission)
    }

    @Test("위치 권한이 없으면 설정을 여는 항목을 내놓는다")
    func surfacesLocationPermission() {
        for reading in [SSIDReading.permissionDenied, .permissionNotDetermined] {
            let hold: AutoSwitchHold = reading == .permissionDenied
                ? .locationPermissionDenied : .locationPermissionRequired
            let model = StatusModel.resolve(input(ssid: reading, hold: hold))
            // 조치 항목과 함께, 지금 무엇이 막혀 있는지도 한 구로 남긴다.
            #expect(model.needsLocationPermission)
            #expect(model.autoSwitchNotes == ["위치 권한 없음"] || model.autoSwitchNotes == ["위치 권한 미승인"])
        }
    }

    @Test("중단됐으면 몇 번 실패했는지 적는다")
    func explainsGivingUp() {
        let model = StatusModel.resolve(input(hold: .givenUp(profile: "office", failures: 5)))
        let note = model.autoSwitchNotes.first ?? ""
        #expect(note.contains("5"))
        // 프로필은 사람이 읽는 이름으로 적는다.
        #expect(note.contains("사내 고정 IP"))
    }

    @Test("다시 시도할 시각이 정해져 있으면 그 시각을 적는다")
    func explainsBackoff() {
        let retryAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = StatusModel.resolve(input(hold: .backoff(profile: "office", retryAt: retryAt)))
        let note = model.autoSwitchNotes.first ?? ""
        #expect(note.contains("재시도"))
        #expect(note.contains(":"))
    }

    @Test("사용자가 손으로 고른 상태임을 알린다")
    func explainsManualOverride() {
        let model = StatusModel.resolve(input(hold: .manualOverride(profile: "auto")))
        #expect(model.autoSwitchNotes.first?.contains("수동") == true)
    }

    @Test("Wi-Fi 가 꺼져 있으면 그렇게 적는다")
    func explainsWiFiOff() {
        let model = StatusModel.resolve(input(ssid: .wifiOff, hold: .wifiOff))
        #expect(model.autoSwitchNotes == ["Wi-Fi 꺼짐"])
        #expect(!model.needsLocationPermission)
    }

    // MARK: - 멈춘 상태에서 빠져나오는 손잡이
    //
    // 백오프·중단은 **Wi-Fi 가 바뀌어야만** 풀린다. 같은 자리에 앉아 원인을 고친 사용자에게
    // "앱을 다시 띄우세요" 말고 다른 길이 없으면 그것은 고장과 다름없다.

    @Test("실패로 쉬거나 멈춘 상태에서는 '지금 다시 시도' 를 내놓는다")
    func offersRetryWhenStalled() {
        let stalls: [AutoSwitchHold] = [
            .givenUp(profile: "office", failures: 5),
            .backoff(profile: "office", retryAt: Date(timeIntervalSince1970: 1_800_000_000)),
            .ineffective(profile: "office"),
        ]
        for hold in stalls {
            #expect(StatusModel.resolve(input(hold: hold)).canRetryAutoSwitch, "\(hold) 에서 손잡이가 없습니다")
        }
    }

    @Test("평소에는 '지금 다시 시도' 를 내놓지 않는다 — 누를 이유가 없는 항목은 소음이다")
    func hidesRetryWhenHealthy() {
        #expect(!StatusModel.resolve(input(hold: .alreadyApplied(profile: "office"))).canRetryAutoSwitch)
        #expect(!StatusModel.resolve(input(hold: .settling(profile: "office"))).canRetryAutoSwitch)
        #expect(!StatusModel.resolve(input(hold: .manualOverride(profile: "auto"))).canRetryAutoSwitch)
        // 꺼져 있으면 다시 시도할 자동 전환 자체가 없다.
        #expect(!StatusModel.resolve(input(
            autoSwitchEnabled: false, hold: .givenUp(profile: "office", failures: 5)
        )).canRetryAutoSwitch)
    }

    // MARK: - 알림 권한
    //
    // 알림이 막히면 자동 전환은 **완전히 무성**이 된다. 메뉴바 아이콘까지 보이지 않는 환경이면
    // 사용자가 IP 가 바뀐 사실을 알 통로가 하나도 남지 않는다.
    //
    // 그 사실은 **'알림 설정 열기…' 항목 하나로** 전한다. 설명을 함께 적으면 메뉴에
    // 산문이 한 줄 더 늘고, 그 한 줄이 메뉴 폭을 정한다.

    @Test("알림이 거부돼 있으면 설정을 여는 항목을 내놓는다")
    func surfacesDeniedNotifications() {
        let model = StatusModel.resolve(input(notifications: .denied))
        #expect(model.needsNotificationPermission)

        // 자동 전환이 꺼져 있으면 알릴 일 자체가 없다 — 재촉하지 않는다.
        #expect(!StatusModel.resolve(input(autoSwitchEnabled: false, notifications: .denied))
            .needsNotificationPermission)
    }

    @Test("허용됐거나 아직 답하지 않은 상태로는 재촉하지 않는다")
    func quietWhenNotificationsAreFine() {
        for permission in [NotificationPermission.allowed, .pending, .unavailable] {
            #expect(!StatusModel.resolve(input(notifications: permission)).needsNotificationPermission)
        }
    }

    @Test("전환할 수 없는 상태여도 자동 전환 토글은 유지된다")
    func keepsShowingWhenSetupIncomplete() {
        let model = StatusModel.resolve(StatusInput(
            config: .missing(path: "/tmp/x.json"),
            helperInstalled: false,
            autoSwitchEnabled: true,
            ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .configUnavailable
        ))
        #expect(model.autoSwitchEnabled)
        // 머리말과 그 보조 줄이 "설정 필요 / 사내 IP 미등록" 을 이미 말했다. 되풀이하지 않는다.
        #expect(model.autoSwitchNotes.isEmpty)
    }
}
