import Foundation

/// IPv4 주소. 문자열 파싱은 **엄격하다** — 관대한 파싱은 검증을 우회하는 통로가 된다.
///
/// 거부하는 것:
/// - 점으로 나눈 옥텟이 4개가 아닌 것
/// - 옥텟에 숫자가 아닌 문자 (공백·부호·16진수 포함)
/// - 앞자리 0 (`192.0.2.01`) — 일부 파서가 8진수로 해석해 같은 문자열이 다른 주소가 된다
/// - 255 초과
public struct IPv4Address: Equatable, Hashable, Sendable, CustomStringConvertible {

    /// 네트워크 바이트 순서(빅엔디언)로 본 32비트 값.
    public let rawValue: UInt32

    /// 원본 표기. 정규 형태만 통과하므로 재구성 값과 항상 같다.
    public let description: String

    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count) else { return nil }
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            // 앞자리 0 금지 ("0" 자체는 허용)
            if part.count > 1 && part.first == "0" { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }

        self.rawValue = value
        self.description = text
    }

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
        self.description = [24, 16, 8, 0].map { String((rawValue >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }
}

/// IPv4 서브넷 마스크. 1비트가 앞쪽에 **연속**해야 한다 (`255.255.0.255` 같은 값 거부).
public struct SubnetMask: Equatable, Hashable, Sendable, CustomStringConvertible {

    public let rawValue: UInt32
    public let description: String

    /// 접두 길이. `/1` ~ `/31` 만 허용한다.
    /// `/0`(전체 개방)과 `/32`(호스트 단독)는 LAN 구성 값으로 의미가 없다.
    public var prefixLength: Int { rawValue.nonzeroBitCount }

    public init?(_ text: String) {
        guard let address = IPv4Address(text) else { return nil }
        let value = address.rawValue
        guard value != 0, value != UInt32.max else { return nil }
        // 연속 1비트 검사: 반전값이 (2^n - 1) 꼴이어야 한다
        let inverted = ~value
        guard inverted & (inverted &+ 1) == 0 else { return nil }

        self.rawValue = value
        self.description = text
    }

    /// 같은 마스크 아래에서 두 주소가 같은 서브넷에 있는가.
    public func isSameSubnet(_ a: IPv4Address, _ b: IPv4Address) -> Bool {
        (a.rawValue & rawValue) == (b.rawValue & rawValue)
    }

    /// 네트워크 주소 (호스트 비트가 전부 0).
    public func networkAddress(of address: IPv4Address) -> IPv4Address {
        IPv4Address(rawValue: address.rawValue & rawValue)
    }

    /// 브로드캐스트 주소 (호스트 비트가 전부 1).
    public func broadcastAddress(of address: IPv4Address) -> IPv4Address {
        IPv4Address(rawValue: (address.rawValue & rawValue) | ~rawValue)
    }

    /// 호스트로 배정할 수 있는 주소인가 (네트워크·브로드캐스트 주소 제외).
    /// `/31` 은 두 주소 모두 호스트로 쓰는 특수 케이스라 예외 처리한다.
    public func isAssignableHost(_ address: IPv4Address) -> Bool {
        if prefixLength >= 31 { return true }
        return address != networkAddress(of: address) && address != broadcastAddress(of: address)
    }
}
