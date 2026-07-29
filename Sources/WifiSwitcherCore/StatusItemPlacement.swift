import Foundation

/// 메뉴 막대의 가로 구간 하나. 화면 좌표 그대로 쓴다.
public struct MenuBarSpan: Equatable, Sendable {

    public var minX: Double
    public var maxX: Double

    public init(minX: Double, maxX: Double) {
        self.minX = minX
        self.maxX = maxX
    }

    /// 이 구간이 저 구간을 통째로 품는가.
    public func contains(_ other: MenuBarSpan) -> Bool {
        minX <= other.minX && other.maxX <= maxX
    }

    var isEmpty: Bool { maxX <= minX }
}

/// 상태 아이콘이 **실제로 보이는 자리**에 있는가.
///
/// 왜 필요한가 — 메뉴 막대에 자리가 모자라면 macOS 는 상태 항목을 조용히 삼킨다. 항목은 여전히
/// `isVisible = true` 이고 좌표도 보고하는데 화면에는 없다. 이 앱은 `.accessory` 라 Dock 아이콘도
/// 없어서, 그 순간 사용자에게 남는 출입구가 하나도 없다 (오너가 실제로 이렇게 갇혔다).
///
/// **판정은 기하 하나로 끝난다** — 항목이 차지한 가로 구간이 그 화면에서 그려지는 구간 안에
/// 통째로 들어가는가. 노치가 있는 화면은 그려지는 구간이 노치를 사이에 두고 **둘로 갈라진다**.
///
/// 실측(2026-07-29 · macOS 26.5 · 노치 있는 내장 화면 1512pt, 노치 663~848)
///
/// | 상황 | 항목 x 구간 | `window.screen` |
/// |---|---|---|
/// | 앞선 항목 없음 (앱이 마지막에 뜬 경우) | 613 ~ 676 | 내장 화면 — **노치에 걸침** |
/// | 앞에 항목 하나 | 528 ~ 591 | 내장 화면 — 노치 왼쪽 안 |
/// | 자리를 다 채운 뒤 | -1944 ~ -1881 | **`nil`** — 어느 화면에도 없음 |
///
/// macOS 는 노치를 **비켜 놓지 않는다.** 오른쪽에서 왼쪽으로 그냥 이어 붙이다가 노치를 가로지른다 —
/// 그래서 왼쪽 끝 자리를 잡은 항목은 노치에 물린다. 위 표의 첫 줄이 오너가 겪은 그 자리다.
public struct StatusItemPlacement: Equatable, Sendable {

    /// 상태 항목이 차지한 가로 구간.
    public var item: MenuBarSpan

    /// 그 항목이 놓인 화면에서 **실제로 그려지는** 가로 구간들.
    /// 노치가 없으면 하나, 노치가 있으면 노치 좌·우로 둘. 어느 화면에도 없으면 비어 있다.
    public var visibleSpans: [MenuBarSpan]

    public init(item: MenuBarSpan, visibleSpans: [MenuBarSpan]) {
        self.item = item
        self.visibleSpans = visibleSpans
    }

    /// 이 값으로 판정해도 되는가.
    ///
    /// 상태 항목은 만든 직후 **최종 자리를 말하지 않는다.** 실측에서 폭 63pt·높이 0 짜리 값이 먼저
    /// 오고 0.25초 뒤에야 자리가 정해졌다. 폭이 없는 값으로 판정하면 멀쩡한 아이콘을 가려졌다고 부른다.
    public var isMeasurable: Bool { !item.isEmpty }

    /// 아이콘이 가려졌는가.
    ///
    /// **조금이라도 걸치면 가려진 것으로 본다.** 실측한 613~676 은 63pt 중 13pt 만 노치에 물렸지만,
    /// 자리의 오른쪽 끝(676)은 이웃 항목이 정하고 폭만 줄어들므로 **아이콘처럼 좁은 항목은 같은 자리에서
    /// 거의 전부 삼켜진다.** 얼마나 물렸는지 재는 대신 물리면 가려진 것으로 둔다.
    public var isHidden: Bool {
        !visibleSpans.contains { $0.contains(item) }
    }
}

/// 아이콘이 가려졌다는 사실을 **언제 말할 것인가**.
///
/// 이 알림은 한 번 뜨면 할 말을 다 한 것이다 — 같은 상태로 매번 로그인할 때마다 다시 말하면
/// 소음이 되고, 소음이 된 알림은 사용자가 통째로 꺼 버린다. 그러면 자동 전환 알림까지 함께 죽는다.
///
/// 그래서 **상태가 바뀔 때만** 말한다. 지난번에 본 상태를 남겨 두고(`UserDefaults`), 그때와 달라진
/// 경우에만 입을 연다. 외부 모니터를 떼면 노치 있는 화면으로 돌아오므로 **고친 뒤 다시 가려지는 일은
/// 실제로 일어난다** — 그때는 다시 말해야 한다.
public enum HiddenIconNotice {

    /// 지난번에 본 상태를 담아 두는 열쇠.
    public static let lastKnownHiddenKey = "menuBarIconHidden"

    /// 지금 알릴 자리인가.
    ///
    /// - Parameters:
    ///   - isHidden: 방금 판정한 상태.
    ///   - lastKnown: 지난번에 본 상태. 본 적이 없으면 `nil`.
    public static func shouldAnnounce(isHidden: Bool, lastKnown: Bool?) -> Bool {
        isHidden && lastKnown != true
    }

    /// 지난번에 본 상태를 읽는다.
    public static func lastKnownHidden(in store: FlagStore) -> Bool? {
        store.boolValue(forKey: lastKnownHiddenKey)
    }

    /// 방금 본 상태를 남긴다. **알렸든 아니든 남긴다** — 남기지 않으면 고친 사실을 잊어
    /// 다음에 다시 가려졌을 때 입을 열지 못한다.
    public static func remember(isHidden: Bool, in store: FlagStore) {
        store.setBool(isHidden, forKey: lastKnownHiddenKey)
    }
}
