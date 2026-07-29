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
    /// 이 프로필을 쓸 Wi-Fi 이름.
    ///
    /// **설정 창에서 등록하는 것은 하나다** — 게스트망은 개방망이라 고정 IP 를 쓸 이유가 없다.
    /// 여기서 쉼표를 계속 받아들이는 것은 설정 파일(`ssids`)이 배열이기 때문이다.
    /// 화면만 하나로 좁히고 구조는 남겨 둔다 — 다시 필요해질 때 파일 형식을 깨지 않으려고.
    ///
    /// **이 값이 비면 자동 전환이 이 프로필을 고르지 못한다** — 어느 Wi-Fi 에서 쓸지 모르니
    /// 기본 프로필(DHCP)로 떨어진다. 값은 다 채워 놓고 이 칸만 비면, 사내에 앉아 있는데
    /// 자동 전환이 고정 IP 를 DHCP 로 되돌리는 일이 벌어진다.
    public var ssids: String

    public init(ip: String = "", subnet: String = "", router: String = "", dns: String = "", ssids: String = "") {
        self.ip = ip
        self.subnet = subnet
        self.router = router
        self.dns = dns
        self.ssids = ssids
    }

    /// 현재 구성에서 초안을 만든다.
    ///
    /// **수동 구성이고 세 값이 다 있을 때만** 값을 돌려준다. DHCP 로 돌고 있다면
    /// 지금 쓰는 주소는 빌린 것이라 사내 고정 IP 로 저장할 근거가 없다 — 그때는 nil 이고,
    /// 온보딩은 직접 입력을 받는다.
    ///
    /// DNS 를 **읽지 못했으면 칸을 비워 둔다.** 읽지 못한 것을 "없음" 으로 채워 넣으면
    /// 사용자가 그 빈 값을 자기 설정인 줄 알고 저장한다. 창은 그 사실을 따로 알린다.
    ///
    /// - Parameter ssid: 지금 접속한 Wi-Fi 이름. **수동 구성일 때만** 초안에 넣는다.
    ///   지금 이 자리에서 고정 IP 로 돌고 있다는 것은 여기가 그 프로필을 쓰는 자리라는 뜻이다.
    ///   (DHCP 로 도는 자리에서 지금 Wi-Fi 이름을 넣으면 집·카페 이름이 사내 프로필에 박힌다 —
    ///   그 순간 그 자리에서 사내 고정 IP 가 걸린다. 읽지 못했을 때도 마찬가지로 비워 둔다)
    public static func from(_ info: InterfaceInfo, dns: DNSReading, ssid: SSIDReading) -> ManualProfileDraft? {
        guard info.configMethod == .manual,
              let ip = info.ip, let subnet = info.subnet, let router = info.router
        else { return nil }
        return ManualProfileDraft(
            ip: ip.description,
            subnet: subnet.description,
            router: router.description,
            dns: dns.servers.joined(separator: ", "),
            ssids: ssid.name ?? ""
        )
    }

    /// 칸이 전부 비어 있는가. **형식은 보지 않는다** — 무엇이든 적혀 있는지만 본다.
    ///
    /// 설정 창 머리말이 이것으로 갈린다: 값이 하나라도 있으면 '아직 저장 안 됨' 을 말해야 하고,
    /// 하나도 없으면 아직 채울 것이 없다는 안내를 해야 한다.
    public var isEmpty: Bool {
        [ip, subnet, router, dns, ssids].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 저장을 시도할 수 있는가. **형식은 보지 않는다** — 빈 칸이 있는지만 본다.
    ///
    /// 사외에서 처음 여는 사람은 다섯 칸을 다 비운 채로 마주한다. 그 자리에서 [저장] 을
    /// 누르면 칸마다 오류가 붙는데, 그것은 **틀린 값을 적었을 때 하는 말**이지 아직 아무것도
    /// 적지 않은 사람에게 할 말이 아니다. 누를 수 없게 해 두고 머리말이 언제 채워지는지 말한다.
    ///
    /// **Wi-Fi 이름은 여기 넣지 않는다.** 없어도 프로필은 성립하고(메뉴에서 골라 쓰는 길),
    /// 없으면 자동 전환만 걸리지 않는다 — 그 사실은 초기 설정 판정(`SetupChecklist`)이 따로 말한다.
    public var hasRequiredValues: Bool {
        [ip, subnet, router, dns].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 저장된 값과 견주어 **바뀐 것이 있는가.**
    ///
    /// [저장]은 이것과 `hasRequiredValues` 가 **둘 다** 설 때만 눌린다. 하나만 보면
    /// 방금 저장하고도 버튼이 살아 있어(누를 이유가 없는데 눌리는 상태) 무엇이 남았는지
    /// 버튼으로는 알 수 없게 된다.
    ///
    /// **기준은 창을 열었을 때의 값이 아니라 저장된 설정이다.** 창을 열면 사내 구성을 읽어
    /// 빈 칸이 저절로 차는데, 그 값은 **아직 저장되지 않은 값**이라 바뀐 것으로 봐야 한다.
    /// 열었을 때를 기준으로 잡으면 자동으로 채워진 직후가 '바뀐 것 없음' 이 되어,
    /// 저장을 놓치는 그 문제가 그대로 되살아난다. 저장된 것이 없으면 기준은 빈 값이다.
    public func isDirty(comparedTo saved: ManualProfileDraft?) -> Bool {
        !matches(saved ?? ManualProfileDraft())
    }

    /// 표기가 아니라 **뜻으로** 같은가.
    ///
    /// 앞뒤 공백, 쉼표 주변 공백 같은 차이로 '바뀌었다' 고 하면 버튼이 거짓말을 한다 —
    /// 저장할 것이 없는데 눌리고, 누르면 같은 값을 다시 쓴다.
    public func matches(_ other: ManualProfileDraft) -> Bool {
        ManualProfileDraft.trim(ip) == ManualProfileDraft.trim(other.ip)
            && ManualProfileDraft.trim(subnet) == ManualProfileDraft.trim(other.subnet)
            && ManualProfileDraft.trim(router) == ManualProfileDraft.trim(other.router)
            && dnsList == other.dnsList
            && ssidList == other.ssidList
    }

    /// 적힌 DNS 서버 목록. **검증하지 않는다** — 표기 차이를 걷어내고 견주기 위한 것이다.
    /// 나누는 기준은 저장할 때 쓰는 것과 같다 (`parseDNS`).
    public var dnsList: [String] {
        dns.components(separatedBy: ManualProfileDraft.dnsSeparators).filter { !$0.isEmpty }
    }

    static let dnsSeparators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)

    /// 비어 있는 칸만 상대의 값으로 채운 초안. **사람이 적어 둔 것은 덮지 않는다.**
    ///
    /// 창을 열어 둔 채 사내 Wi-Fi 에 붙는 순간에 쓴다 — 그때 지금 구성을 읽어 빈 칸이 찬다.
    public func adopting(_ other: ManualProfileDraft) -> ManualProfileDraft {
        ManualProfileDraft(
            ip: ip.isEmpty ? other.ip : ip,
            subnet: subnet.isEmpty ? other.subnet : subnet,
            router: router.isEmpty ? other.router : router,
            dns: dns.isEmpty ? other.dns : dns,
            ssids: ssids.isEmpty ? other.ssids : ssids
        )
    }

    /// 저장할 Wi-Fi 이름 목록. 쉼표로 끊고 앞뒤 공백만 턴다.
    ///
    /// **공백으로 끊지 않는다** — SSID 에는 공백이 들어갈 수 있어서(`OFFICE WIFI`)
    /// DNS 처럼 나누면 이름 하나가 둘로 쪼개진다.
    public var ssidList: [String] {
        ssids.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 온보딩 창의 입력 칸.
public enum DraftField: Equatable, Sendable {
    case ip
    case subnet
    case router
    case dns
    case ssids
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
    ///
    /// Wi-Fi 이름도 **초안이 들고 있는 값**을 쓴다 — 화면이 채운 칸과 저장되는 값이
    /// 갈라질 자리를 만들지 않는다.
    public func makeProfile(name: String, label: String?) -> Result<NetworkProfile, DraftIssues> {
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
        //    Wi-Fi 이름 규칙(길이·제어문자·중복)도 여기서 함께 걸린다 — 따로 만들지 않는다.
        let profile = NetworkProfile(
            name: name, mode: .manual, ip: ip, subnet: subnet, router: router,
            dns: servers, ssids: ssidList, label: label
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
        case .invalidSSID(_, let reason):
            return DraftIssue(field: .ssids, message: "Wi-Fi 이름을 쓸 수 없습니다 — \(reason)")
        default:
            return DraftIssue(field: .form, message: "\(error)")
        }
    }

    // MARK: - 다듬기

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDNS(_ text: String) -> Result<[String], DraftIssues> {
        let servers = text.components(separatedBy: dnsSeparators).filter { !$0.isEmpty }

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
    /// 이미 있던 설정에서 **사용자가 손으로 추가했을 수 있는 다른 프로필은 그대로 둔다.**
    /// 덮어쓰는 것은 고정 IP 프로필 하나뿐이다.
    ///
    /// **고정 IP 프로필은 넘어온 값을 그대로 쓴다 — Wi-Fi 이름도 마찬가지다.**
    /// 예전에는 넘어온 목록이 비면 옛 목록을 되살렸다. 화면에 그 칸이 없던 시절의 보호막인데,
    /// 이제 칸이 있으므로 그 되살리기는 **사용자가 지운 이름을 되돌려 놓는 짓**이 된다.
    /// 지우고 저장했는데 그대로면 그것은 고장이다.
    public static func makeConfig(service: String, office: NetworkProfile, existing: AppConfig?) -> AppConfig {
        var profiles = existing?.profiles ?? []

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
