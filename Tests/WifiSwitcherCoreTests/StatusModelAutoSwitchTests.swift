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
        location: LocationAuthorizationState = .granted,
        ssid: SSIDReading? = .connected("OFFICE-WIFI"),
        hold: AutoSwitchHold? = nil,
        notifications: NotificationPermission = .allowed
    ) -> StatusInput {
        StatusInput(
            config: .ready(StatusModelAutoSwitchTests.config),
            interface: StatusModelAutoSwitchTests.officeInfo,
            helperInstalled: true,
            location: location,
            autoSwitchEnabled: autoSwitchEnabled,
            ssid: ssid,
            autoSwitchHold: hold,
            notifications: notifications
        )
    }

    /// **잘 돌고 있을 때는 말이 없다** (2026-07-28 오너 판단).
    ///
    /// 예전에는 이 자리에 지금 붙어 있는 Wi-Fi 이름을 적었다. 그런데 이 도구가 하는 일은
    /// 사내·사외 전환을 쉽게 하는 것과 지금 어느 설정인지 확인하는 것이고, **어느 쪽인지는
    /// 메뉴바 아이콘과 프로필의 체크 표시가 이미 말한다.** 이름은 거들지 않는다.
    @Test("켜져 있고 잘 돌고 있으면 아무 줄도 두지 않는다")
    func silentWhileWorking() {
        let model = StatusModel.resolve(input(hold: .alreadyApplied(profile: "office")))
        #expect(model.autoSwitchEnabled)
        #expect(model.autoSwitchNotes.isEmpty)
    }

    /// 말이 없는 것과 **말할 것이 없는 것**은 다르다. 이름을 못 읽는 상태는 지금 무엇에
    /// 붙어 있는지가 아니라 **자동 전환이 성립하지 않는다**는 뜻이라 그대로 남는다.
    @Test("이름을 못 읽는 상태는 켜져 있어도 남긴다")
    func keepsNotesWhenNameCannotBeRead() {
        let wifiOff = StatusModel.resolve(input(ssid: .wifiOff, hold: .wifiOff))
        #expect(wifiOff.autoSwitchNotes == ["Wi-Fi 꺼짐"])

        let notAssociated = StatusModel.resolve(input(ssid: .notAssociated, hold: .notAssociated))
        #expect(notAssociated.autoSwitchNotes == ["Wi-Fi 미접속"])

        // 이름을 못 읽는데 판정은 평소 상태로 남아 있는 순간에도 그 사실이 남아야 한다.
        let unreadable = StatusModel.resolve(input(ssid: .unavailable("읽기 실패"), hold: nil))
        #expect(unreadable.autoSwitchNotes == ["Wi-Fi 이름 읽기 실패"])
    }

    @Test("꺼져 있으면 군더더기를 붙이지 않는다")
    func silentWhenDisabled() {
        let model = StatusModel.resolve(input(autoSwitchEnabled: false, hold: .disabled))
        #expect(!model.autoSwitchEnabled)
        #expect(model.autoSwitchNotes.isEmpty)
    }

    /// 위치 권한이 막힌 상태는 **자동 전환 무리의 일이 아니다.**
    ///
    /// 그 권한은 초기 설정의 필수 항목이라(`SetupChecklist`) 막혀 있으면 머리말이
    /// '초기 설정하기' 로 남고, 켤 수도 끌 수도 없는 자동 전환 무리는 서지 않는다.
    /// 예전에는 여기에 '위치 권한 설정 열기…' 항목을 내놓았는데, 이제 그 조치는
    /// 설정 창의 권한 섹션이 버튼으로 처리한다 — 한 가지 일에 두 개의 문을 두지 않는다.
    @Test("위치 권한이 막히면 자동 전환 무리 대신 머리말이 말한다")
    func surfacesLocationPermission() {
        for (reading, location, hold) in [
            (SSIDReading.permissionDenied, LocationAuthorizationState.denied, AutoSwitchHold.locationPermissionDenied),
            (.permissionNotDetermined, .notDetermined, .locationPermissionRequired),
        ] {
            let model = StatusModel.resolve(input(location: location, ssid: reading, hold: hold))
            #expect(model.headline == "초기 설정하기")
            #expect(model.detail == "위치 권한 없음" || model.detail == "위치 권한 미승인")
            #expect(!MenuLayout.sections(model).contains(.autoSwitch))
            // 이유 자체는 잃지 않는다 — 진단은 여전히 그 한 구를 쓴다.
            #expect(StatusModel.autoSwitchReason(hold, ssid: reading, profiles: model.profiles) != nil)
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

    // MARK: - 권한이 바뀌면 표시도 따라 바뀐다
    //
    // 권한은 **앱 밖에서** 바뀐다. 사용자가 시스템 설정에서 켜고 돌아왔는데 메뉴가 그대로면,
    // 고친 사람에게 안 고쳐졌다고 말하는 셈이다.
    //
    // 다시 읽는 시점(`SwitchNotifier.refresh` · `menuWillOpen` · 앱 활성화)은 시스템 상태에
    // 매여 있어 단위 테스트로 잡을 수 없다. 대신 그 앞뒤를 못박는다 —
    // **값이 바뀌면 모델의 출력이 반드시 따라 바뀐다**는 것. 조건부 표시가 한쪽으로만
    // 동작하면(켤 때만 나타나고 끌 때 안 사라지면) 여기서 걸린다.

    @Test("알림 권한이 허용으로 바뀌면 보조 줄과 조치 항목이 사라진다")
    func followsNotificationPermissionBothWays() {
        let hold = AutoSwitchHold.alreadyApplied(profile: "office")
        let denied = StatusModel.resolve(input(hold: hold, notifications: .denied))
        let allowed = StatusModel.resolve(input(hold: hold, notifications: .allowed))

        // 꺼짐 → 표시
        #expect(denied.needsNotificationPermission)
        #expect(denied.autoSwitchNotes == ["알림 꺼짐"])

        // 허용 → 사라짐. 조치 항목만 거두고 보조 줄이 남으면 사용자는 여전히 꺼진 줄 안다.
        #expect(!allowed.needsNotificationPermission)
        #expect(allowed.autoSwitchNotes.isEmpty)

        // 두 모델이 실제로 다르다 — 메뉴는 모델이 바뀔 때만 다시 그린다(`StatusItemController.render`).
        // 같은 값으로 판정되면 새로 읽어도 화면이 그대로 남는다.
        #expect(denied != allowed)
    }

    @Test("위치 권한이 허용으로 바뀌면 자동 전환 무리가 돌아온다")
    func followsLocationPermissionBothWays() {
        let blocked = StatusModel.resolve(input(location: .denied, ssid: .permissionDenied, hold: .locationPermissionDenied))
        let granted = StatusModel.resolve(input(hold: .alreadyApplied(profile: "office")))

        #expect(!MenuLayout.sections(blocked).contains(.autoSwitch))
        #expect(blocked.detail == "위치 권한 없음")

        // 허용되면 토글이 제자리로 돌아오고, 막혔다는 줄은 사라진다 (잘 돌면 말이 없다).
        #expect(MenuLayout.sections(granted).contains(.autoSwitch))
        #expect(granted.autoSwitchEnabled)
        #expect(granted.autoSwitchNotes.isEmpty)

        #expect(blocked != granted)
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
