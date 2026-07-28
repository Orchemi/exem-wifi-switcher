import Foundation
import Testing
@testable import WifiSwitcherCore

/// 권한 점검의 판정 규칙.
///
/// 이 계산에도 시스템 호출이 없다 — 관측값(설치 여부·계정 종류·위치/알림 권한)을 넣으면
/// 항목별 상태와 조치가 결정된다. 설정 창과 `--diagnose` 가 **같은 판정**을 쓰는 근거가 여기다.
@Suite("권한 점검")
struct PermissionReportTests {

    private func input(
        applyInstalled: Bool = true,
        sudoersInstalled: Bool = true,
        saveConfigInstalled: Bool = true,
        isAdministrator: Bool = true,
        installerAvailable: Bool = true,
        location: LocationAuthorizationState = .granted,
        wifiNameVisible: Bool = false,
        notifications: NotificationPermission = .allowed
    ) -> PermissionInput {
        PermissionInput(
            applyInstalled: applyInstalled,
            sudoersInstalled: sudoersInstalled,
            saveConfigInstalled: saveConfigInstalled,
            isAdministrator: isAdministrator,
            installerAvailable: installerAvailable,
            location: location,
            wifiNameVisible: wifiNameVisible,
            notifications: notifications
        )
    }

    private func item(_ subject: PermissionSubject, _ input: PermissionInput) -> PermissionItem {
        PermissionReport.resolve(input).item(subject)
    }

    // MARK: - 전체 모양

    @Test("항목은 넷이고 순서가 고정돼 있다")
    func hasFixedItems() {
        let report = PermissionReport.resolve(input())
        #expect(report.items.map(\.subject) == [.switching, .saving, .location, .notification])
    }

    @Test("모든 항목이 왜 필요한지 한 줄을 갖는다")
    func everyItemExplainsItself() {
        // 위치 권한이 Wi-Fi 앱에 왜 필요한지는 설명이 없으면 의심스럽게 보인다.
        for item in PermissionReport.resolve(input()).items {
            #expect(!item.title.isEmpty)
            #expect(!item.purpose.isEmpty)
            #expect(!item.status.isEmpty)
        }
    }

    @Test("다 갖춰졌으면 조치할 것이 없다")
    func allSatisfied() {
        let report = PermissionReport.resolve(input())
        #expect(!report.needsAttention)
        for item in report.items {
            #expect(item.state == .satisfied)
            #expect(item.advice == nil)
            #expect(item.remedy == .none)
            // 문제가 없을 때 화면에 남는 줄은 '왜 필요한가' 하나뿐이다.
            #expect(item.note == item.purpose)
        }
    }

    // MARK: - 전환 권한

    @Test("전환 권한이 없으면 앱 안에서 설치할 수 있게 한다")
    func switchingNotInstalled() {
        let item = item(.switching, input(applyInstalled: false, sudoersInstalled: false))
        #expect(item.state == .actionNeeded)
        #expect(item.remedy == .install)
        // 무엇이 일어날지 미리 말한다 — 누르면 계획을 보여주고 인증을 한 번 받는다.
        #expect(item.advice?.contains("설치") == true)
        #expect(item.advice?.contains("인증") == true)
        #expect(PermissionReport.resolve(input(applyInstalled: false)).needsAttention)
    }

    @Test("번들 밖에서 실행 중이면 앱이 설치할 수 있는 척하지 않는다")
    func switchingWithoutBundledInstaller() {
        let item = item(.switching, input(applyInstalled: false, installerAvailable: false))
        #expect(item.remedy == .runCommand(PermissionReport.installCommand))
        #expect(item.advice?.contains(PermissionReport.installCommand) == true)
        #expect(item.advice?.contains("터미널") == true)
    }

    @Test("스크립트는 있는데 무암호 규칙이 없으면 그 사실을 따로 말한다")
    func switchingMissingSudoersRule() {
        // 이 상태는 '설치됨' 으로 보이지만 전환할 때마다 암호를 물어 실패한다.
        let ruleMissing = item(.switching, input(sudoersInstalled: false))
        let notInstalled = item(.switching, input(applyInstalled: false))
        #expect(ruleMissing.state == .actionNeeded)
        #expect(ruleMissing.status != notInstalled.status)
        #expect(ruleMissing.remedy == .install)
    }

    // MARK: - 설정 저장 권한

    @Test("저장 권한이 없으면 같은 설치로 안내한다")
    func savingNotInstalled() {
        let missing = item(.saving, input(saveConfigInstalled: false))
        #expect(missing.state == .actionNeeded)
        #expect(missing.remedy == .install)

        let withoutInstaller = item(.saving, input(saveConfigInstalled: false, installerAvailable: false))
        #expect(withoutInstaller.remedy == .runCommand(PermissionReport.installCommand))
    }

    @Test("관리자 계정이 아니면 설치로 해결되지 않는다고 말한다")
    func savingWithoutAdministrator() {
        let item = item(.saving, input(isAdministrator: false))
        #expect(item.state == .actionNeeded)
        // 설치 명령을 내밀면 안 된다 — 실행해도 상태가 달라지지 않는다.
        #expect(item.remedy == .none)
        #expect(item.advice?.contains("관리자") == true)
    }

    @Test("저장 권한이 아예 없으면 계정 종류보다 설치가 먼저다")
    func savingMissingHelperComesFirst() {
        let item = item(.saving, input(saveConfigInstalled: false, isAdministrator: false))
        #expect(item.remedy == .install)
    }

    // MARK: - 되돌리기

    @Test("설치된 것이 없으면 제거할 것도 없다")
    func nothingToUninstall() {
        let report = PermissionReport.resolve(
            input(applyInstalled: false, sudoersInstalled: false, saveConfigInstalled: false)
        )
        #expect(!report.canUninstall)
    }

    @Test("반쯤 설치된 상태도 제거 대상이다", arguments: [
        (true, false, false), (false, true, false), (false, false, true), (true, true, true),
    ])
    func partialInstallCanBeUndone(_ state: (apply: Bool, sudoers: Bool, saveConfig: Bool)) {
        // 남은 조각을 지울 길이 없으면 사용자는 터미널로 밀려난다.
        let report = PermissionReport.resolve(input(
            applyInstalled: state.apply,
            sudoersInstalled: state.sudoers,
            saveConfigInstalled: state.saveConfig
        ))
        #expect(report.canUninstall)
    }

    @Test("번들 밖에서는 제거도 앱이 대신하지 않는다")
    func cannotUninstallWithoutBundledInstaller() {
        #expect(!PermissionReport.resolve(input(installerAvailable: false)).canUninstall)
    }

    // MARK: - 위치 권한

    @Test("위치 권한이 거부되면 설정을 열어 준다")
    func locationDenied() {
        let item = item(.location, input(location: .denied))
        #expect(item.state == .actionNeeded)
        #expect(item.remedy == .openSettings(.locationServices))
        // 없으면 무슨 일이 생기는지 적는다 — 자동 전환이 조용히 멈춘다.
        #expect(item.advice?.contains("자동 전환") == true)
    }

    @Test("아직 묻지 않은 위치 권한은 문제로 세지 않는다")
    func locationNotDetermined() {
        let report = PermissionReport.resolve(input(location: .notDetermined))
        let item = report.item(.location)
        #expect(item.state == .undetermined)
        #expect(item.advice != nil)
        #expect(item.remedy == .openSettings(.locationServices))
        // 곧 승인 창이 뜰 상태를 붉게 칠하지 않는다.
        #expect(!report.needsAttention)
    }

    /// Wi-Fi 이름이 읽히고 있다는 것은 **위치 권한이 있다는 증거**다.
    ///
    /// `CLLocationManager` 는 만든 직후 아직 정해지지 않은 값을 준다 — 실제 상태는 조금 뒤
    /// 델리게이트로 온다. 그 사이의 값을 그대로 옮기면 "권한 없음" 과 "Wi-Fi 이름 읽음" 이
    /// 한 화면에 함께 찍힌다. **둘 중 하나는 틀렸고, 틀린 쪽은 권한 표시다.**
    @Test("Wi-Fi 이름이 읽히면 위치 권한을 '아직 묻지 않음' 으로 적지 않는다")
    func locationEvidenceBeatsStaleStatus() {
        let item = item(.location, input(location: .notDetermined, wifiNameVisible: true))
        #expect(item.state == .satisfied)
        #expect(item.advice == nil)
        #expect(item.remedy == .none)
    }

    @Test("거부 상태는 증거로 덮지 않는다 — 그때는 이름이 읽힐 리 없다")
    func deniedStaysDenied() {
        #expect(item(.location, input(location: .denied, wifiNameVisible: true)).state == .actionNeeded)
    }

    // MARK: - 알림 권한

    @Test("알림이 거부되면 전환이 조용해진다고 알린다")
    func notificationDenied() {
        let item = item(.notification, input(notifications: .denied))
        #expect(item.state == .actionNeeded)
        #expect(item.remedy == .openSettings(.notifications))
        #expect(item.advice?.contains("메뉴") == true)
    }

    @Test("알림 권한을 아직 묻지 않았으면 기다린다")
    func notificationPending() {
        let report = PermissionReport.resolve(input(notifications: .pending))
        #expect(report.item(.notification).state == .undetermined)
        #expect(!report.needsAttention)
    }

    @Test("번들 밖에서는 알림 상태를 확인할 수 없다고 말한다")
    func notificationUnavailable() {
        let item = item(.notification, input(notifications: .unavailable))
        #expect(item.state == .undetermined)
        // 사용자가 할 수 있는 일이 없다. 버튼을 내밀지 않는다.
        #expect(item.remedy == .none)
    }

    // MARK: - 진단 출력과의 공유

    @Test("진단 한 줄은 상태와 조치를 이어 붙인다")
    func diagnosticText() {
        #expect(item(.location, input()).diagnosticText == item(.location, input()).status)

        let denied = item(.location, input(location: .denied))
        #expect(denied.diagnosticText == "\(denied.status) — \(denied.advice ?? "")")
    }

    @Test("시스템 설정 딥링크는 해당 화면을 가리킨다")
    func settingsPaneURLs() {
        #expect(SystemSettingsPane.locationServices.url.contains("Privacy_LocationServices"))
        #expect(SystemSettingsPane.notifications.url.contains("com.apple.preference.notifications"))
        for pane in [SystemSettingsPane.locationServices, .notifications] {
            #expect(pane.url.hasPrefix("x-apple.systempreferences:"))
        }
    }

    @Test("여러 항목이 어긋나도 각자의 조치를 따로 낸다")
    func independentRemedies() {
        let report = PermissionReport.resolve(
            input(applyInstalled: false, location: .denied, notifications: .denied)
        )
        #expect(report.needsAttention)
        #expect(report.items.filter { $0.state == .actionNeeded }.count == 3)
        #expect(report.item(.saving).state == .satisfied)
    }
}

/// 판정을 두 곳에서 따로 만들면 반드시 어긋난다. **한 곳에서 나온 값만** 쓰는지 소스로 확인한다.
///
/// 계층이 갈라지는 것을 막는 방식은 프로필 이름 규칙(3계층 교차 테스트)에서 쓴 것과 같다 —
/// 여기서는 화면과 진단이 같은 타입을 거치는지를 본다.
@Suite("권한 판정 출처 일치")
struct PermissionSourceParityTests {

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLayout.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("설정 창과 진단이 모두 PermissionReport 를 거친다")
    func bothUseTheReport() throws {
        for path in [
            "Sources/ExemWifiSwitcherApp/SettingsWindowController.swift",
            "Sources/ExemWifiSwitcherApp/Diagnostics.swift",
        ] {
            #expect(try source(path).contains("PermissionReport"), "\(path) 가 권한 판정을 따로 만들고 있다")
        }
    }

    @Test("진단이 권한 문구를 스스로 만들지 않는다")
    func diagnosticsHasNoOwnWording() throws {
        let text = try source("Sources/ExemWifiSwitcherApp/Diagnostics.swift")
        // 예전에 진단이 직접 들고 있던 문구들. 다시 생기면 두 화면이 다른 답을 낸다.
        for phrase in ["./scripts/install.sh", "시스템 설정 > 알림", "위치 서비스"] {
            #expect(!text.contains(phrase), "진단이 '\(phrase)' 문구를 직접 들고 있다")
        }
    }
}
