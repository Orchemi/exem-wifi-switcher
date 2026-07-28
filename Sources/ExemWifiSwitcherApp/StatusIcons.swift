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

    /// 메뉴바 아이콘 높이.
    ///
    /// 기본값 16pt 는 다른 메뉴바 아이콘들과 나란히 놓았을 때 작아 보였다.
    /// 아이콘 자산은 캔버스 세로의 94% 를 이미 채우고 있어 여백으로는 더 키울 수 없으므로,
    /// 렌더 크기 자체를 올린다. 메뉴바가 허용하는 범위 안이다.
    private static let pointSize: CGFloat = 18

    static func image(for icon: MenuBarIcon) -> NSImage? {
        let image = bundledImage(named: icon.rawValue) ?? symbolImage(for: icon)
        image?.isTemplate = true
        // 메뉴바가 정하는 것은 **높이**다. 가로는 원본 비율을 따라야 한다.
        // 아이콘은 Wi-Fi 베이스 오른쪽 아래에 배지가 얹힌 가로로 긴 모양(18×16pt)이라,
        // 정사각으로 못박으면 가로가 눌려 찌그러진다. SF Symbols 폴백은 정사각이므로
        // 같은 식으로 계산해도 그대로 16×16 이 된다.
        if let image, image.size.height > 0 {
            let ratio = image.size.width / image.size.height
            image.size = NSSize(width: pointSize * ratio, height: pointSize)
        }
        image?.accessibilityDescription = accessibilityDescription(for: icon)
        return image
    }

    private static func bundledImage(named name: String) -> NSImage? {
        // 캐시된 이미지를 그대로 손대면 다른 곳의 표시까지 바뀐다. 복사본을 만든다.
        guard let original = Bundle.main.image(forResource: name) else { return nil }
        return original.copy() as? NSImage
    }

    private static func symbolImage(for icon: MenuBarIcon) -> NSImage? {
        // 자산이 없을 때만 쓰이지만, 상태를 가리키는 은유는 실제 아이콘과 같은 것으로 맞춘다
        // (서류가방=사내 / 집=그 밖 / 원+느낌표=확인 필요).
        let symbolName: String
        switch icon {
        case .manual: symbolName = "briefcase"
        case .dhcp: symbolName = "house"
        case .error: symbolName = "exclamationmark.circle"
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
