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
        // **버튼이 곧 조치다.** 그 옆에 "[설치] 를 누르면…" 을 적으면 같은 말이 두 번 있는 것이고,
        // 정작 왜 이 권한이 필요한지가 그 문장에 밀려난다. 그 자리에 남는 줄은 '왜' 여야 한다.
        #expect(item.advice == nil)
        #expect(item.note == item.purpose)
        // 대가는 미리 말한다 — 관리자 인증을 한 번 받는다.
        #expect(item.note.contains("관리자 인증"))
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

    @Test("아직 묻지 않았으면 시스템 설정이 아니라 승인 창으로 간다")
    func locationNotDetermined() {
        let report = PermissionReport.resolve(input(location: .notDetermined))
        let item = report.item(.location)
        #expect(item.state == .undetermined)
        // 창 하나면 끝날 일이다. 목록으로 보내 우리 줄을 찾게 하는 것은 일을 어렵게 만드는 것이다.
        #expect(item.remedy == .requestLocationPermission)
        // 버튼이 조치를 말하므로, 그 자리에 남는 줄은 '왜 필요한가' 다.
        #expect(item.advice == nil)
        #expect(item.note == item.purpose)
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

    /// 앱이 사용자를 보낼 수 있는 자리 전부. 새 화면을 추가하면 여기에도 넣어라 —
    /// 아래 테스트들이 **빠짐없이** 도는 근거다.
    private static let allPanes: [SystemSettingsPane] = [.locationServices, .notifications, .loginItems]

    @Test("시스템 설정 딥링크는 해당 화면을 가리킨다")
    func settingsPaneURLs() {
        #expect(SystemSettingsPane.locationServices.url.contains("Privacy_LocationServices"))
        #expect(SystemSettingsPane.notifications.url.contains("com.apple.preference.notifications"))
        #expect(SystemSettingsPane.loginItems.url.contains("LoginItems-Settings"))
        for pane in Self.allPanes {
            #expect(pane.url.hasPrefix("x-apple.systempreferences:"))
            // 글로 적은 자리도 함께 있어야 한다 — 딥링크가 열리지 않는 날의 유일한 안내다.
            #expect(pane.displayPath.hasPrefix("시스템 설정 > "))
        }
    }

    @Test("알림 딥링크는 우리 앱의 줄을 펴고 연다")
    func notificationPaneRevealsApp() {
        #expect(SystemSettingsPane.notifications.revealsApp)
        let revealed = SystemSettingsPane.notifications.url(revealing: "com.example.app")
        #expect(revealed == "\(SystemSettingsPane.notifications.url)?id=com.example.app")

        // 식별자를 모르면(번들 밖 실행) 화면까지는 연다 — 아무 데도 못 가는 것보다 낫다.
        #expect(SystemSettingsPane.notifications.url(revealing: nil) == SystemSettingsPane.notifications.url)
        #expect(SystemSettingsPane.notifications.url(revealing: "") == SystemSettingsPane.notifications.url)
    }

    @Test("지목할 수 없는 화면에는 질의를 붙이지 않는다")
    func listPanesKeepTheirURLUntouched() {
        // 위치 서비스에 질의를 덧붙이면 앵커가 깨져 상위 '개인정보 보호 및 보안' 으로 떨어진다(실측).
        // 지목할 수 없는 화면은 주소를 **그대로** 두는 것이 최선이다.
        for pane in Self.allPanes where !pane.revealsApp {
            #expect(pane.url(revealing: "com.example.app") == pane.url, "\(pane) 주소에 질의가 붙었다")
        }
    }

    @Test("목록만 열리는 화면은 무엇을 찾아야 하는지 알려준다")
    func listPanesTellWhatToLookFor() {
        for pane in Self.allPanes {
            if pane.revealsApp {
                // 그 앱의 화면이 바로 열리는데 "찾으세요" 라고 하면 없는 수고를 시키는 말이 된다.
                #expect(pane.listHint == nil, "\(pane) 은 지목되는데 찾으라고 한다")
                #expect(pane.openGuidance == "\(pane.displayPath)에서 허용하세요.")
            } else {
                let hint = pane.listHint
                #expect(hint?.contains(InstallPaths.appName) == true, "\(pane) 이 찾을 이름을 말하지 않는다")
                // 이름만 알려주고 목록 앞에 세워 두면 결국 처음부터 훑게 된다.
                // 지목할 수 없는 화면에서 줄 수 있는 단서는 **어디쯤을 보면 되는가** 하나뿐이다.
                #expect(
                    hint?.contains(SystemSettingsPane.listOrder) == true,
                    "\(pane) 이 어디쯤을 봐야 하는지 말하지 않는다"
                )
                #expect(pane.openGuidance.contains(hint ?? "\u{0}"))
            }
            // 어느 쪽이든 갈 자리는 반드시 적힌다.
            #expect(pane.openGuidance.contains(pane.displayPath))
        }
    }

    @Test("권한 안내는 갈 자리와 찾을 이름을 함께 적는다")
    func adviceCarriesGuidance() {
        // 위치는 목록이 열리므로 이름까지, 알림은 앱 화면이 열리므로 자리까지만.
        let location = item(.location, input(location: .denied))
        #expect(location.advice?.contains(InstallPaths.appName) == true)
        #expect(location.advice?.contains(SystemSettingsPane.locationServices.displayPath) == true)

        let notification = item(.notification, input(notifications: .denied))
        #expect(notification.advice?.contains(SystemSettingsPane.notifications.displayPath) == true)
        #expect(notification.advice?.contains(InstallPaths.appName) == false)
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

    @Test("시스템 설정 주소를 화면 쪽에 다시 적지 않는다")
    func settingsURLsLiveInOnePlace() throws {
        // 같은 주소를 메뉴와 설정 창에 따로 적어 두면, 한쪽만 고쳐진 채 조용히 갈라진다.
        // (실제로 그렇게 두 벌이었다 — 주소는 `SystemSettingsPane` 한 곳에 있다)
        for path in [
            "Sources/ExemWifiSwitcherApp/StatusItemController.swift",
            "Sources/ExemWifiSwitcherApp/SettingsWindowController.swift",
        ] {
            #expect(
                try !source(path).contains("x-apple.systempreferences"),
                "\(path) 가 시스템 설정 주소를 직접 들고 있다"
            )
        }
    }

    @Test("시스템 설정으로 가는 길을 문구로도 두 벌 적지 않는다")
    func settingsPathsAreNotRetyped() throws {
        // 알림 본문에는 누를 버튼이 없어 갈 자리를 글로 적는데, 그 글을 여기서 새로 쓰면
        // 화면과 알림이 서로 다른 경로를 안내하게 된다 (`displayPath` 가 유일한 출처다).
        let announcement = try source("Sources/WifiSwitcherCore/SwitchAnnouncement.swift")
        #expect(!announcement.contains("시스템 설정 >"), "알림 문구가 설정 경로를 직접 들고 있다")
        #expect(announcement.contains("SystemSettingsPane"), "알림 문구가 공용 안내를 쓰지 않는다")
    }

    /// 권한은 **앱 밖에서** 바뀐다. 그 사실을 알아채는 것은 값이 아니라 **다시 읽는 시점**이고,
    /// 그 시점은 시스템 상태에 매여 있어 단위 테스트로 잡을 수 없다.
    ///
    /// 잃어버리기는 쉽다 — 없어도 빌드가 되고 테스트가 통과하며, 화면은 기동 때 읽은 값을
    /// 그럴듯하게 계속 보여준다. 그래서 **자리가 남아 있는지만** 소스로 확인한다
    /// (판정을 한 곳에 모으는 위 테스트들과 같은 방식이다).
    ///
    /// 리팩터링으로 이름이 바뀌면 이 테스트가 걸린다. 그때는 **다시 읽는 자리가 남아 있는지
    /// 확인하고** 이름을 고쳐라 — 테스트만 지우면 같은 버그가 조용히 돌아온다.
    @Test("메뉴가 권한을 다시 읽는 자리를 잃지 않는다")
    func menuRereadsPermissions() throws {
        let controller = try source("Sources/ExemWifiSwitcherApp/StatusItemController.swift")
        // 메뉴를 여는 순간 · 시스템 설정에 다녀와 돌아온 순간, 둘 다 갱신으로 이어져야 한다.
        #expect(controller.contains("func menuWillOpen"))
        #expect(controller.contains("didBecomeActiveNotification"), "설정에 다녀온 것을 알아챌 자리가 없다")
        // 그 갱신이 알림 권한까지 다시 묻는가. 이것이 빠지면 기동 때 읽은 값이 영영 남는다.
        #expect(controller.contains("notifier.refresh()"), "갱신이 알림 권한을 다시 묻지 않는다")

        let notifier = try source("Sources/ExemWifiSwitcherApp/SwitchNotifier.swift")
        #expect(notifier.contains("func refresh()"), "알림 권한을 다시 읽는 길이 없다")
    }
}
