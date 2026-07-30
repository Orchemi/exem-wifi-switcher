import Foundation
import WifiSwitcherCore

/// 한 번의 관측 결과. 화면이 쓰는 값은 전부 여기 담긴다.
struct Observation: Sendable {
    var config: ConfigStatus
    var interface: InterfaceInfo?
    var interfaceError: String?
    var helperInstalled: Bool
    /// 무암호 sudoers 규칙이 놓여 있는가. 스크립트만 있고 규칙이 없으면 전환할 때마다 암호를 물어 실패한다.
    var sudoersInstalled: Bool
    /// 설정 저장 스크립트가 놓여 있는가. 초기 설정이 끝났는지를 볼 때 함께 본다.
    var saveConfigInstalled: Bool
    /// 위치 권한 상태. 메인 스레드의 `LocationAuthority` 가 본 값을 그대로 들고 다닌다 —
    /// **초기 설정의 필수 항목**이라 메뉴 판정에도 들어간다.
    var location: LocationAuthorizationState
    /// 지금 접속한 Wi-Fi 이름을 읽은 결과 (자동 전환의 판단 근거).
    var ssid: SSIDReading
    /// 현재 설정된 DNS 서버를 읽은 결과. 온보딩이 초안을 만들 때 쓴다.
    /// **"없음" 과 "읽지 못함" 을 구분한다** — 읽지 못한 것을 없음으로 저장하면 이름 해석이 끊긴다.
    var dnsServers: DNSReading
    /// 지금 이름 해석에 실제로 쓰이는 IPv4 리졸버 (`scutil --dns`).
    ///
    /// **`dnsServers` 와 섞지 마라.** 이 값은 수동 지정 값이 아니라 **제안**이다
    /// (DHCP 가 알려준 값이 여기 들어온다). 자동 전환 판정은 이 값을 보지 않는다 —
    /// 제안을 적용 여부 판단에 쓰면 걸지도 않은 프로필을 '이미 적용됨' 으로 볼 수 있다.
    /// 쓰는 곳은 설정 창의 DNS 칸 하나다 (`DNSFieldState`).
    var activeResolvers: [String]
    /// 이 시스템에 있는 네트워크 서비스 이름. 설정 창의 선택 목록이 된다.
    var services: [String]

    /// 아직 아무것도 읽지 못한 상태.
    static let pending = Observation(
        config: .missing(path: InstallPaths.configFile),
        interface: nil,
        interfaceError: nil,
        helperInstalled: false,
        sudoersInstalled: false,
        saveConfigInstalled: false,
        location: .notDetermined,
        ssid: .unavailable("아직 읽지 않았습니다"),
        dnsServers: .unreadable("아직 읽지 않았습니다"),
        activeResolvers: [],
        services: []
    )

    func statusInput(
        action: ActionState,
        autoSwitchEnabled: Bool,
        autoSwitchHold: AutoSwitchHold?,
        notifications: NotificationPermission = .allowed
    ) -> StatusInput {
        StatusInput(
            config: config,
            interface: interface,
            interfaceError: interfaceError,
            helperInstalled: helperInstalled,
            sudoersInstalled: sudoersInstalled,
            saveConfigInstalled: saveConfigInstalled,
            location: location,
            action: action,
            autoSwitchEnabled: autoSwitchEnabled,
            ssid: ssid,
            autoSwitchHold: autoSwitchHold,
            notifications: notifications
        )
    }

    /// 전환 권한 판정. 메뉴가 전환을 잠그는 기준과 **같은 값**이다 (`SwitchingPermission`).
    var switching: SwitchingPermission {
        SwitchingPermission(applyInstalled: helperInstalled, sudoersInstalled: sudoersInstalled)
    }

    /// 자동 전환 판정에 넘길 관측값.
    ///
    /// **DNS 도 함께 넘긴다.** IP·서브넷·라우터만으로 "이미 적용됨" 을 판정하면 사내 DNS 가
    /// 남은 채 밖에서 도는 구성을 정상으로 본다.
    ///
    /// **전환 권한도 스크립트 유무가 아니라 판정으로 넘긴다.** 무암호 규칙이 빠진 상태에서
    /// 시도하면 `sudo -n` 이 그 자리에서 거부한다 — 실패를 쌓을 이유가 없다.
    func autoSwitchContext(isEnabled: Bool, isBusy: Bool) -> AutoSwitchContext {
        AutoSwitchContext(
            isEnabled: isEnabled,
            config: config,
            switching: switching,
            ssid: ssid,
            interface: interface,
            dns: dnsServers,
            isBusy: isBusy
        )
    }

    var readyConfig: AppConfig? {
        if case .ready(let config) = config { return config }
        return nil
    }
}

/// 시스템을 읽어 `Observation` 을 만든다. **읽기만 한다** — 어떤 것도 바꾸지 않는다.
///
/// 프로세스를 띄우므로 메인 스레드에서 부르지 않는다 (`StatusItemController` 가 백그라운드로 보낸다).
struct SystemProbe: Sendable {

    var configPath: String = InstallPaths.configFile
    var ssidReader = WiFiSSIDReader()

    /// - Parameter locationAuthorization: 메인 스레드의 `LocationAuthority` 가 본 권한 상태.
    ///   SSID 를 읽지 못했을 때 그 이유를 가리기 위해 필요하다.
    func read(locationAuthorization: LocationAuthorizationState) -> Observation {
        let configStatus = AppConfig.inspect(path: configPath)
        let services = SystemProbe.availableServices()
        let service: String
        if case .ready(let config) = configStatus {
            service = config.service
        } else {
            service = SystemProbe.preferredService(among: services)
        }

        let reader = NetworkStateReader(service: service)
        var interface: InterfaceInfo?
        var interfaceError: String?
        do {
            interface = try reader.readInterfaceInfo()
        } catch {
            interfaceError = "\(error)"
        }

        return Observation(
            config: configStatus,
            interface: interface,
            interfaceError: interfaceError,
            helperInstalled: FileManager.default.isExecutableFile(atPath: InstallPaths.applyScript),
            // 파일이 놓여 있는지만 본다 — 상태를 보려고 sudo 를 시험 삼아 돌리지 않는다.
            // (sudoers 파일 내용은 root 만 읽을 수 있지만, 있는지 없는지는 확인할 수 있다)
            sudoersInstalled: FileManager.default.fileExists(atPath: InstallPaths.sudoersFile),
            saveConfigInstalled: FileManager.default.isExecutableFile(atPath: InstallPaths.saveConfigScript),
            location: locationAuthorization,
            ssid: ssidReader.read(authorization: locationAuthorization),
            dnsServers: reader.readDNSServers(),
            activeResolvers: reader.readActiveResolvers(),
            services: services
        )
    }

    /// 설정이 아직 없을 때 볼 서비스 이름. Wi-Fi 가 있으면 그것을, 없으면 첫 번째 서비스를 쓴다.
    static func preferredService(among services: [String]) -> String {
        if services.contains("Wi-Fi") { return "Wi-Fi" }
        return services.first ?? "Wi-Fi"
    }

    static func availableServices() -> [String] {
        (try? NetworkStateReader.availableServices()) ?? []
    }
}
