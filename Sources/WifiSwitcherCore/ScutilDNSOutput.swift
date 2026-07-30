import Foundation

/// `scutil --dns` 출력에서 **지금 이름 해석에 실제로 쓰이는 IPv4 리졸버**를 골라낸다.
///
/// 왜 이 창이 하나 더 필요한가.
///
/// `networksetup -getdnsservers` 는 **수동으로 지정된 값만** 돌려준다. DHCP 가 알려준 DNS 로
/// 이름 해석이 잘 되고 있어도 그 명령은 "없음" 이라고 답한다. 게다가 이 도구는 DHCP 프로필을
/// 걸 때마다 수동 지정을 지운다 (`scripts/apply` 의 `-setdnsservers … Empty`). 그래서 사외에
/// 한 번 다녀오면 사내 DNS 값은 시스템에 남아 있지 않고, 설정 창의 DNS 칸만 비어 있게 된다.
/// 사용자에게는 값이 사라진 것으로 보이고, 무엇을 다시 넣어야 하는지 알 방법이 없다.
///
/// `scutil --dns` 는 DHCP 로 받은 것까지 포함해 지금 쓰이는 리졸버를 보여주므로 그 자리를 메운다.
/// **읽기 전용이다. 이 파일은 어떤 것도 바꾸지 않는다.**
public enum ScutilDNSOutput {

    /// 제안하는 최대 개수. 프로필이 받는 상한과 같은 값을 쓴다 (더 제안해도 저장에서 거부된다).
    public static let maxServers = NetworkProfile.maxDNSServers

    /// 한 `resolver #N` 블록에서 우리가 보는 것.
    private struct Resolver {
        var nameservers: [String] = []
        /// `domain : example.` 줄이 있는가. 이 리졸버는 그 도메인에만 쓰인다.
        var isDomainScoped = false
        /// `flags : Supplemental, …` — 보조 리졸버. 일반 이름 해석에 쓰이지 않는다.
        var isSupplemental = false
        /// `options : mdns` — 로컬 이름(`*.local`) 전용.
        var isMulticast = false

        /// 일반 이름 해석을 맡는 리졸버인가.
        var isDefault: Bool { !isDomainScoped && !isSupplemental && !isMulticast }
    }

    /// 지금 쓰이는 IPv4 리졸버 목록. 읽어낸 것이 없으면 빈 배열이다.
    ///
    /// 고르는 기준
    ///
    ///   1. 앞쪽 `DNS configuration` 절의 **일반 리졸버**만 본다. 뒤쪽
    ///      `DNS configuration (for scoped queries)` 절은 인터페이스별 사본이고,
    ///      `domain` · `Supplemental` · `mdns` 가 붙은 블록은 특정 도메인에만 쓰인다.
    ///      그것을 그대로 제안하면 VPN 이나 로컬 프록시의 리졸버가 사내 프로필에 박힌다
    ///   2. 일반 리졸버가 하나도 없으면 출력 전체의 `nameserver` 줄로 물러선다.
    ///      틀린 제안이 될 수 있지만, 아무것도 못 주는 것보다는 확인할 거리가 있는 편이 낫다
    ///
    /// 걸러내는 것
    ///
    ///   - **IPv6** — 설정 스키마도 `apply` 의 검증도 IPv4 만 받는다
    ///   - **루프백(`127.0.0.0/8`)** — mDNSResponder 나 로컬 프록시가 잡힌다.
    ///     그 값을 프로필에 박으면 그 기기 밖에서는 뜻이 없고, 사내에서 이름 해석이 끊긴다
    ///   - **중복** — 같은 서버가 여러 절·여러 블록에 나온다. **순서는 그대로 둔다**
    ///     (`networksetup -setdnsservers` 는 적은 순서대로 우선순위를 정한다)
    ///   - **상한을 넘는 것** — 앞에서부터 `maxServers` 개까지만 남긴다
    public static func activeResolvers(_ text: String) -> [String] {
        let resolvers = parseResolvers(text)

        let preferred = sanitize(resolvers.primary.filter(\.isDefault).flatMap(\.nameservers))
        if !preferred.isEmpty { return preferred }

        return sanitize((resolvers.primary + resolvers.scoped).flatMap(\.nameservers))
    }

    /// IPv4 주소만, 루프백을 뺀 채, 순서를 지키며 중복 없이, 상한까지.
    static func sanitize(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var servers: [String] = []
        for candidate in candidates {
            guard let address = IPv4Address(candidate) else { continue }
            guard !isLoopback(address) else { continue }
            guard seen.insert(address.description).inserted else { continue }
            servers.append(address.description)
            if servers.count == maxServers { break }
        }
        return servers
    }

    /// `127.0.0.0/8` 인가.
    private static func isLoopback(_ address: IPv4Address) -> Bool {
        address.rawValue >> 24 == 127
    }

    /// 출력을 두 절로 나눠 리졸버 블록을 모은다.
    ///
    /// 실측한 모양 (macOS 26)
    ///
    /// ```
    /// DNS configuration
    ///
    /// resolver #1
    ///   search domain[0] : example.
    ///   nameserver[0] : 192.0.2.53
    ///   flags    : Request A records
    ///   order    : 200000
    ///
    /// DNS configuration (for scoped queries)
    ///
    /// resolver #1
    ///   nameserver[0] : 192.0.2.53
    ///   if_index : 15 (en0)
    /// ```
    private static func parseResolvers(_ text: String) -> (primary: [Resolver], scoped: [Resolver]) {
        var primary: [Resolver] = []
        var scoped: [Resolver] = []
        var isScopedSection = false
        var current: Resolver?

        func flush() {
            guard let resolver = current, !resolver.nameservers.isEmpty else {
                current = nil
                return
            }
            if isScopedSection { scoped.append(resolver) } else { primary.append(resolver) }
            current = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("DNS configuration") {
                flush()
                // 절 이름에 "scoped" 가 들어가는 순간부터 뒤쪽 절이다.
                isScopedSection = line.contains("scoped")
                continue
            }
            if line.hasPrefix("resolver #") {
                flush()
                current = Resolver()
                continue
            }
            guard current != nil, let separator = line.firstIndex(of: ":") else { continue }

            // `nameserver[0] : 192.0.2.53` — 값에 콜론이 들어가는 줄(IPv6)이 있으므로
            // **첫 번째** 콜론에서만 자른다.
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

            if key.hasPrefix("nameserver[") {
                current?.nameservers.append(value)
            } else if key == "domain" {
                // `search domain[0]` 은 이름 뒤에 붙이는 접미사일 뿐이라 리졸버를 좁히지 않는다.
                // 좁히는 것은 `domain` 한 줄이다.
                current?.isDomainScoped = true
            } else if key == "flags", value.contains("Supplemental") {
                current?.isSupplemental = true
            } else if key == "options", value.contains("mdns") {
                current?.isMulticast = true
            }
        }
        flush()

        return (primary, scoped)
    }
}
