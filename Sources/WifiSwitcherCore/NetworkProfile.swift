import Foundation

/// 프로필이 지정하는 IPv4 구성 방식.
public enum ProfileMode: String, Codable, Sendable {
    /// 고정 IP (`networksetup -setmanual`)
    case manual
    /// 자동 (`networksetup -setdhcp`)
    case dhcp
}

/// 하나의 네트워크 구성 프로필.
///
/// 사내 Wi-Fi 처럼 고정 IP 가 필요한 곳은 `manual`, 그 외에는 `dhcp` 로 둔다.
/// `ssids` 에 적힌 Wi-Fi 이름에 접속하면 이 프로필이 선택된다(Phase 3).
public struct NetworkProfile: Codable, Equatable, Sendable {

    public var name: String
    public var mode: ProfileMode
    public var ip: String?
    public var subnet: String?
    public var router: String?
    public var dns: [String]
    public var ssids: [String]
    /// 화면에 보여줄 이름. `name` 은 root 스크립트에 넘기는 인자라 ASCII 로 좁혀 두었으므로,
    /// 사람이 읽을 이름은 여기에 따로 담는다. 없으면 `name` 을 그대로 쓴다.
    public var label: String?

    public init(
        name: String,
        mode: ProfileMode,
        ip: String? = nil,
        subnet: String? = nil,
        router: String? = nil,
        dns: [String] = [],
        ssids: [String] = [],
        label: String? = nil
    ) {
        self.name = name
        self.mode = mode
        self.ip = ip
        self.subnet = subnet
        self.router = router
        self.dns = dns
        self.ssids = ssids
        self.label = label
    }

    /// 메뉴·창에 쓰는 이름.
    public var displayName: String {
        guard let label, !label.isEmpty else { return name }
        return label
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, ip, subnet, router, dns, ssids, label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.ip = try container.decodeIfPresent(String.self, forKey: .ip)
        self.subnet = try container.decodeIfPresent(String.self, forKey: .subnet)
        self.router = try container.decodeIfPresent(String.self, forKey: .router)
        self.dns = try container.decodeIfPresent([String].self, forKey: .dns) ?? []
        self.ssids = try container.decodeIfPresent([String].self, forKey: .ssids) ?? []
        // mode 가 생략되면 고정 IP 값의 유무로 추론한다. 추론 결과와 값이 어긋나면 validate() 가 잡는다.
        if let mode = try container.decodeIfPresent(ProfileMode.self, forKey: .mode) {
            self.mode = mode
        } else {
            self.mode = (self.ip == nil && self.subnet == nil && self.router == nil) ? .dhcp : .manual
        }
    }
}

/// 프로필·설정 검증 실패 사유. 메시지는 그대로 사용자에게 보여줄 수 있다.
public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case invalidProfileName(String)
    case invalidLabel(profile: String, reason: String)
    case missingField(profile: String, field: String)
    case missingDNS(profile: String)
    case unexpectedField(profile: String, field: String)
    case invalidAddress(profile: String, field: String, value: String)
    case routerOutsideSubnet(profile: String)
    case reservedAddress(profile: String, field: String, value: String)
    case duplicateAddress(profile: String)
    case tooManyDNSServers(profile: String, count: Int)
    case duplicateDNSServer(profile: String, value: String)
    case invalidSSID(profile: String, reason: String)
    case duplicateProfileName(String)
    case duplicateSSID(String)
    case unknownDefaultProfile(String)
    case emptyProfileList
    case invalidServiceName(String)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .invalidProfileName(let name):
            return "프로필 이름이 규칙에 맞지 않습니다: '\(name)' "
                + "(영문·숫자로 시작, 이후 영문·숫자·_·- 만, 최대 \(ProfileName.maxLength)자)"
        case .invalidLabel(let profile, let reason):
            return "'\(profile)' 프로필의 표시 이름이 올바르지 않습니다: \(reason)"
        case .missingField(let profile, let field):
            return "'\(profile)' 프로필에 \(field) 값이 없습니다 (고정 IP 프로필의 필수 항목)"
        case .missingDNS(let profile):
            return "'\(profile)' 은 고정 IP 프로필이라 DNS 서버를 최소 1개 적어야 합니다. "
                + "DHCP 가 아니므로 알려줄 주체가 없고, 비워 두면 이름 해석이 통째로 끊깁니다"
        case .unexpectedField(let profile, let field):
            return "'\(profile)' 은 DHCP 프로필인데 \(field) 값이 들어 있습니다"
        case .invalidAddress(let profile, let field, let value):
            return "'\(profile)' 프로필의 \(field) 형식이 올바르지 않습니다: '\(value)'"
        case .routerOutsideSubnet(let profile):
            return "'\(profile)' 프로필의 라우터가 IP·서브넷이 이루는 대역 밖에 있습니다"
        case .reservedAddress(let profile, let field, let value):
            return "'\(profile)' 프로필의 \(field)('\(value)')는 네트워크·브로드캐스트 주소라 사용할 수 없습니다"
        case .duplicateAddress(let profile):
            return "'\(profile)' 프로필의 IP 와 라우터가 같은 주소입니다"
        case .tooManyDNSServers(let profile, let count):
            return "'\(profile)' 프로필의 DNS 서버가 너무 많습니다 (\(count)개, 최대 \(NetworkProfile.maxDNSServers)개)"
        case .duplicateDNSServer(let profile, let value):
            return "'\(profile)' 프로필에 DNS 서버 '\(value)' 가 중복 지정됐습니다"
        case .invalidSSID(let profile, let reason):
            return "'\(profile)' 프로필의 Wi-Fi 이름이 올바르지 않습니다: \(reason)"
        case .duplicateProfileName(let name):
            return "프로필 이름 '\(name)' 이 중복됩니다"
        case .duplicateSSID(let ssid):
            return "Wi-Fi 이름 '\(ssid)' 이 여러 프로필에 지정돼 어느 쪽을 쓸지 알 수 없습니다"
        case .unknownDefaultProfile(let name):
            return "기본 프로필 '\(name)' 이 프로필 목록에 없습니다"
        case .emptyProfileList:
            return "프로필이 하나도 없습니다"
        case .invalidServiceName(let name):
            return "네트워크 서비스 이름이 올바르지 않습니다: '\(name)'"
        case .unsupportedVersion(let version):
            return "지원하지 않는 설정 파일 버전입니다: \(version)"
        }
    }
}

extension NetworkProfile {

    /// DNS 서버 개수 상한. root 스크립트에 넘길 인자 수를 유한하게 묶어둔다.
    public static let maxDNSServers = 8

    /// SSID 는 802.11 규격상 최대 32 옥텟이다.
    public static let maxSSIDByteLength = 32

    /// 표시 이름 상한. 메뉴 한 줄에 들어가는 길이로 묶는다.
    public static let maxLabelLength = 24

    /// 파싱된 고정 IP 구성. `mode == .manual` 이고 검증을 통과했을 때만 값이 있다.
    public var manualConfiguration: (ip: IPv4Address, subnet: SubnetMask, router: IPv4Address)? {
        guard mode == .manual,
              let ipText = ip, let address = IPv4Address(ipText),
              let subnetText = subnet, let mask = SubnetMask(subnetText),
              let routerText = router, let gateway = IPv4Address(routerText)
        else { return nil }
        return (address, mask, gateway)
    }

    /// 이 프로필 하나만 놓고 볼 수 있는 모든 검증. 문제가 없으면 빈 배열.
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        if !ProfileName.isValid(name) {
            errors.append(.invalidProfileName(name))
        }
        errors.append(contentsOf: validateLabel())

        switch mode {
        case .manual:
            errors.append(contentsOf: validateManualFields())
            // 고정 IP 에는 DNS 를 알려줄 DHCP 서버가 없다. 비워 두면 resolver 가 0개가 되고
            // `apply` 가 시스템 DNS 를 지운다 — 사용자에게는 "인터넷이 안 된다" 로 보인다.
            if dns.isEmpty {
                errors.append(.missingDNS(profile: name))
            }
        case .dhcp:
            // DHCP 프로필에 고정 IP 값이 남아 있으면 "적용된 줄 알았는데 아니었다" 를 만든다. 거부한다.
            if ip != nil { errors.append(.unexpectedField(profile: name, field: "ip")) }
            if subnet != nil { errors.append(.unexpectedField(profile: name, field: "subnet")) }
            if router != nil { errors.append(.unexpectedField(profile: name, field: "router")) }
        }

        errors.append(contentsOf: validateDNS())
        errors.append(contentsOf: validateSSIDs())
        return errors
    }

    private func validateManualFields() -> [ValidationError] {
        var errors: [ValidationError] = []

        guard let ipText = ip else { return [.missingField(profile: name, field: "ip")] }
        guard let subnetText = subnet else { return [.missingField(profile: name, field: "subnet")] }
        guard let routerText = router else { return [.missingField(profile: name, field: "router")] }

        guard let address = IPv4Address(ipText) else {
            return [.invalidAddress(profile: name, field: "ip", value: ipText)]
        }
        guard let mask = SubnetMask(subnetText) else {
            return [.invalidAddress(profile: name, field: "subnet", value: subnetText)]
        }
        guard let gateway = IPv4Address(routerText) else {
            return [.invalidAddress(profile: name, field: "router", value: routerText)]
        }

        if !mask.isAssignableHost(address) {
            errors.append(.reservedAddress(profile: name, field: "ip", value: ipText))
        }
        if !mask.isAssignableHost(gateway) {
            errors.append(.reservedAddress(profile: name, field: "router", value: routerText))
        }
        if !mask.isSameSubnet(address, gateway) {
            errors.append(.routerOutsideSubnet(profile: name))
        }
        if address == gateway {
            errors.append(.duplicateAddress(profile: name))
        }
        return errors
    }

    private func validateLabel() -> [ValidationError] {
        guard let label else { return [] }
        if label.isEmpty {
            return [.invalidLabel(profile: name, reason: "빈 값")]
        }
        if label.count > Self.maxLabelLength {
            return [.invalidLabel(profile: name, reason: "\(Self.maxLabelLength)자를 넘습니다")]
        }
        if label.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return [.invalidLabel(profile: name, reason: "제어 문자가 들어 있습니다")]
        }
        return []
    }

    private func validateDNS() -> [ValidationError] {
        var errors: [ValidationError] = []
        if dns.count > Self.maxDNSServers {
            errors.append(.tooManyDNSServers(profile: name, count: dns.count))
        }
        var seen = Set<String>()
        for server in dns {
            guard IPv4Address(server) != nil else {
                errors.append(.invalidAddress(profile: name, field: "dns", value: server))
                continue
            }
            if !seen.insert(server).inserted {
                errors.append(.duplicateDNSServer(profile: name, value: server))
            }
        }
        return errors
    }

    private func validateSSIDs() -> [ValidationError] {
        var errors: [ValidationError] = []
        var seen = Set<String>()
        for ssid in ssids {
            if ssid.isEmpty {
                errors.append(.invalidSSID(profile: name, reason: "빈 값"))
            } else if ssid.utf8.count > Self.maxSSIDByteLength {
                errors.append(.invalidSSID(profile: name, reason: "'\(ssid)' 이 32바이트를 넘습니다"))
            } else if ssid.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                errors.append(.invalidSSID(profile: name, reason: "제어 문자가 들어 있습니다"))
            } else if !seen.insert(ssid).inserted {
                errors.append(.invalidSSID(profile: name, reason: "'\(ssid)' 이 중복됩니다"))
            }
        }
        return errors
    }
}
