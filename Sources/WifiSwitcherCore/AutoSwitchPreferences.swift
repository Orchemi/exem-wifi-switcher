import Foundation

/// 앱이 기억해 두는 켜짐/꺼짐 값 하나를 담는 곳.
///
/// 앱에서는 `UserDefaults`, 테스트에서는 메모리에 담는다. 설정 파일(`config.json`)에 두지 않는 이유는
/// 그 파일이 `root:admin` 소유라 저장할 때마다 권한이 필요하고, 이 값들은 기기·사용자별 취향이기 때문이다.
///
/// 자동 전환 on/off 와 '아이콘이 가려졌더라' 는 지난 기억(`HiddenIconNotice`)이 이 문을 함께 쓴다.
public protocol FlagStore: AnyObject {
    func boolValue(forKey key: String) -> Bool?
    func setBool(_ value: Bool, forKey key: String)
}

extension UserDefaults: FlagStore {
    public func boolValue(forKey key: String) -> Bool? {
        // 값을 정한 적이 없는 것과 false 를 구분해야 한다 (기본값이 '켜짐' 이므로).
        guard object(forKey: key) != nil else { return nil }
        return bool(forKey: key)
    }

    public func setBool(_ value: Bool, forKey key: String) {
        set(value, forKey: key)
    }
}

/// 자동 전환 설정.
public enum AutoSwitchPreferences {

    public static let enabledKey = "autoSwitchEnabled"

    /// 기본값은 **켜짐**이다. 이 도구의 목적이 "사람이 아무것도 누르지 않는 것" 이므로,
    /// 아무것도 정하지 않은 사용자에게는 자동 전환이 동작하는 편이 맞다.
    public static func isEnabled(in store: FlagStore) -> Bool {
        store.boolValue(forKey: enabledKey) ?? true
    }

    public static func setEnabled(_ enabled: Bool, in store: FlagStore) {
        store.setBool(enabled, forKey: enabledKey)
    }
}
