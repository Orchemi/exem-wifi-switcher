import Foundation
import WifiSwitcherCore

// Phase 1 전환 코어를 손으로 확인하기 위한 최소 CLI.
// 메뉴바 앱(Phase 2)이 쓸 코드와 같은 라이브러리를 호출한다.

let usage = """
사용법: exem-wifi-switcher-cli <명령> [옵션]

명령
  status              현재 네트워크 구성을 읽어 프로필과 대조한다 (읽기 전용)
  profiles            설정에 등록된 프로필 목록을 보여준다
  validate            설정 파일을 검증한다
  apply <프로필>       프로필을 적용한다 (sudo -n 으로 권한 스크립트 호출)
  help                이 도움말

옵션
  --config <경로>      설정 파일 경로 (기본: \(InstallPaths.configFile))
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// `--config <경로>` 를 뽑아내고 나머지 인자를 돌려준다.
func extractConfigPath(from arguments: [String]) -> (path: String, rest: [String]) {
    var path = InstallPaths.configFile
    var rest: [String] = []
    var index = arguments.startIndex
    while index < arguments.endIndex {
        if arguments[index] == "--config", index + 1 < arguments.endIndex {
            path = arguments[index + 1]
            index += 2
        } else {
            rest.append(arguments[index])
            index += 1
        }
    }
    return (path, rest)
}

func loadConfig(_ path: String) -> AppConfig {
    do {
        return try AppConfig.load(from: path)
    } catch {
        fail("\(error)")
    }
}

let allArguments = Array(CommandLine.arguments.dropFirst())
guard let command = allArguments.first else {
    print(usage)
    exit(0)
}

let (configPath, remaining) = extractConfigPath(from: Array(allArguments.dropFirst()))

switch command {

case "help", "-h", "--help":
    print(usage)

case "validate":
    // 판정은 **앱이 쓰는 것과 같은 것**을 쓴다 (`AppConfig.inspect`).
    // 형식만 보고 "유효합니다" 라고 답하면, 예시 그대로인 파일을 두고
    // 앱은 '아직 저장 안 됨' · CLI 는 '유효함' 이라고 서로 다르게 말하게 된다.
    let report = ConfigValidationReport.make(path: configPath)
    if report.isReadyForApp {
        report.lines.forEach { print($0) }
    } else {
        fail(report.lines.joined(separator: "\n"))
    }

case "profiles":
    let config = loadConfig(configPath)
    for profile in config.profiles {
        let marker = profile.name == config.defaultProfile ? "*" : " "
        switch profile.mode {
        case .dhcp:
            print("\(marker) \(profile.name)  DHCP")
        case .manual:
            print("\(marker) \(profile.name)  고정 IP \(profile.ip ?? "-") / \(profile.subnet ?? "-") → \(profile.router ?? "-")")
        }
        if !profile.dns.isEmpty { print("     DNS  \(profile.dns.joined(separator: ", "))") }
        if !profile.ssids.isEmpty { print("     SSID \(profile.ssids.joined(separator: ", "))") }
    }
    print("\n(* 는 기본 프로필)")

case "status":
    let config = loadConfig(configPath)
    let reader = NetworkStateReader(service: config.service)
    do {
        let info = try reader.readInterfaceInfo()
        let dns = reader.readDNSServers()

        let methodText: String
        switch info.configMethod {
        case .manual: methodText = "수동 (고정 IP)"
        case .dhcp: methodText = "자동 (DHCP)"
        case .manualWithDHCPRouter: methodText = "수동 IP + DHCP 라우터"
        case .bootp: methodText = "BOOTP"
        case .unknown(let raw): methodText = "알 수 없음 (\(raw))"
        }

        print("서비스     : \(config.service)")
        print("구성 방식  : \(methodText)")
        print("IP 주소    : \(info.ip?.description ?? "없음")")
        print("서브넷     : \(info.subnet?.description ?? "없음")")
        print("라우터     : \(info.router?.description ?? "없음")")
        // "없음" 과 "읽지 못함" 을 같은 말로 적지 않는다.
        switch dns {
        case .servers(let servers):
            print("DNS        : \(servers.isEmpty ? "설정 없음" : servers.joined(separator: ", "))")
        case .unreadable(let reason):
            print("DNS        : 읽지 못함 — \(reason)")
        }

        let matched = config.profiles.filter { info.conforms(to: $0) }
        if matched.isEmpty {
            print("일치 프로필: 없음")
        } else {
            print("일치 프로필: \(matched.map(\.name).joined(separator: ", "))")
        }
    } catch {
        fail("\(error)")
    }

case "apply":
    guard let profileName = remaining.first else {
        fail("적용할 프로필 이름이 필요합니다.\n\n\(usage)", code: 2)
    }
    let config = loadConfig(configPath)
    guard let profile = config.profile(named: profileName) else {
        fail("설정에 없는 프로필입니다: '\(profileName)'", code: 2)
    }
    do {
        try ApplyCommand.run(profileName: profile.name)
        print("'\(profile.name)' 프로필을 적용했습니다.")
    } catch {
        fail("\(error)")
    }

default:
    fail("알 수 없는 명령입니다: '\(command)'\n\n\(usage)", code: 2)
}
