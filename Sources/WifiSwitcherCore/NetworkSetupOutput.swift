import Foundation

/// `networksetup -getinfo` 첫 줄이 알려주는 IPv4 구성 방식.
public enum IPv4ConfigMethod: Equatable, Sendable {
    /// "Manual Configuration"
    case manual
    /// "DHCP Configuration"
    case dhcp
    /// "Manually Using DHCP Router Configuration" — IP 는 수동, 라우터는 DHCP 가 알려준 값
    case manualWithDHCPRouter
    /// "BOOTP Configuration"
    case bootp
    /// 위 어디에도 없는 표기. 원문을 그대로 보관해 진단에 쓴다.
    case unknown(String)

    /// 첫 줄 원문을 구성 방식으로 옮긴다.
    public static func parse(_ line: String) -> IPv4ConfigMethod {
        switch line {
        case "Manual Configuration": return .manual
        case "DHCP Configuration": return .dhcp
        case "Manually Using DHCP Router Configuration": return .manualWithDHCPRouter
        case "BOOTP Configuration": return .bootp
        default: return .unknown(line)
        }
    }
}

/// `networksetup -getinfo <서비스>` 로 읽어낸 현재 구성.
public struct InterfaceInfo: Equatable, Sendable {

    public let configMethod: IPv4ConfigMethod
    public let ip: IPv4Address?
    public let subnet: SubnetMask?
    public let router: IPv4Address?
    /// "Wi-Fi ID" / "Ethernet Address" 줄의 값. 로그·화면에 그대로 내보내지 않는다.
    public let hardwareAddress: String?

    public init(
        configMethod: IPv4ConfigMethod,
        ip: IPv4Address? = nil,
        subnet: SubnetMask? = nil,
        router: IPv4Address? = nil,
        hardwareAddress: String? = nil
    ) {
        self.configMethod = configMethod
        self.ip = ip
        self.subnet = subnet
        self.router = router
        self.hardwareAddress = hardwareAddress
    }

    /// 고정 IP 로 구성돼 있는가.
    public var isManual: Bool {
        configMethod == .manual || configMethod == .manualWithDHCPRouter
    }

    /// IPv4 주소를 실제로 배정받은 상태인가. 미연결이면 false.
    public var hasAddress: Bool { ip != nil }

    /// 현재 IPv4 구성이 프로필과 이미 같은가.
    ///
    /// Phase 3 의 자동 전환이 같은 값을 반복 적용해 네트워크를 흔드는 것을 막는 판정이다.
    ///
    /// **DNS 는 여기서 보지 않는다** — `-getinfo` 출력에 없기 때문이다.
    /// DNS 비교는 `DNSReading.conformance(to:)` 가 맡고, 자동 전환 판정(`AutoSwitchPolicy.decide`)이
    /// 두 결과를 함께 본다. 이 함수만으로 "이미 적용됨" 을 결론짓지 마라 — IP 만 맞고 DNS 는
    /// 다른 상태(부분 적용·다른 프로필의 잔재)를 통과시키게 된다.
    public func conforms(to profile: NetworkProfile) -> Bool {
        switch profile.mode {
        case .dhcp:
            return configMethod == .dhcp
        case .manual:
            guard configMethod == .manual, let expected = profile.manualConfiguration else { return false }
            return ip == expected.ip && subnet == expected.subnet && router == expected.router
        }
    }
}

/// 현재 DNS 설정을 읽은 결과.
///
/// **"설정된 서버가 없다" 와 "읽지 못했다" 는 다른 사실이다.** 둘을 같은 빈 배열로 뭉개면,
/// 조회에 실패한 상태에서 온보딩을 하는 사용자가 빈 DNS 를 자기 값인 줄 알고 저장하게 된다.
/// 고정 IP 프로필에서 그것은 이름 해석이 통째로 끊기는 설정이다.
public enum DNSReading: Equatable, Sendable {
    /// 읽었다. 배열이 비어 있으면 **정말로 설정된 서버가 없다**는 뜻이다.
    case servers([String])
    /// 읽지 못했다. 사유는 그대로 화면에 옮길 수 있다.
    case unreadable(String)

    /// 읽어낸 서버 목록. 읽지 못했으면 빈 배열이므로 `isUnreadable` 과 함께 봐야 한다.
    public var servers: [String] {
        if case .servers(let servers) = self { return servers }
        return []
    }

    public var isUnreadable: Bool {
        if case .unreadable = self { return true }
        return false
    }

    /// 읽지 못한 사유. 읽었으면 nil.
    public var failureReason: String? {
        if case .unreadable(let reason) = self { return reason }
        return nil
    }
}

/// 현재 DNS 가 프로필이 요구하는 것과 같은가.
///
/// **"같다 / 다르다" 만으로는 부족하다.** 읽지 못한 경우를 '다르다' 로 뭉개면 조회가 실패할 때마다
/// 자동 전환이 같은 프로필을 영원히 다시 적용한다. 판정할 수 없다는 것은 그 자체로 하나의 답이다.
public enum DNSConformance: Equatable, Sendable {
    /// 목표와 같다
    case matches
    /// 목표와 다르다 — 아직 적용되지 않았거나, 적용된 뒤 바뀌었다
    case differs
    /// 읽지 못해 판정할 수 없다. **다르다는 뜻이 아니다.**
    case undecidable
}

extension DNSReading {

    /// 지금 걸려 있는 DNS 가 이 프로필이 요구하는 것과 같은가.
    ///
    /// 순서까지 본다. `networksetup -setdnsservers` 는 적은 순서대로 resolver 우선순위를 정하므로,
    /// 순서가 다르면 우리가 요청한 구성이 아니다.
    ///
    /// DHCP 프로필의 `dns` 가 비어 있으면 **수동 지정이 없는 상태**가 목표다
    /// (`-getdnsservers` 는 수동 지정만 보여준다 — DHCP 가 알려준 값은 여기 나오지 않는다).
    public func conformance(to profile: NetworkProfile) -> DNSConformance {
        switch self {
        case .unreadable:
            return .undecidable
        case .servers(let current):
            return current == profile.dns ? .matches : .differs
        }
    }
}

/// `networksetup` 출력 파서. 시스템 호출 없이 문자열만 다루므로 그대로 테스트할 수 있다.
public enum NetworkSetupOutput {

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case commandFailed(String)
        case unrecognizedOutput

        public var description: String {
            switch self {
            case .commandFailed(let message):
                return "networksetup 이 오류를 반환했습니다: \(message)"
            case .unrecognizedOutput:
                return "networksetup 출력에서 구성 방식을 찾지 못했습니다"
            }
        }
    }

    /// `networksetup -getinfo <서비스>` 출력을 파싱한다.
    public static func parseInterfaceInfo(_ text: String) throws -> InterfaceInfo {
        var method: IPv4ConfigMethod?
        var ip: IPv4Address?
        var subnet: SubnetMask?
        var router: IPv4Address?
        var hardwareAddress: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // 서비스 이름이 틀리면 "** Error: ..." 를 낸다.
            if line.hasPrefix("**") {
                throw ParseError.commandFailed(line)
            }

            // 값에 콜론이 들어가는 줄(MAC 주소)이 있으므로 **첫 번째** 콜론에서만 자른다.
            // 그리고 "IPv6 IP address" 가 IPv4 값을 덮어쓰지 않도록 키를 정확히 일치시킨다.
            guard let separator = line.firstIndex(of: ":") else {
                if method == nil, line.hasSuffix("Configuration") {
                    method = IPv4ConfigMethod.parse(line)
                }
                continue
            }

            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value == "none" { continue }

            switch key {
            case "IP address": ip = IPv4Address(value)
            case "Subnet mask": subnet = SubnetMask(value)
            case "Router": router = IPv4Address(value)
            case "Wi-Fi ID", "Ethernet Address", "Wi-Fi Address": hardwareAddress = value
            default: break
            }
        }

        guard let method else { throw ParseError.unrecognizedOutput }
        return InterfaceInfo(
            configMethod: method,
            ip: ip,
            subnet: subnet,
            router: router,
            hardwareAddress: hardwareAddress
        )
    }

    /// `networksetup -getdnsservers <서비스>` 출력에서 IPv4 주소만 골라낸다.
    /// **"없다" 와 "못 읽었다" 를 가르지 않으므로 직접 쓰지 말고 `parseDNSReading` 을 쓴다.**
    static func parseDNSServers(_ text: String) -> [String] {
        var servers: [String] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if IPv4Address(line) != nil { servers.append(line) }
        }
        return servers
    }

    /// `networksetup` 이 "설정된 서버가 없다" 고 할 때 쓰는 문구.
    private static let noDNSServersPhrase = "aren't any DNS Servers"

    /// `networksetup -getdnsservers <서비스>` 의 결과를 **읽었는지 여부까지 포함해** 해석한다.
    ///
    /// 실측 동작(macOS 26):
    ///   - 서버가 있음      → 종료 코드 0 + 주소 한 줄씩
    ///   - 서버가 없음      → 종료 코드 0 + "There aren't any DNS Servers set on <서비스>."
    ///   - 서비스 이름 오류 → 종료 코드 4 + "** Error: …"
    ///
    /// 마지막 경우를 빈 목록으로 뭉개면, 온보딩이 **읽지도 못한 값을 '비어 있음' 으로 저장**하게 된다.
    public static func parseDNSReading(output: String, exitCode: Int32) -> DNSReading {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard exitCode == 0 else {
            let detail = trimmed.split(separator: "\n").last.map(String.init) ?? "종료 코드 \(exitCode)"
            return .unreadable(detail.trimmingCharacters(in: .whitespaces))
        }
        if trimmed.contains(noDNSServersPhrase) {
            return .servers([])
        }
        let servers = parseDNSServers(output)
        guard !servers.isEmpty else {
            return .unreadable("networksetup 출력을 해석하지 못했습니다")
        }
        return .servers(servers)
    }

    /// `networksetup -listallnetworkservices` 출력을 파싱한다.
    /// 첫 줄은 안내 문구이고, 비활성 서비스는 이름 앞에 `*` 가 붙는다.
    public static func parseNetworkServices(_ text: String) -> [String] {
        var services: [String] = []
        for (index, rawLine) in text.split(separator: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if index == 0 && line.hasPrefix("An asterisk") { continue }
            services.append(line.hasPrefix("*") ? String(line.dropFirst()) : line)
        }
        return services
    }
}
