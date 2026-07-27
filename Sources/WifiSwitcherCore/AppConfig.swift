import Foundation

/// `config.json` 의 내용.
///
/// 이 파일에는 **사용자의 실제 사내 네트워크 값**이 들어간다.
/// 그래서 레포에는 `config.example.json` 만 두고, 실 파일은 `/usr/local/etc/` 에만 존재한다.
public struct AppConfig: Codable, Equatable, Sendable {

    /// 현재 지원하는 설정 파일 버전.
    public static let currentVersion = 1

    public var version: Int
    /// `networksetup` 이 쓰는 네트워크 서비스 이름 (보통 "Wi-Fi").
    public var service: String
    public var profiles: [NetworkProfile]
    /// 어떤 SSID 에도 걸리지 않을 때 적용할 프로필 이름.
    public var defaultProfile: String

    public init(
        version: Int = AppConfig.currentVersion,
        service: String = "Wi-Fi",
        profiles: [NetworkProfile],
        defaultProfile: String
    ) {
        self.version = version
        self.service = service
        self.profiles = profiles
        self.defaultProfile = defaultProfile
    }

    private enum CodingKeys: String, CodingKey {
        case version, service, profiles, defaultProfile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.service = try container.decodeIfPresent(String.self, forKey: .service) ?? "Wi-Fi"
        self.profiles = try container.decode([NetworkProfile].self, forKey: .profiles)
        self.defaultProfile = try container.decode(String.self, forKey: .defaultProfile)
    }

    // MARK: - 조회

    public func profile(named name: String) -> NetworkProfile? {
        profiles.first { $0.name == name }
    }

    /// SSID 로 적용할 프로필을 고른다. 걸리는 프로필이 없으면 기본 프로필.
    /// SSID 비교는 대소문자를 구분한다 — 802.11 SSID 는 바이트열이라 대소문자가 다르면 다른 네트워크다.
    public func profile(forSSID ssid: String?) -> NetworkProfile? {
        if let ssid, let matched = profiles.first(where: { $0.ssids.contains(ssid) }) {
            return matched
        }
        return profile(named: defaultProfile)
    }

    // MARK: - 검증

    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        if version != Self.currentVersion {
            errors.append(.unsupportedVersion(version))
        }
        if !Self.isValidServiceName(service) {
            errors.append(.invalidServiceName(service))
        }
        if profiles.isEmpty {
            errors.append(.emptyProfileList)
        }

        var seenNames = Set<String>()
        var seenSSIDs = Set<String>()
        for profile in profiles {
            errors.append(contentsOf: profile.validate())
            if !seenNames.insert(profile.name).inserted {
                errors.append(.duplicateProfileName(profile.name))
            }
            for ssid in Set(profile.ssids) where !seenSSIDs.insert(ssid).inserted {
                errors.append(.duplicateSSID(ssid))
            }
        }

        if profile(named: defaultProfile) == nil {
            errors.append(.unknownDefaultProfile(defaultProfile))
        }
        return errors
    }

    /// 서비스 이름의 형태 검사. "USB 10/100/1000 LAN" 처럼 공백·슬래시가 들어갈 수 있어
    /// 문자 집합을 좁히는 대신 **길이와 제어 문자**만 본다.
    /// 실제 존재 여부는 `apply` 가 `networksetup -listallnetworkservices` 와 대조해 확정한다.
    public static func isValidServiceName(_ name: String) -> Bool {
        guard (1...64).contains(name.count) else { return false }
        if name != name.trimmingCharacters(in: .whitespaces) { return false }
        return !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    // MARK: - 읽기 · 쓰기

    public enum ConfigError: Error, CustomStringConvertible {
        case notFound(String)
        case unreadable(String, underlying: Error)
        case malformed(String, underlying: Error)
        case invalid([ValidationError])
        case unwritable(String, underlying: Error)

        public var description: String {
            switch self {
            case .notFound(let path):
                return "설정 파일이 없습니다: \(path)"
            case .unreadable(let path, let underlying):
                return "설정 파일을 읽지 못했습니다: \(path) (\(underlying))"
            case .malformed(let path, let underlying):
                return "설정 파일 형식이 올바르지 않습니다: \(path) (\(underlying))"
            case .invalid(let errors):
                return "설정 값에 문제가 있습니다:\n" + errors.map { "  - \($0)" }.joined(separator: "\n")
            case .unwritable(let path, let underlying):
                return "설정 파일에 저장하지 못했습니다: \(path) (\(underlying))"
            }
        }
    }

    /// 앱이 뜰 때 본 설정 파일의 상태.
    public enum Status: Equatable, Sendable {
        /// 파일이 아직 없다 (설치 전이거나 지워졌다)
        case missing(path: String)
        /// 설치 스크립트가 복사한 예시 그대로다 — 아직 사용자의 값이 아니다
        case pristineExample(path: String)
        /// 파일은 있는데 읽거나 검증하지 못했다
        case unusable(path: String, reason: String)
        /// 그대로 쓸 수 있다
        case ready(AppConfig)
    }

    /// 설정 파일이 어떤 상태인지 본다. 던지지 않고 상태로 돌려주므로 화면에 그대로 옮길 수 있다.
    ///
    /// 예시 파일 판별은 설명용 `_readme` 키의 유무로 한다. `install.sh` 가 `config.example.json`
    /// 을 그대로 복사하고, 앱이 저장할 때는 이 키를 남기지 않기 때문에
    /// **"사용자가 한 번이라도 저장했는가"** 의 표시가 된다.
    public static func inspect(path: String = InstallPaths.configFile) -> Status {
        guard FileManager.default.fileExists(atPath: path) else { return .missing(path: path) }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .unusable(path: path, reason: "파일을 읽지 못했습니다")
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           dictionary["_readme"] != nil {
            return .pristineExample(path: path)
        }

        do {
            return .ready(try load(from: path))
        } catch {
            return .unusable(path: path, reason: "\(error)")
        }
    }

    /// 설정 파일을 읽고 검증까지 마친다. 검증에 실패하면 값을 돌려주지 않는다.
    public static func load(from path: String = InstallPaths.configFile) throws -> AppConfig {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.notFound(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path, underlying: error)
        }

        let config: AppConfig
        do {
            config = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw ConfigError.malformed(path, underlying: error)
        }

        let errors = config.validate()
        guard errors.isEmpty else { throw ConfigError.invalid(errors) }
        return config
    }

    /// 검증을 통과한 설정만, **쓸 권한이 이미 있을 때** 저장한다.
    ///
    /// 설치된 설정 파일(`/usr/local/etc/…/config.json`)은 `root:wheel 0644` 라
    /// 사용자 권한으로는 여기까지 오지 못한다. 앱은 `ConfigInstaller` 를 통해
    /// 관리자 인증을 받고 저장한다. 이 메서드는 **이미 root 인 경우**(sudo 로 도는 CLI·복구)와
    /// 테스트에서 쓴다.
    ///
    /// 갈아 끼우기(atomic)로 쓴다. 쓰는 도중에 `apply` 가 읽어 반쯤 잘린 JSON 을 보는 일이 없다.
    /// 새 파일의 소유자는 이 프로세스(root), 그룹은 상위 디렉터리(wheel)를 따르고, 권한은 0644 로 맞춘다.
    public func save(to path: String = InstallPaths.configFile) throws {
        let errors = validate()
        guard errors.isEmpty else { throw ConfigError.invalid(errors) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        let url = URL(fileURLWithPath: path)

        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        } catch {
            throw ConfigError.unwritable(path, underlying: error)
        }
    }
}
