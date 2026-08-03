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
        saveConfigAcceptsDigest: Bool = true,
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
            saveConfigAcceptsDigest: saveConfigAcceptsDigest,
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
            // **갖춰진 항목에는 아무 줄도 붙지 않는다.** 이미 해결된 일을 두고 왜 필요한지를
            // 계속 읽힐 이유가 없다 — 전부 갖춰지면 권한 섹션은 상태 넉 줄로 끝난다.
            #expect(item.note == nil)
            #expect(item.diagnosticText == item.status)
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
        // 대가는 미리 말한다 — 관리자 인증을 한 번 받는다. 줄이다가 이것까지 지우면
        // 사용자가 전환할 때마다 암호를 물을 줄 안다.
        #expect(item.note?.contains("관리자 인증 1회") == true)
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

    /// **앱만 새로 받은 사람이 겪는 자리다** (2026-08-03 실측).
    ///
    /// 예전 버전의 `save-config` 가 그대로 남아 있으면 저장은 `helperOutdated` 로 막히는데,
    /// 권한 표는 파일이 있다는 이유로 '설치됨' 이라고 적었다. 그래서 **안내는 재설치하라는데
    /// 재설치할 자리가 화면에 없었다** — 남은 길은 [앱 삭제…] 로 전부 지우고 처음부터 하거나
    /// 번들 안 스크립트 경로를 알아내 터미널로 부르는 것뿐이었다. 동료 배포에서 성립하지 않는다.
    @Test("설치된 저장 스크립트가 오래됐으면 설치됨이라고 적지 않는다")
    func savingHelperOutdated() {
        let outdated = item(.saving, input(saveConfigAcceptsDigest: false))
        #expect(outdated.state == .actionNeeded)
        #expect(outdated.status != item(.saving, input()).status)
        // 새 손잡이를 만들지 않는다 — 이미 있는 [설치] 버튼이 그대로 서면 된다.
        // 그 버튼은 계획 미리보기 → 확인 → 관리자 인증 → install.sh 를 이미 들고 있다.
        #expect(outdated.remedy == .install)
        // 상태만 봐서는 알 수 없는 사실이다. 무엇이 막히는지 한 줄로 말한다.
        #expect(outdated.note?.contains("저장") == true)
        #expect(outdated.details?.contains("오래") == true)
    }

    @Test("오래된 저장 스크립트도 번들 밖에서는 설치할 수 있는 척하지 않는다")
    func savingHelperOutdatedWithoutBundledInstaller() {
        let item = item(.saving, input(saveConfigAcceptsDigest: false, installerAvailable: false))
        #expect(item.remedy == .runCommand(PermissionReport.installCommand))
    }

    /// 판정 순서는 **저장 경로가 막히는 순서와 같아야 한다** (`ConfigInstaller.save`).
    /// 그쪽은 파일 유무 → 관리자 여부 → 지문 계약 순으로 막는다. 표가 다른 순서로 말하면
    /// 화면이 가리키는 조치와 실제로 걸리는 자리가 어긋난다.
    @Test("관리자가 아닌 계정에는 오래된 스크립트보다 계정 사실을 먼저 말한다")
    func savingOrderFollowsTheSavePath() {
        let item = item(.saving, input(saveConfigAcceptsDigest: false, isAdministrator: false))
        #expect(item.remedy == .none)
        #expect(item.advice?.contains("관리자") == true)
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

    @Test("화면은 한 줄로 줄이고, 터미널에는 상세를 싣는다")
    func diagnosticText() {
        // 갖춰졌으면 상태 한 마디로 끝난다.
        #expect(item(.location, input()).diagnosticText == item(.location, input()).status)

        // 화면에는 누를 버튼과 갈 자리가 있지만 터미널에는 둘 다 없다 — 폭도 넉넉하다.
        let denied = item(.location, input(location: .denied))
        #expect(denied.note == denied.advice)
        #expect(denied.details != nil)
        #expect(denied.diagnosticText == "\(denied.status) — \(denied.details ?? "")")
        // 화면 줄은 짧고, 상세는 갈 자리까지 적는다.
        #expect(denied.note?.count ?? 0 < denied.details?.count ?? 0)
        #expect(denied.details?.contains(SystemSettingsPane.locationServices.displayPath) == true)
    }

    @Test("화면에 실리는 줄은 문장이 아니라 명사구다")
    func screenLinesAreShort() {
        // 권한 넷에 두세 줄씩 붙으면 화면 절반이 글이 되고, 그러면 아무도 읽지 않는다.
        // 전문은 README 와 [설치] 시트가 들고 있다.
        let inputs = [
            input(applyInstalled: false, sudoersInstalled: false),
            input(sudoersInstalled: false),
            input(saveConfigInstalled: false),
            input(saveConfigAcceptsDigest: false),
            input(isAdministrator: false),
            input(location: .denied),
            input(location: .notDetermined),
            input(notifications: .denied),
            input(notifications: .pending),
        ]
        for probe in inputs {
            for item in PermissionReport.resolve(probe).items {
                guard let note = item.note else { continue }
                #expect(note.count <= 40, "화면 줄이 길다(\(note.count)자): \(note)")
                #expect(!note.hasSuffix("."), "문장이다: \(note)")
                for ending in ["습니다", "하세요", "됩니다"] {
                    #expect(!note.contains(ending), "문장이다: \(note)")
                }
            }
        }
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
        // (화면에는 버튼이 있으니 이 상세는 터미널·툴팁 몫이다)
        let location = item(.location, input(location: .denied))
        #expect(location.details?.contains(InstallPaths.appName) == true)
        #expect(location.details?.contains(SystemSettingsPane.locationServices.displayPath) == true)

        let notification = item(.notification, input(notifications: .denied))
        #expect(notification.details?.contains(SystemSettingsPane.notifications.displayPath) == true)
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

    /// 권한 표가 '저장할 수 있다' 고 적는 근거와, 저장이 실제로 막히는 근거가 **같은 물음**이어야 한다.
    ///
    /// 갈라지면 그 자리는 조용하다 — 화면은 '설치됨' 이라 적고 저장은 재설치를 안내하는데,
    /// 재설치할 손잡이는 화면 판정이 내주는 것이라 어디에도 없다 (2026-08-03 실측).
    /// 그래서 관측하는 쪽이 **저장 경로와 같은 함수**를 부르는지 소스로 확인한다.
    @Test("권한 표가 저장 경로와 같은 물음으로 스크립트 버전을 본다")
    func permissionProbeAsksTheSaveQuestion() throws {
        let probe = try source("Sources/ExemWifiSwitcherApp/PermissionProbe.swift")
        #expect(probe.contains("helperAcceptsDigest"), "권한 표가 스크립트 버전을 따로 판정하고 있다")
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
