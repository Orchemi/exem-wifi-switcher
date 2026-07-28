import AppKit
import WifiSwitcherCore

/// 메뉴 항목의 **생김새**를 정하는 한 자리.
///
/// 이 메뉴에는 두 종류의 줄이 있고, 그 둘이 한눈에 갈리는 것이 이 파일의 존재 이유다.
///
///   - **주 항목** — 누를 수 있는 것과 지금 상태 한 마디. 기본 라벨 색, 기본 메뉴 글자 크기
///   - **보조 줄** — 그 위 항목에 딸린 짧은 명사구. **흐린 색 + 한 단 작은 글자 + `- ` 접두**
///
/// 위계를 만드는 것은 **색과 크기**다. 접두는 그것을 거들 뿐이다 — 셋 중 색만 빼도 줄들이
/// 평평해져서 무엇이 액션이고 무엇이 상태인지 다시 알 수 없게 된다.
///
/// **색은 시스템 색만 쓴다.** 회색 값을 직접 적으면 라이트/다크 중 한쪽에서 반드시 깨진다.
/// `secondaryLabelColor` 는 두 모드 모두에서 "읽히되 물러나는" 밝기를 시스템이 맞춰 준다.
///
/// **`isEnabled = false` 로 회색을 만들지 않는다.** 그것은 색을 얻으려고 상호작용과
/// 접근성(보이스오버가 '흐릿함' 으로 읽고 건너뛴다)을 대가로 내주는 방식이다.
/// 누를 수 없다는 사실과 흐리게 보이는 것은 별개이므로 각각 따로 정한다.
enum MenuStyle {

    /// 누를 수 없는 상태 한 마디 (메뉴 첫 줄). 색과 크기는 주 항목 그대로다.
    static func headline(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        // **`isEnabled = false` 로 두지 않는다.** AppKit 은 비활성 항목을 통째로 흐리게 칠하고,
        // 그 흐림은 `attributedTitle` 의 색을 덮어쓴다 (실측: 지정한 `labelColor` 가 회색으로 나왔다).
        // 그러면 이 줄이 딸린 보조 줄과 같은 밝기가 되어, 메뉴에서 가장 중요한 한 마디가 묻힌다.
        //
        // 대신 **누를 것을 주지 않는다** — 동작이 없으므로 눌러도 아무 일이 없고,
        // 접근성은 흐림 없이 그대로 읽힌다. (메뉴는 `autoenablesItems = false` 로 돌린다)
        item.isEnabled = true
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        return item
    }

    /// 고를 것이 없는 자리를 채우는 줄 ("등록된 프로필 없음").
    ///
    /// 액션이 놓일 자리에 서지만 액션이 아니다. 주 항목과 같은 밝기로 두면 누를 수 있는 것처럼
    /// 보이므로 색만 한 단 물린다 — 크기는 그대로다 (딸린 줄이 아니라 그 무리의 전부이므로).
    static func placeholder(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    /// 위 항목에 딸린 보조 줄.
    static func secondary(_ text: String) -> NSMenuItem {
        let line = StatusModel.secondaryLine(text)
        let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        item.isEnabled = false
        // 들여쓰기까지 함께 걸어 종속 관계를 위치로도 드러낸다.
        item.indentationLevel = 1
        item.attributedTitle = NSAttributedString(
            string: line,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }
}
