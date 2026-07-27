import Foundation

/// 온보딩 창이 다루는 입력값.
///
/// 화면은 AppKit 이지만 판단은 전부 여기 있다. **검증은 새로 만들지 않고
/// `NetworkProfile.validate()` 를 그대로 쓴다** — 규칙이 두 벌이 되면 반드시 어긋난다.
/// 이 타입이 하는 일은 (1) 문자열을 다듬고 (2) 실패 사유를 어느 칸에 붙일지 정하는 것뿐이다.
public struct ManualProfileDraft: Equatable, Sendable {

    public var ip: String
    public var subnet: String
    public var router: String
    /// 사용자가 적은 원문. 쉼표·공백·줄바꿈 어느 쪽으로 나눠도 받는다.
    public var dns: String

    public init(ip: String = "", subnet: String = "", router: String = "", dns: String = "") {
        self.ip = ip
        self.subnet = subnet
        self.router = router
        self.dns = dns
    }

    /// 현재 구성에서 초안을 만든다.
    ///
    /// **수동 구성이고 세 값이 다 있을 때만** 값을 돌려준다. DHCP 로 돌고 있다면
    /// 지금 쓰는 주소는 빌린 것이라 사내 고정 IP 로 저장할 근거가 없다 — 그때는 nil 이고,
    /// 온보딩은 직접 입력을 받는다.
    ///
    /// DNS 를 **읽지 못했으면 칸을 비워 둔다.** 읽지 못한 것을 "없음" 으로 채워 넣으면
    /// 사용자가 그 빈 값을 자기 설정인 줄 알고 저장한다. 창은 그 사실을 따로 알린다.
    public static func from(_ info: InterfaceInfo, dns: DNSReading) -> ManualProfileDraft? {
        guard info.configMethod == .manual,
              let ip = info.ip, let subnet = info.subnet, let router = info.router
        else { return nil }
        return ManualProfileDraft(
            ip: ip.description,
            subnet: subnet.description,
            router: router.description,
            dns: dns.servers.joined(separator: ", ")
        )
    }
}

/// 온보딩 창의 입력 칸.
public enum DraftField: Equatable, Sendable {
    case ip
    case subnet
    case router
    case dns
    /// 특정 칸으로 좁힐 수 없는 문제
    case form
}

/// 어느 칸이 왜 잘못됐는지. 메시지는 그대로 칸 아래에 보여준다.
public struct DraftIssue: Equatable, Sendable {
    public let field: DraftField
    public let message: String

    public init(field: DraftField, message: String) {
        self.field = field
        self.message = message
    }
}

/// 입력 검증 실패 묶음. 칸별 사유를 잃지 않고 통째로 던진다.
public struct DraftIssues: Error, Equatable, Sendable, CustomStringConvertible {
    public let issues: [DraftIssue]

    public init(_ issues: [DraftIssue]) {
        self.issues = issues
    }

    public func message(for field: DraftField) -> String? {
        issues.first { $0.field == field }?.message
    }

    public var description: String {
        issues.map(\.message).joined(separator: "\n")
    }
}

extension ManualProfileDraft {

    /// 입력값으로 고정 IP 프로필을 만든다. 실패하면 칸별 사유를 전부 돌려준다.
    public func makeProfile(name: String, label: String?, ssids: [String]) -> Result<NetworkProfile, DraftIssues> {
        let ip = ManualProfileDraft.trim(ip)
        let subnet = ManualProfileDraft.trim(subnet)
        let router = ManualProfileDraft.trim(router)

        var issues: [DraftIssue] = []

        // 1) 빈 칸
        if ip.isEmpty { issues.append(DraftIssue(field: .ip, message: "IP 주소를 입력하세요")) }
        if subnet.isEmpty { issues.append(DraftIssue(field: .subnet, message: "서브넷 마스크를 입력하세요")) }
        if router.isEmpty { issues.append(DraftIssue(field: .router, message: "라우터 주소를 입력하세요")) }

        // 2) 형식
        if !ip.isEmpty, IPv4Address(ip) == nil {
            issues.append(DraftIssue(field: .ip, message: ManualProfileDraft.addressHint))
        }
        if !subnet.isEmpty, SubnetMask(subnet) == nil {
            issues.append(DraftIssue(field: .subnet, message: ManualProfileDraft.subnetHint(subnet)))
        }
        if !router.isEmpty, IPv4Address(router) == nil {
            issues.append(DraftIssue(field: .router, message: ManualProfileDraft.addressHint))
        }

        // 3) DNS
        let servers: [String]
        switch ManualProfileDraft.parseDNS(dns) {
        case .success(let parsed):
            servers = parsed
        case .failure(let failure):
            servers = []
            issues.append(contentsOf: failure.issues)
        }

        guard issues.isEmpty else { return .failure(DraftIssues(issues)) }

        // 4) 값끼리의 관계는 Phase 1 의 검증을 그대로 쓴다.
        let profile = NetworkProfile(
            name: name, mode: .manual, ip: ip, subnet: subnet, router: router,
            dns: servers, ssids: ssids, label: label
        )
        let errors = profile.validate()
        guard errors.isEmpty else {
            return .failure(DraftIssues(errors.map { ManualProfileDraft.issue(for: $0, ip: ip, subnet: subnet) }))
        }
        return .success(profile)
    }

    // MARK: - 메시지

    private static let addressHint = "IPv4 주소 형식이 아닙니다. 0~255 숫자 4개를 점으로 잇습니다 (예: 192.0.2.10)"

    /// 고정 IP 프로필에서 DNS 를 비우면 이름 해석이 끊긴다. 왜 필요한지까지 말한다.
    static let emptyDNSHint = "사내에서 쓰는 DNS 서버를 최소 1개 입력하세요. "
        + "고정 IP 는 DHCP 가 아니라 DNS 를 알려줄 주체가 없고, 비워 두면 인터넷 주소가 열리지 않습니다"

    private static func subnetHint(_ value: String) -> String {
        guard IPv4Address(value) != nil else { return addressHint }
        return "서브넷 마스크는 1 비트가 앞쪽에 연속돼야 합니다 (예: 255.255.255.0 / 255.255.0.0)"
    }

    /// Phase 1 검증 실패를 칸별 메시지로 옮긴다.
    private static func issue(for error: ValidationError, ip: String, subnet: String) -> DraftIssue {
        switch error {
        case .routerOutsideSubnet:
            let network = SubnetMask(subnet).flatMap { mask in
                IPv4Address(ip).map { mask.networkAddress(of: $0) }
            }
            let example = network.map { "\($0) 대역" } ?? "IP 와 같은 대역"
            return DraftIssue(field: .router, message: "라우터가 IP·서브넷이 이루는 대역 밖에 있습니다 (\(example) 안이어야 합니다)")
        case .duplicateAddress:
            return DraftIssue(field: .router, message: "IP 주소와 라우터가 같습니다. 라우터는 다른 주소여야 합니다")
        case .reservedAddress(_, let field, let value):
            let message = "\(value) 는 대역의 네트워크 주소이거나 브로드캐스트 주소라 기기에 붙일 수 없습니다"
            return DraftIssue(field: field == "router" ? .router : .ip, message: message)
        case .invalidAddress(_, let field, _):
            switch field {
            case "ip": return DraftIssue(field: .ip, message: addressHint)
            case "subnet": return DraftIssue(field: .subnet, message: subnetHint(subnet))
            case "router": return DraftIssue(field: .router, message: addressHint)
            default: return DraftIssue(field: .dns, message: addressHint)
            }
        case .tooManyDNSServers, .duplicateDNSServer:
            return DraftIssue(field: .dns, message: "\(error)")
        case .missingDNS:
            return DraftIssue(field: .dns, message: emptyDNSHint)
        default:
            return DraftIssue(field: .form, message: "\(error)")
        }
    }

    // MARK: - 다듬기

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDNS(_ text: String) -> Result<[String], DraftIssues> {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        let servers = text.components(separatedBy: separators).filter { !$0.isEmpty }

        if let bad = servers.first(where: { IPv4Address($0) == nil }) {
            return .failure(DraftIssues([DraftIssue(field: .dns, message: "'\(bad)' 는 IPv4 주소가 아닙니다. 쉼표로 구분해 적습니다")]))
        }
        if servers.isEmpty {
            return .failure(DraftIssues([DraftIssue(field: .dns, message: emptyDNSHint)]))
        }
        if servers.count > NetworkProfile.maxDNSServers {
            return .failure(DraftIssues([DraftIssue(
                field: .dns,
                message: "DNS 서버는 최대 \(NetworkProfile.maxDNSServers)개까지 지정할 수 있습니다 (지금 \(servers.count)개)"
            )]))
        }
        var seen = Set<String>()
        if let duplicate = servers.first(where: { !seen.insert($0).inserted }) {
            return .failure(DraftIssues([DraftIssue(field: .dns, message: "'\(duplicate)' 가 중복됩니다")]))
        }
        return .success(servers)
    }
}

/// 온보딩이 만들어내는 설정의 모양.
///
/// 프로필은 둘이면 충분하다 — 사내 고정 IP 하나, 그 밖의 모든 곳에 쓰는 DHCP 하나.
public enum OnboardingSetup {

    public static let officeProfileName = "office"
    public static let officeProfileLabel = "사내 고정 IP"
    public static let autoProfileName = "auto"
    public static let autoProfileLabel = "자동 (DHCP)"

    public static var autoProfile: NetworkProfile {
        NetworkProfile(name: autoProfileName, mode: .dhcp, label: autoProfileLabel)
    }

    /// 온보딩 결과를 설정으로 조립한다.
    ///
    /// 이미 있던 설정은 최대한 보존한다 — SSID 목록(Phase 3 가 채운다)과, 사용자가 손으로
    /// 추가했을 수 있는 다른 프로필은 그대로 둔다. 덮어쓰는 것은 고정 IP 프로필의 주소뿐이다.
    public static func makeConfig(service: String, office: NetworkProfile, existing: AppConfig?) -> AppConfig {
        var profiles = existing?.profiles ?? []

        var office = office
        if let previous = profiles.first(where: { $0.name == office.name }) {
            if office.ssids.isEmpty { office.ssids = previous.ssids }
        }

        if let index = profiles.firstIndex(where: { $0.name == office.name }) {
            profiles[index] = office
        } else {
            profiles.insert(office, at: 0)
        }

        if !profiles.contains(where: { $0.name == autoProfileName }) {
            let insertAt = min(1, profiles.count)
            profiles.insert(autoProfile, at: insertAt)
        }

        // 어느 SSID 에도 걸리지 않을 때는 DHCP 로 둔다. 사외에서 인터넷이 끊기지 않는 쪽이 안전하다.
        var defaultProfile = existing?.defaultProfile ?? autoProfileName
        if !profiles.contains(where: { $0.name == defaultProfile }) {
            defaultProfile = autoProfileName
        }

        return AppConfig(service: service, profiles: profiles, defaultProfile: defaultProfile)
    }
}
