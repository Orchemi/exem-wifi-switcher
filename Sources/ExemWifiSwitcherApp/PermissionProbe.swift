import Foundation
import UserNotifications
import WifiSwitcherCore

/// 권한 판정에 필요한 값을 시스템에서 읽는다. **읽기만 한다** — 승인 창을 띄우지 않고,
/// 어떤 것도 설치하거나 바꾸지 않는다.
///
/// 판정은 여기 없다. 읽은 값을 `PermissionReport.resolve` 에 넘길 뿐이다
/// (설정 창과 `--diagnose` 가 같은 답을 내는 이유).
enum PermissionProbe {

    /// 설정 창에서 부르는 길. 파일 확인과 `id -Gn` 이 메인 스레드를 잡지 않게 한다.
    ///
    /// - Parameter wifiNameVisible: 지금 Wi-Fi 이름을 읽고 있는가. 위치 권한 판정의 **물증**이다
    ///   (`PermissionInput.wifiNameVisible` 참조).
    static func read(
        location: LocationAuthorizationState,
        wifiNameVisible: Bool
    ) async -> PermissionInput {
        let install = await Task.detached(priority: .userInitiated) { installState() }.value
        let notifications = await notificationPermission()
        return PermissionInput(
            applyInstalled: install.apply,
            sudoersInstalled: install.sudoers,
            saveConfigInstalled: install.saveConfig,
            saveConfigAcceptsDigest: install.saveConfigAcceptsDigest,
            isAdministrator: install.administrator,
            installerAvailable: install.installer,
            location: location,
            wifiNameVisible: wifiNameVisible,
            notifications: notifications
        )
    }

    /// `--diagnose` 에서 부르는 길. 한 번 찍고 끝나는 경로라 메인을 잠깐 붙잡아도 잃을 것이 없다
    /// (아직 실행 루프도 돌지 않는다).
    static func readBlocking(
        location: LocationAuthorizationState,
        wifiNameVisible: Bool
    ) -> PermissionInput {
        let install = installState()
        return PermissionInput(
            applyInstalled: install.apply,
            sudoersInstalled: install.sudoers,
            saveConfigInstalled: install.saveConfig,
            saveConfigAcceptsDigest: install.saveConfigAcceptsDigest,
            isAdministrator: install.administrator,
            installerAvailable: install.installer,
            location: location,
            wifiNameVisible: wifiNameVisible,
            notifications: notificationPermissionBlocking()
        )
    }

    // MARK: - 설치 상태

    /// 파일이 놓여 있는지만 본다. `sudo` 를 시험 삼아 실행하지 않는다 —
    /// 상태를 보려고 권한 동작을 실제로 돌리는 것은 진단이 할 일이 아니다.
    ///
    /// **`save-config --capabilities` 하나는 예외다.** 그것은 권한 동작이 아니라 질문이다 —
    /// root 가 필요 없고 아무것도 건드리지 않으며, 저장 경로가 인증 창을 띄우기 전에 묻는
    /// 바로 그 물음이다 (`ConfigInstaller.helperAcceptsDigest`). 이 답이 없으면 권한 표는
    /// 예전 버전이 깔린 상태를 '설치됨' 으로 적고, 저장은 재설치하라며 막는다.
    ///
    /// **값은 캐시하지 않는다.** 이 자리는 이미 갱신마다 `id -Gn` 을 띄우는데,
    /// 같은 기계에서 20회 반복 측정하면 `--capabilities` 가 그보다 오히려 싸다
    /// (3.6ms 대 4.6ms, 2026-08-03 실측). 캐시를 두면 앱 밖에서 재설치한 사실을
    /// 알아채지 못하는 쪽이 더 비싼 문제가 된다.
    private static func installState()
        -> (apply: Bool, sudoers: Bool, saveConfig: Bool, saveConfigAcceptsDigest: Bool,
            administrator: Bool, installer: Bool)
    {
        let manager = FileManager.default
        let saveConfig = manager.isExecutableFile(atPath: InstallPaths.saveConfigScript)
        return (
            apply: manager.isExecutableFile(atPath: InstallPaths.applyScript),
            // 파일 내용은 root 만 읽을 수 있지만(0440), 있는지 없는지는 확인할 수 있다.
            sudoers: manager.fileExists(atPath: InstallPaths.sudoersFile),
            saveConfig: saveConfig,
            // 없는 파일에는 묻지 않는다 — 답이 뻔한 물음에 프로세스를 하나 더 띄우지 않는다.
            saveConfigAcceptsDigest: saveConfig
                && ConfigInstaller.helperAcceptsDigest(InstallPaths.saveConfigScript),
            administrator: PrivilegedShell.currentUserIsAdministrator(),
            installer: bundledInstallerAvailable()
        )
    }

    /// 번들이 설치 스크립트를 품고 있는가. `swift run` 으로 띄운 실행 파일에는 없다.
    static func bundledInstallerAvailable() -> Bool {
        let manager = FileManager.default
        return [InstallPaths.installScriptName, InstallPaths.uninstallScriptName].allSatisfy {
            manager.isExecutableFile(
                atPath: InstallPaths.bundledScript($0, inBundleAt: Bundle.main.bundlePath)
            )
        }
    }

    // MARK: - 알림 권한

    /// 권한을 **묻지 않고 지금 상태만 읽는다.** 점검이 승인 창을 띄우면 안 된다.
    static func notificationPermission() async -> NotificationPermission {
        guard isBundled else { return .unavailable }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return map(status)
    }

    private static func notificationPermissionBlocking() -> NotificationPermission {
        guard isBundled else { return .unavailable }
        final class Box: @unchecked Sendable {
            var value: UNAuthorizationStatus = .notDetermined
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        // **`Task { }` 를 쓰면 안 된다** — 이 자리에서 만든 작업은 메인 액터에 격리되는데,
        // 아래에서 메인 스레드를 붙잡고 기다리므로 서로를 기다리는 교착이 된다.
        Task.detached {
            box.value = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            done.signal()
        }
        done.wait()
        return map(box.value)
    }

    /// `UNUserNotificationCenter.current()` 는 번들 밖(맨 실행 파일)에서 부르면 프로세스가 죽는다.
    private static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .pending
        @unknown default: return .pending
        }
    }
}
