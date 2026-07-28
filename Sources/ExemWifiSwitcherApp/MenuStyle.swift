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

    /// 메뉴 첫 줄. 지금 상태 한 마디이자, **설정 창으로 들어가는 문**이다.
    /// 색과 크기는 주 항목 그대로다.
    ///
    /// **`isEnabled = false` 로 두지 않는다.** AppKit 은 비활성 항목을 통째로 흐리게 칠하고,
    /// 그 흐림은 `attributedTitle` 의 색을 덮어쓴다 (실측: 지정한 `labelColor` 가 회색으로 나왔다).
    /// 그러면 이 줄이 딸린 보조 줄과 같은 밝기가 되어, 메뉴에서 가장 중요한 한 마디가 묻힌다.
    ///
    /// 그래서 이 줄은 살아 있는 항목이고, **살아 있으면 AppKit 이 여느 항목처럼 하이라이트한다.**
    /// 눌리는 것처럼 보이는데 아무 일도 없는 줄은 고장으로 읽힌다 — 색을 얻은 대가로 고장을
    /// 하나 만든 셈이다. 그래서 동작을 준다.
    ///
    /// 여는 곳은 언제나 설정 창이다. 상태를 손볼 수 있는 자리(값 · 권한 · 로그인 항목)가 거기
    /// 하나뿐이므로, 어떤 상태에서 눌러도 그 창이 다음 자리다. 설정이 아직 없는 상태에서는
    /// 부르는 쪽이 문구 자체를 할 일로 바꿔 준다 (`StatusModel` 의 '초기 설정하기').
    static func headline(_ text: String, target: AnyObject?, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: action, keyEquivalent: "")
        item.target = target
        // 메뉴는 `autoenablesItems = false` 로 돈다 — 활성 여부를 여기서 정한다.
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
