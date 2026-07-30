import AppKit

import WifiSwitcherCore

/// 아이콘 자리를 심고 옮기는 AppKit 글루.
///
/// **판단은 여기에 없다.** 어디에 심을지·밀 수 있는지는 `StatusItemSeat` 가 정하고 단위 테스트가
/// 지킨다. 여기서 하는 일은 화면에서 좌표를 꺼내고, 정해진 값을 `UserDefaults` 에 적고,
/// 상태 항목에게 그 값을 다시 읽게 하는 것뿐이다.
@MainActor
enum MenuBarSeat {

    /// 상태 항목을 **만들기 전에** 자리를 심는다. 심은 값을 돌려준다 (심지 않았으면 `nil`).
    ///
    /// **만든 뒤에는 늦다** — 상태 항목은 태어나는 순간 저장된 자리를 읽는다.
    /// 그래서 `StatusItemController` 는 이 함수를 부른 다음에 항목을 만든다.
    @discardableResult
    static func seedIfNeeded(autosaveName: String, store: UserDefaults) -> Double? {
        let screen = notchedScreen()
        let spans = visibleSpans(of: screen)
        guard let frame = screen?.frame,
              let position = StatusItemSeat.seedPosition(
                  stored: StatusItemSeat.state(autosaveName: autosaveName, in: store).stored,
                  screen: MenuBarSpan(minX: frame.minX, maxX: frame.maxX),
                  notch: StatusItemSeat.notch(between: spans)
              )
        else { return nil }
        StatusItemSeat.recordSeed(position, autosaveName: autosaveName, in: store)
        return position
    }

    /// 이미 떠 있는 상태 항목을 다른 자리로 옮긴다.
    ///
    /// **`autosaveName` 을 다시 지정하는 것이 옮기는 방법이다** (2026-07-30 실측). 값만 새로
    /// 적어서는 항목이 움직이지 않았고(763 그대로), 같은 이름을 한 번 더 지정하자 그 자리로 갔다
    /// (763 → 945, 심은 값 500). **`isVisible` 은 건드리지 않는다** — 끄는 순간 기억해 둔 자리가
    /// 지워진다 (`StatusItemController.init()` 주석).
    static func move(
        _ statusItem: NSStatusItem, to position: Double,
        autosaveName: String, from state: StatusItemSeatState, store: UserDefaults
    ) {
        StatusItemSeat.recordNudge(position, autosaveName: autosaveName, from: state, in: store)
        statusItem.autosaveName = autosaveName
    }

    /// 노치가 있는 화면. 상태 항목은 주 화면의 메뉴 막대에 뜨므로 그쪽을 먼저 본다.
    ///
    /// 여러 대가 붙어 있고 그중 하나만 노치가 있다면 그 화면 기준으로 심는다 — 심는 값은
    /// **오른쪽 끝에서 잰 거리**라서, 노치 없는 화면으로 옮겨 가도 오른쪽 어딘가에 놓일 뿐 해가 없다.
    static func notchedScreen() -> NSScreen? {
        let candidates = [NSScreen.main].compactMap { $0 } + NSScreen.screens
        return candidates.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
    }

    /// 화면에서 메뉴 막대가 **실제로 그려지는** 가로 구간들.
    ///
    /// 노치가 있는 화면은 `auxiliaryTopLeftArea` · `auxiliaryTopRightArea` 가 노치 좌·우를 알려 준다
    /// (실측: 1512pt 화면에서 0~663 과 848~1512 — 사이 663~848 이 노치다).
    /// 노치가 없으면 화면 폭 전체가 한 구간이다.
    ///
    /// 창이 **어느 화면에도 없으면 구간이 하나도 없다** — 자리가 모자라 밀려난 항목이 그렇다
    /// (실측: `x=-1944`, `window.screen == nil`).
    static func visibleSpans(of screen: NSScreen?) -> [MenuBarSpan] {
        guard let screen else { return [] }
        let aux = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
        guard !aux.isEmpty else {
            return [MenuBarSpan(minX: screen.frame.minX, maxX: screen.frame.maxX)]
        }
        return aux.map { MenuBarSpan(minX: $0.minX, maxX: $0.maxX) }
    }
}

/// 상태 아이콘이 메뉴 막대에서 **실제로 보이는지** 확인하고, 가려졌으면 한 번 비켜 보고 한 번 알린다.
///
/// 이 앱은 `.accessory` 라 Dock 아이콘이 없다. 아이콘이 가려지면 사용자에게는 앱이 사라진 것과
/// 구별되지 않는다 — 오너가 실제로 그렇게 갇혔다.
///
/// **말하기 전에 먼저 해 본다.** 알림만으로는 오너가 못 고쳤다 (알림은 떴고, 기록도 남았는데,
/// 아이콘은 노치 밑에 그대로 있었다). 그래서 가려진 것을 보면 자리를 오른쪽으로 밀어 보고,
/// 그래도 안 되면 그때 말한다.
///
/// **판단은 여기에 없다.** 이 기하값이면 가려진 것인가는 `StatusItemPlacement` 가,
/// 어디로 얼마나 밀 것인가는 `StatusItemSeat` 가, 지금 말할 자리인가는 `HiddenIconNotice` 가
/// 정하고 단위 테스트가 지킨다. 여기서 하는 일은 AppKit 에서 값을 꺼내 넘기는 것뿐이다.
@MainActor
final class MenuBarVisibilityWatch {

    /// 자리가 정해지기를 기다리는 시간.
    ///
    /// 상태 항목은 만든 직후 최종 자리를 말하지 않는다. 실측한 순서(macOS 26.5)
    ///   +0.00s `(x=0, y=0, w=63, h=0)` — 높이가 없다
    ///   +0.10s `(x=0, y=-26, w=63, h=30)` · +0.15s `(x=0, y=-30 …)` — **어느 화면에도 없다**
    ///   +0.25s `(x=1659, y=1410, w=63, h=30)` — 여기서 정해지고 그대로 있었다
    ///
    /// 가운데 두 값이 위험하다 — 화면이 없으니 그대로 재면 **멀쩡한 아이콘을 가려졌다고 부른다.**
    /// 재는 시각이 이르면 잘못 알리고, 게다가 그 잘못된 값을 기억해 **정작 진짜 가려졌을 때 입을 다문다.**
    /// 늦게 재서 잃는 것은 알림이 조금 늦는 것뿐이라, 넉넉히 기다리는 쪽으로 기운다.
    private static let settleDelay: TimeInterval = 1.5

    /// 한 번 더 재서 같은 값인지 확인하는 간격.
    ///
    /// 시간만으로 못박지 않는 이유 — 위 실측은 이 기계 이 순간의 값이고, 느린 기계나 로그인 직후에는
    /// 더 걸릴 수 있다. **두 번 재서 같을 때만** 말한다. 지나가는 값은 두 번 연속 같기 어렵다.
    private static let confirmDelay: TimeInterval = 0.5

    private let statusItem: NSStatusItem
    private let autosaveName: String
    /// 가려짐 여부(`FlagStore`)와 아이콘 자리(`NumberStore`)를 같은 자리에 담는다.
    private let store: UserDefaults
    private let announce: @MainActor (SwitchAnnouncement.Message) -> Void

    /// 화면 구성 변경 관찰. 이 객체는 앱과 수명을 같이 하므로 따로 떼지 않는다
    /// (`StatusItemController` 의 다른 관찰들과 같다).
    private var screenObserver: NSObjectProtocol?
    /// 예약해 둔 확인. 새 확인이 들어오면 앞의 것은 버린다 — 화면 구성 변경은 한 번에 여러 번 온다.
    private var scheduled: DispatchWorkItem?

    init(
        statusItem: NSStatusItem,
        autosaveName: String,
        store: UserDefaults,
        announce: @escaping @MainActor (SwitchAnnouncement.Message) -> Void
    ) {
        self.statusItem = statusItem
        self.autosaveName = autosaveName
        self.store = store
        self.announce = announce
    }

    /// 실행 직후 한 번, 그리고 화면 구성이 바뀔 때마다 확인한다.
    ///
    /// **주기 타이머를 두지 않는다.** 아이콘이 가려지는 것은 화면이 바뀌는 순간에 일어난다
    /// (외부 모니터를 떼면 노치 있는 화면으로 돌아온다). 그 순간에만 확인하면 충분하고,
    /// 계속 재면 아이콘이 화면 사이를 오갈 때마다 말이 많아진다.
    func start() {
        schedule()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    private func schedule() {
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.confirmThenJudge() }
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    /// 두 번 재서 같은 값일 때만 판정한다.
    private func confirmThenJudge() {
        guard let first = placement() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let second = self.placement(), second == first else { return }
                self.judge(second)
            }
        }
    }

    private func judge(_ placement: StatusItemPlacement) {
        let seat = StatusItemSeat.state(autosaveName: autosaveName, in: store)

        if !placement.isHidden {
            // 보이는 것을 확인했으니 민 횟수를 거둔다 — 나중에 다시 가려지면 그때부터 새로 센다.
            StatusItemSeat.recordVisible(in: store)
            HiddenIconNotice.remember(isHidden: false, in: store)
            return
        }

        // 말하기 전에 한 번 비켜 본다. **밀어서 해결되면 할 말이 없다** — 사용자가 손댈 일이 아니다.
        // 여기서 기억을 남기지 않는 이유: 아직 판정이 끝나지 않았다. 밀고 다시 재서 그때 남긴다.
        if let next = StatusItemSeat.nudgedPosition(placement: placement, state: seat) {
            MenuBarSeat.move(statusItem, to: next, autosaveName: autosaveName, from: seat, store: store)
            schedule()
            return
        }

        if HiddenIconNotice.shouldAnnounce(isHidden: true, lastKnown: HiddenIconNotice.lastKnownHidden(in: store)) {
            announce(SwitchAnnouncement.menuBarIconHidden())
        }
        // 알렸든 아니든 남긴다 — 고친 사실을 잊으면 다음에 다시 가려졌을 때 말하지 못한다.
        HiddenIconNotice.remember(isHidden: true, in: store)
    }

    /// 지금 상태 항목이 어디에 있고, 그 화면에서 그려지는 구간이 어디인가.
    /// 잴 수 없는 값이면 `nil` — 그때는 아무 말도 하지 않고 기억도 남기지 않는다.
    private func placement() -> StatusItemPlacement? {
        guard let window = statusItem.button?.window else { return nil }
        let frame = window.frame
        // 높이가 없는 값은 아직 자리를 잡기 전이다 (위 실측의 첫 줄).
        guard frame.height > 0 else { return nil }
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: frame.minX, maxX: frame.maxX),
            visibleSpans: MenuBarSeat.visibleSpans(of: window.screen)
        )
        return placement.isMeasurable ? placement : nil
    }
}
