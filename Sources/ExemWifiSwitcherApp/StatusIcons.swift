import AppKit
import WifiSwitcherCore

/// 메뉴바 아이콘.
///
/// 번들에 들어 있는 템플릿 PNG 를 먼저 찾고, 없으면 SF Symbols 로 대신 그린다.
/// (아이콘 자산은 따로 만들어진다 — 없다고 앱이 아무것도 못 그리면 안 된다)
///
/// 어느 쪽이든 **템플릿 이미지**로 표시한다. macOS 가 알파만 읽고 라이트/다크·강조 상태에 맞춰
/// 색을 칠하므로, 템플릿 표시를 빠뜨리면 다크 메뉴바에서 검은 아이콘이 그대로 나와 보이지 않는다.
enum StatusIcons {

    private static let pointSize: CGFloat = 16

    static func image(for icon: MenuBarIcon) -> NSImage? {
        let image = bundledImage(named: icon.rawValue) ?? symbolImage(for: icon)
        image?.isTemplate = true
        image?.size = NSSize(width: pointSize, height: pointSize)
        image?.accessibilityDescription = accessibilityDescription(for: icon)
        return image
    }

    private static func bundledImage(named name: String) -> NSImage? {
        // 캐시된 이미지를 그대로 손대면 다른 곳의 표시까지 바뀐다. 복사본을 만든다.
        guard let original = Bundle.main.image(forResource: name) else { return nil }
        return original.copy() as? NSImage
    }

    private static func symbolImage(for icon: MenuBarIcon) -> NSImage? {
        let symbolName: String
        switch icon {
        case .manual: symbolName = "mappin.and.ellipse"
        case .dhcp: symbolName = "arrow.triangle.2.circlepath"
        case .error: symbolName = "exclamationmark.triangle"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription(for: icon))
    }

    private static func accessibilityDescription(for icon: MenuBarIcon) -> String {
        switch icon {
        case .manual: return "고정 IP 적용 중"
        case .dhcp: return "DHCP 사용 중"
        case .error: return "확인이 필요한 상태"
        }
    }
}
