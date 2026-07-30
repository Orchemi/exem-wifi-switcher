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

/// 숫자 하나를 담아 두는 곳.
///
/// `FlagStore` 와 같은 자리(`UserDefaults`)를 쓰지만 담는 것이 숫자다 — 아이콘 자리는
/// 켜짐/꺼짐이 아니라 좌표 하나라서 문을 따로 낸다. 테스트에서는 메모리에 담는다.
public protocol NumberStore: AnyObject {
    func doubleValue(forKey key: String) -> Double?
    func setDouble(_ value: Double, forKey key: String)
}

extension UserDefaults: NumberStore {
    public func doubleValue(forKey key: String) -> Double? {
        // 정한 적이 없는 것과 0 을 구분해야 한다 — 0 은 '오른쪽 끝' 이라는 뜻의 유효한 자리다.
        guard object(forKey: key) != nil else { return nil }
        return double(forKey: key)
    }

    public func setDouble(_ value: Double, forKey key: String) {
        set(value, forKey: key)
    }
}

/// 아이콘 자리에 대해 앱이 알고 있는 것 전부.
public struct StatusItemSeatState: Equatable, Sendable {

    /// macOS 가 적어 둔 자리. 정한 적이 없으면 `nil`.
    ///
    /// **macOS 는 사용자가 ⌘-드래그로 옮겼을 때만 이 값을 적는다** (2026-07-30 실측: 상태 항목을
    /// 여러 번 띄웠다 내려도 값이 생기지 않았고, 앱이 심어 둔 값도 그대로 남았다).
    /// 그래서 앱이 심은 값과 다르면 **사용자가 손수 옮긴 것**이다.
    public var stored: Double?

    /// 앱이 마지막으로 심은 값. 심은 적이 없으면 `nil`.
    public var appliedByApp: Double?

    /// 앱이 지금까지 오른쪽으로 민 횟수.
    public var nudges: Int

    public init(stored: Double?, appliedByApp: Double?, nudges: Int) {
        self.stored = stored
        self.appliedByApp = appliedByApp
        self.nudges = nudges
    }

    /// 사용자가 손수 옮겨 둔 자리인가. **그렇다면 앱은 손대지 않는다.**
    public var isUserPlaced: Bool {
        guard let stored else { return false }
        return stored != appliedByApp
    }
}

/// 아이콘을 **어디에 놓을 것인가**.
///
/// `autosaveName` 은 사용자가 ⌘-드래그로 한 번 옮긴 뒤에야 듣는다. 옮기기 전까지 macOS 는 남은
/// 자리 중 **왼쪽 끝**에 놓고, 노치가 있는 Mac 에서 그 자리는 노치에 물리는 자리다. 오너의 기계에서
/// 실제로 그랬다 (항목 656~699 · 노치 663~848 — 아이콘이 노치 밑에 깔려 보이지 않았다).
/// 그래서 **저장된 자리가 없을 때만** 노치를 피하는 값을 하나 심어 준다.
///
/// ## 심는 값의 뜻 (2026-07-30 실측 · 1512pt 화면 · 노치 663~848 · 폭 37pt 항목)
///
/// | 심은 값 | 놓인 자리 | |
/// |---|---|---|
/// | 없음 | 620 ~ 657 | 남은 자리 중 왼쪽 끝 — 노치에 붙는다 |
/// | 0 · 50 · 100 · 200 | 1276 ~ 1313 | 더 오른쪽은 시스템 항목이 차지해 여기서 멈춘다 |
/// | 300 | 1123 ~ 1160 | |
/// | 400 | 1065 ~ 1102 | |
/// | 450 | 1015 ~ 1052 | |
/// | 504 · 524 | 945 ~ 982 | |
/// | **544** · 564 · 600 | **907 ~ 944** | 이 앱이 심는 값이 여기 든다 |
/// | 620 | 840 ~ 877 | 노치에 물린다 |
/// | 700 | 808 ~ 845 | 노치 안 |
/// | 800 이상 | 693 ~ 730 | 노치 안 — 더 왼쪽으로는 가지 않는다 |
///
/// 값은 **화면 오른쪽 끝에서 왼쪽으로 잰 거리**다. 클수록 왼쪽이고, 그 자리가 이미 차 있으면
/// 가까운 빈자리로 붙는다(표의 계단이 그것이다). 화면 오른쪽 끝에서 항목 왼쪽 끝까지의 실제 거리는
/// 심은 값보다 60pt 안팎 크다 (544 → 1512-907 = 605). 그 어긋남까지 포함해 `notchClearance` 를 잡았다.
///
/// 값은 세 번씩 재서 모두 같았다 — 이 자리 배정은 흔들리지 않는다.
public enum StatusItemSeat {

    /// macOS 가 자리를 적어 두는 열쇠. `NSStatusItem.autosaveName` 과 짝이다.
    public static func preferredPositionKey(autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// 앱이 마지막으로 심은 값을 적어 두는 열쇠.
    /// 이것이 없으면 **사용자가 옮긴 자리와 앱이 민 자리를 구별할 수 없다.**
    public static let appliedPositionKey = "menuBarSeatAppliedPosition"

    /// 앱이 지금까지 민 횟수를 적어 두는 열쇠.
    public static let nudgeCountKey = "menuBarSeatNudges"

    /// 자동으로 밀 수 있는 횟수.
    ///
    /// **반드시 막혀 있어야 한다.** 밀 때마다 다시 재고 또 미는 길이라, 상한이 없으면 아이콘이
    /// 메뉴 막대를 걸어 다닌다. 두 번 밀어 안 되면 자리 문제가 아니므로 사용자에게 말한다.
    public static let nudgeLimit = 2

    /// 노치 오른쪽 가장자리에서 얼마나 떨어뜨릴 것인가.
    ///
    /// 위 표에서 온 값이다 — 노치 오른쪽 끝까지의 거리(1512-848 = 664)에서 120 을 빼면 544 가 되고,
    /// 그 값은 907 에 놓여 노치를 59pt 벗어난다. 60pt 안팎은 좌표 어긋남을 메우는 데 쓰이고,
    /// 나머지 60pt 가 실제로 노치와 벌어지는 거리다.
    ///
    /// **더 크게 잡지 마라** — 값이 커지면 왼쪽으로 가고, 620 에서 이미 노치에 물렸다.
    /// 더 작게 잡을 수는 있지만 오른쪽에는 시스템 항목이 있어 결국 같은 자리로 붙는다.
    static let notchClearance: Double = 120

    /// 밀어 놓을 때 구간 왼쪽 끝에서 띄우는 거리. 아이콘 하나 폭 남짓이다 —
    /// 경계에 딱 붙이면 좌표 어긋남만큼 다시 물린다.
    static let nudgeClearance: Double = 40

    /// 보이는 구간들 사이의 빈틈. 그것이 노치다. 구간이 하나뿐이면 노치가 없다.
    public static func notch(between spans: [MenuBarSpan]) -> MenuBarSpan? {
        let sorted = spans.sorted { $0.minX < $1.minX }
        guard sorted.count >= 2 else { return nil }
        let gap = MenuBarSpan(minX: sorted[0].maxX, maxX: sorted[1].minX)
        return gap.isEmpty ? nil : gap
    }

    /// 지금 앱이 아이콘 자리에 대해 알고 있는 것.
    public static func state(autosaveName: String, in store: NumberStore) -> StatusItemSeatState {
        StatusItemSeatState(
            stored: store.doubleValue(forKey: preferredPositionKey(autosaveName: autosaveName)),
            appliedByApp: store.doubleValue(forKey: appliedPositionKey),
            nudges: Int(store.doubleValue(forKey: nudgeCountKey) ?? 0)
        )
    }

    /// 처음 놓을 자리. 심을 이유가 없으면 `nil`.
    ///
    /// 심지 않는 경우가 둘이다.
    ///   - **이미 자리가 정해져 있다** — 사용자가 옮겨 둔 자리다. 덮어쓰면 그 사람이 고른 자리를
    ///     빼앗는 것이고, 이 앱이 가장 경계하는 실패다
    ///   - **노치가 없다** — 피할 것이 없는데 자리를 정해 두면, 그 화면에서 자연스럽게 놓였을 자리를
    ///     이유 없이 옮기는 셈이 된다. 노치 없는 기계·외부 모니터에서는 아무것도 하지 않는다
    public static func seedPosition(stored: Double?, screen: MenuBarSpan, notch: MenuBarSpan?) -> Double? {
        guard stored == nil, let notch else { return nil }
        let value = (screen.maxX - notch.maxX) - notchClearance
        return value > 0 ? value : nil
    }

    /// 가려진 아이콘을 오른쪽으로 **한 번** 미는 다음 값. 밀 수 없거나 밀 이유가 없으면 `nil`.
    ///
    /// 미는 폭은 상수가 아니라 **방금 잰 좌표에서 나온다** — 오른쪽 첫 빈 구간까지 얼마나 가야
    /// 하는지 계산해 그만큼 값을 줄인다. 값과 좌표가 정확히 1:1 은 아니지만(위 표의 계단),
    /// 밀고 다시 재는 되먹임이라 한두 번이면 닿는다.
    public static func nudgedPosition(placement: StatusItemPlacement, state: StatusItemSeatState) -> Double? {
        guard placement.isMeasurable, placement.isHidden else { return nil }
        // 사용자가 고른 자리는 앱이 옮기지 않는다. 가려져 있어도 그렇다 — 그때는 말로 알린다.
        guard !state.isUserPlaced else { return nil }
        guard state.nudges < nudgeLimit else { return nil }
        // 심어 둔 값이 없으면 얼마를 빼야 할지 알 수 없다. 좌표와 값의 어긋남(60pt 안팎)이
        // 기계마다 다를 수 있어 짐작으로 쓰면 엉뚱한 자리로 보낸다.
        guard let current = state.stored else { return nil }

        let width = placement.item.maxX - placement.item.minX
        // 오른쪽에 있으면서 항목을 통째로 담을 수 있는 첫 구간. 없으면 밀 자리가 없다
        // (어느 화면에도 없는 항목이 여기 걸린다 — 구간이 하나도 없다).
        guard let target = placement.visibleSpans
            .filter({ $0.minX > placement.item.minX && ($0.maxX - $0.minX) >= width + nudgeClearance })
            .min(by: { $0.minX < $1.minX })
        else { return nil }

        let shift = (target.minX + nudgeClearance) - placement.item.minX
        guard shift > 0 else { return nil }
        let next = max(current - shift, 0)
        // 더 갈 곳이 없으면(이미 오른쪽 끝) 미는 시늉을 하지 않는다 — 같은 값을 다시 심으면
        // 아무것도 달라지지 않은 채 횟수만 깎인다.
        return next < current ? next : nil
    }

    /// 심은 값을 남긴다. **여기서 남기지 않으면 사용자가 옮긴 자리와 구별할 수 없다.**
    public static func recordSeed(_ position: Double, autosaveName: String, in store: NumberStore) {
        store.setDouble(position, forKey: preferredPositionKey(autosaveName: autosaveName))
        store.setDouble(position, forKey: appliedPositionKey)
        store.setDouble(0, forKey: nudgeCountKey)
    }

    /// 민 값을 남긴다. 횟수가 함께 올라간다 — 그 횟수가 걸어 다니는 아이콘을 막는 유일한 빗장이다.
    public static func recordNudge(
        _ position: Double, autosaveName: String, from state: StatusItemSeatState, in store: NumberStore
    ) {
        store.setDouble(position, forKey: preferredPositionKey(autosaveName: autosaveName))
        store.setDouble(position, forKey: appliedPositionKey)
        store.setDouble(Double(state.nudges + 1), forKey: nudgeCountKey)
    }

    /// 아이콘이 보이는 것을 확인했다 — 민 횟수를 거둔다.
    ///
    /// 거두지 않으면 **한 기계에서 평생 두 번**만 밀 수 있다. 외부 모니터를 뗐다 붙이는 것만으로
    /// 자리는 다시 어그러지므로, 한 번 해결된 뒤에는 다음 기회를 새로 준다.
    public static func recordVisible(in store: NumberStore) {
        store.setDouble(0, forKey: nudgeCountKey)
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

/// `--diagnose` 가 메뉴 막대에 대해 말할 수 있는 것.
///
/// **지금 좌표는 말할 수 없다.** `--diagnose` 는 `NSApplication` 을 띄우지 않아 상태 항목 자체가
/// 없고, 따로 돌고 있는 앱에게 어디 있느냐고 물을 길도 없다. 그래서 지어내는 대신 **그 앱이
/// 마지막으로 보고 남긴 것**을 말한다 — 앱이 자리를 잰 뒤 `UserDefaults` 에 남겨 두는 값들이다.
///
/// 노치 유무만은 지금 재서 말한다. 화면은 앱 없이도 읽히고(`NSScreen`), 이 한 가지가
/// 나머지 전부를 설명하기 때문이다 — 오너의 아이콘은 노치 밑에 깔려 있었다.
public enum MenuBarSeatReport {

    /// - Parameters:
    ///   - lastKnownHidden: 앱이 마지막으로 본 상태. 본 적이 없으면 `nil`.
    ///   - state: 자리에 대해 앱이 남겨 둔 것.
    ///   - hasNotch: 지금 화면에 노치가 있는가. 화면을 읽지 못했으면 `nil`.
    public static func text(lastKnownHidden: Bool?, state: StatusItemSeatState, hasNotch: Bool?) -> String {
        var facts: [String] = []
        if lastKnownHidden != nil { facts.append("마지막 확인") }
        if let hasNotch { facts.append(hasNotch ? "노치 있는 화면" : "노치 없는 화면") }
        facts.append(seatText(state))
        if state.nudges > 0 { facts.append("앱이 \(state.nudges)번 옮겨 봄") }
        let detail = "(" + facts.joined(separator: " · ") + ")"

        switch lastKnownHidden {
        case true:
            return "가려짐: ⌘ 를 누른 채 아이콘을 오른쪽으로 끌어 옮기세요 \(detail)"
        case false:
            return "보임 \(detail)"
        default:
            return "확인한 적 없음: 앱을 실행하면 2초 안에 확인합니다 \(detail)"
        }
    }

    private static func seatText(_ state: StatusItemSeatState) -> String {
        guard let stored = state.stored else { return "위치를 정한 적 없음" }
        let who = state.isUserPlaced ? "사용자가 옮긴 위치" : "앱이 정한 위치"
        return "오른쪽 끝에서 \(points(stored))pt · \(who)"
    }

    /// 위치 값은 정수로 떨어진다. `544.0` 을 그대로 찍으면 읽는 사람이 정밀도를 오해한다.
    private static func points(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
