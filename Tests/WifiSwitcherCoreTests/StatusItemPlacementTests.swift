import Testing
@testable import WifiSwitcherCore

/// 실측값으로 표를 세운다 (2026-07-29, 노치 있는 내장 화면 · macOS 26.5).
///
/// 화면 1512pt · 노치 663~848 · 상태 항목 폭 63pt. 항목을 **마지막에 만들어** 왼쪽 끝 자리를 잡게 하고,
/// 앞에 상태 항목을 하나씩 더 세워 자리를 왼쪽으로 밀며 쟀다. 각 단계에서 네 번씩 재 값이 흔들리지 않는 것을 확인했다.
///
/// | 앞선 항목 | 항목 x 구간 | 결과 |
/// |---|---|---|
/// | 0개 | 613 ~ 676 | **노치에 걸침** (663 부터 노치) |
/// | 1개 | 528 ~ 591 | 노치 왼쪽 영역 안 |
/// | 2개 | 460 ~ 523 | 노치 왼쪽 영역 안 |
/// | 3개 | 377 ~ 440 | 노치 왼쪽 영역 안 |
/// | 4개 | 292 ~ 355 | 노치 왼쪽 영역 안 |
///
/// 자리가 아예 없을 때는 화면 밖(음수 x)으로 밀리고 `window.screen` 이 `nil` 이 된다 —
/// 그때는 보이는 구간이 하나도 없다.
@Suite("메뉴 막대 아이콘 가려짐 판정")
struct StatusItemPlacementTests {

    /// 실측한 노치 화면. 노치 663 ~ 848.
    private let notched = [MenuBarSpan(minX: 0, maxX: 663), MenuBarSpan(minX: 848, maxX: 1512)]

    @Test("실측 — 앞선 항목이 없으면 노치에 걸린다")
    func straddlesNotch() {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: 613, maxX: 676), visibleSpans: notched
        )
        #expect(placement.isMeasurable)
        #expect(placement.isHidden)
    }

    @Test("실측 — 앞선 항목이 하나만 있어도 노치 왼쪽으로 온전히 들어간다", arguments: [
        (528.0, 591.0), (460.0, 523.0), (377.0, 440.0), (292.0, 355.0),
    ])
    func fitsLeftOfNotch(minX: Double, maxX: Double) {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: minX, maxX: maxX), visibleSpans: notched
        )
        #expect(!placement.isHidden)
    }

    @Test("노치 오른쪽 영역 안이면 보인다")
    func fitsRightOfNotch() {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: 1250, maxX: 1313), visibleSpans: notched
        )
        #expect(!placement.isHidden)
    }

    @Test("노치 안에 통째로 들어가면 가려진 것이다")
    func swallowedByNotch() {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: 700, maxX: 763), visibleSpans: notched
        )
        #expect(placement.isHidden)
    }

    /// 조금이라도 걸치면 가려진 것으로 본다.
    ///
    /// 실측한 613~676 은 63pt 중 13pt 만 노치에 물렸지만, 아이콘은 그보다 좁아서(폭 24pt 안팎)
    /// **같은 자리에서 거의 전부 삼켜진다** — 자리의 오른쪽 끝(676)은 이웃이 정하고 폭만 줄기 때문이다.
    /// 절반을 넘겼는지 재는 대신 걸치면 가려진 것으로 둔다.
    @Test("오른쪽 끝만 물려도 가려진 것이다")
    func partialOverlapCountsAsHidden() {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: 640, maxX: 664), visibleSpans: notched
        )
        #expect(placement.isHidden)
    }

    @Test("경계에 딱 맞으면 보이는 것이다")
    func exactFitIsVisible() {
        #expect(!StatusItemPlacement(
            item: MenuBarSpan(minX: 600, maxX: 663), visibleSpans: notched
        ).isHidden)
        #expect(!StatusItemPlacement(
            item: MenuBarSpan(minX: 848, maxX: 911), visibleSpans: notched
        ).isHidden)
    }

    @Test("노치가 없는 화면은 구간이 하나다")
    func plainScreen() {
        let plain = [MenuBarSpan(minX: 1512, maxX: 4072)]
        #expect(!StatusItemPlacement(
            item: MenuBarSpan(minX: 3171, maxX: 3234), visibleSpans: plain
        ).isHidden)
        #expect(StatusItemPlacement(
            item: MenuBarSpan(minX: -636, maxX: -573), visibleSpans: plain
        ).isHidden)
    }

    @Test("어느 화면에도 없으면 가려진 것이다 — 자리가 없어 밀려난 경우")
    func noScreenAtAll() {
        let placement = StatusItemPlacement(
            item: MenuBarSpan(minX: -1944, maxX: -1881), visibleSpans: []
        )
        #expect(placement.isMeasurable)
        #expect(placement.isHidden)
    }

    /// 상태 항목은 만든 직후 최종 자리를 말하지 않는다 — 실측에서 폭 63pt·**높이 0** 인 값이
    /// 먼저 왔고 0.25초 뒤에야 자리가 정해졌다. 그런 값으로는 판정하지 않는다.
    @Test("폭이 없는 값으로는 판정하지 않는다")
    func degenerateMeasurementIsUnusable() {
        #expect(!StatusItemPlacement(
            item: MenuBarSpan(minX: 0, maxX: 0), visibleSpans: notched
        ).isMeasurable)
        #expect(!StatusItemPlacement(
            item: MenuBarSpan(minX: 100, maxX: 40), visibleSpans: notched
        ).isMeasurable)
    }
}

@Suite("아이콘 가려짐을 언제 알리는가")
struct HiddenIconNoticeTests {

    @Test("처음 가려지면 알린다")
    func firstTime() {
        #expect(HiddenIconNotice.shouldAnnounce(isHidden: true, lastKnown: nil))
    }

    @Test("보이는 상태는 알릴 것이 없다")
    func visibleSaysNothing() {
        #expect(!HiddenIconNotice.shouldAnnounce(isHidden: false, lastKnown: nil))
        #expect(!HiddenIconNotice.shouldAnnounce(isHidden: false, lastKnown: true))
        #expect(!HiddenIconNotice.shouldAnnounce(isHidden: false, lastKnown: false))
    }

    /// 로그인할 때마다 같은 말을 하면 그 알림은 소음이 된다.
    @Test("가려진 채 그대로면 다시 알리지 않는다")
    func staysQuietWhileUnchanged() {
        #expect(!HiddenIconNotice.shouldAnnounce(isHidden: true, lastKnown: true))
    }

    /// 고친 뒤 다시 가려지는 일은 실제로 일어난다 — 외부 모니터를 떼면 노치가 있는 화면으로 돌아온다.
    @Test("고쳤다가 다시 가려지면 그때는 알린다")
    func speaksAgainAfterRecovery() {
        #expect(HiddenIconNotice.shouldAnnounce(isHidden: true, lastKnown: false))
    }
}

/// 숫자를 담아 두는 자리. 테스트에서는 메모리에 담는다.
final class MemoryNumberStore: NumberStore {
    var values: [String: Double] = [:]
    func doubleValue(forKey key: String) -> Double? { values[key] }
    func setDouble(_ value: Double, forKey key: String) { values[key] = value }
}

/// 아이콘을 처음 어디에 놓을 것인가.
///
/// 실측(2026-07-30 · 1512pt 화면 · 노치 663~848)에서 값 → 자리는 아래와 같았다. 세 번씩 재서
/// 모두 같았다. 이 표가 `notchClearance` 의 근거다.
///
/// | 값 | 자리 | | 값 | 자리 |
/// |---|---|---|---|---|
/// | 없음 | 620~657 (노치) | | 544 | 907~944 |
/// | 300 | 1123~1160 | | 620 | 840~877 (노치) |
/// | 450 | 1015~1052 | | 700 | 808~845 (노치) |
/// | 504 | 945~982 | | 800+ | 693~730 (노치) |
@Suite("아이콘 첫 자리 심기")
struct StatusItemSeedTests {

    /// 실측한 내장 화면.
    private let screen = MenuBarSpan(minX: 0, maxX: 1512)
    private let notch = MenuBarSpan(minX: 663, maxX: 848)

    @Test("실측 — 노치 있는 화면에 심는 값은 544 다")
    func seedsMeasuredValue() {
        #expect(StatusItemSeat.seedPosition(stored: nil, screen: screen, notch: notch) == 544)
    }

    /// **이 저장소가 가장 경계하는 실패다.** 덮어쓰면 사용자가 ⌘-드래그로 골라 둔 자리를 빼앗고,
    /// 그 사람에게는 고칠 방법이 남지 않는다.
    @Test("저장된 자리가 있으면 절대 덮어쓰지 않는다")
    func neverOverwritesAStoredSeat() {
        #expect(StatusItemSeat.seedPosition(stored: 720, screen: screen, notch: notch) == nil)
        // 0 도 정한 자리다 — '오른쪽 끝' 이라는 뜻이지 '정한 적 없음' 이 아니다.
        #expect(StatusItemSeat.seedPosition(stored: 0, screen: screen, notch: notch) == nil)
    }

    /// 피할 것이 없는데 자리를 정해 두면, 그 화면에서 자연스럽게 놓였을 자리를 이유 없이 옮기는 셈이다.
    @Test("노치가 없으면 심지 않는다")
    func leavesPlainScreensAlone() {
        #expect(StatusItemSeat.seedPosition(
            stored: nil, screen: MenuBarSpan(minX: 0, maxX: 2560), notch: nil
        ) == nil)
    }

    /// 값은 화면 오른쪽 끝에서 잰 거리다 — 노치가 더 오른쪽에 있는 화면일수록 값이 작아진다.
    @Test("다른 화면에서도 노치 오른쪽 끝에서 같은 거리를 둔다")
    func scalesWithTheScreen() {
        let wide = MenuBarSpan(minX: 0, maxX: 1728)
        let wideNotch = MenuBarSpan(minX: 764, maxX: 964)
        #expect(StatusItemSeat.seedPosition(stored: nil, screen: wide, notch: wideNotch) == 644)
    }

    /// 노치 오른쪽이 여유분보다 좁으면 심을 값이 음수가 된다 — 그런 화면에는 손대지 않는다.
    @Test("노치 오른쪽에 자리가 없으면 심지 않는다")
    func skipsWhenThereIsNoRoom() {
        #expect(StatusItemSeat.seedPosition(
            stored: nil, screen: screen, notch: MenuBarSpan(minX: 1300, maxX: 1450)
        ) == nil)
    }

    @Test("보이는 구간 사이의 빈틈이 노치다")
    func findsTheNotch() {
        let spans = [MenuBarSpan(minX: 0, maxX: 663), MenuBarSpan(minX: 848, maxX: 1512)]
        #expect(StatusItemSeat.notch(between: spans) == MenuBarSpan(minX: 663, maxX: 848))
        #expect(StatusItemSeat.notch(between: [MenuBarSpan(minX: 0, maxX: 2560)]) == nil)
        #expect(StatusItemSeat.notch(between: []) == nil)
    }

    /// 가려진 자리를 고치는 일은 **재고 미는 한 길**로 모았다 (`nudgedPosition`).
    /// 심는 시점에는 상태 항목이 아직 없어 그 자리가 가려지는지 잴 방법이 없기 때문이다.
    @Test("심는 자리에서는 가려짐을 따지지 않는다 — 잴 것이 아직 없다")
    func seedingNeverJudgesVisibility() {
        // 오너의 값 637 은 노치 안에 놓이지만(실측 803~837), 심는 쪽은 그것을 알 길이 없다.
        #expect(StatusItemSeat.seedPosition(stored: 637, screen: screen, notch: notch) == nil)
    }

    @Test("심은 값을 남겨야 나중에 사용자가 옮긴 자리와 구별된다")
    func recordsWhatItPlanted() {
        let store = MemoryNumberStore()
        StatusItemSeat.recordSeed(544, autosaveName: "status-item", in: store)

        let state = StatusItemSeat.state(autosaveName: "status-item", in: store)
        #expect(state.stored == 544)
        #expect(state.appliedByApp == 544)
        #expect(state.nudges == 0)
        #expect(state.isAppPlaced)
        #expect(!state.isUserPlaced(isHidden: false))
    }

    @Test("앱이 심은 값과 다르면 사용자가 옮긴 것이다")
    func detectsAUserMove() {
        let store = MemoryNumberStore()
        StatusItemSeat.recordSeed(544, autosaveName: "status-item", in: store)
        // macOS 는 사용자가 ⌘-드래그로 옮겼을 때만 이 값을 다시 적는다 (실측).
        store.setDouble(300, forKey: StatusItemSeat.preferredPositionKey(autosaveName: "status-item"))

        #expect(StatusItemSeat.state(autosaveName: "status-item", in: store).isUserPlaced(isHidden: false))
    }

    /// 앱이 심은 적이 없는데 값이 있다면, 그것을 적은 것은 사용자뿐이다.
    @Test("앱이 심은 적 없는 값도 사용자가 옮긴 자리다")
    func treatsUnknownSeatsAsTheUsers() {
        let store = MemoryNumberStore()
        store.setDouble(300, forKey: StatusItemSeat.preferredPositionKey(autosaveName: "status-item"))
        #expect(StatusItemSeat.state(autosaveName: "status-item", in: store).isUserPlaced(isHidden: false))
    }
}

/// 저장된 자리의 임자가 누구인가.
///
/// 값을 적은 것과 자리를 고른 것은 다르다. macOS 는 ⌘-드래그 때만 값을 적으므로 앱이 적지 않은 값은
/// 사용자가 적은 것이지만, **그 자리가 가려져 있으면 사용자가 그 자리를 골랐다고 볼 수 없다** —
/// 안 보이는 아이콘을 겨냥해 끌 수는 없기 때문이다.
///
/// 오너의 기계에서 실제로 그랬다 (2026-07-30 실측 · 1512pt 화면 · 노치 663~848).
/// 저장값 637 이 놓이는 자리는 803~837 로 노치 **안**이다. 오너는 그 자리를 본 적이 없다.
@Suite("자리의 임자 가리기")
struct StatusItemSeatOwnerTests {

    /// 앱이 적은 적 없는 값. 적은 것은 사용자다.
    private func userWritten(_ stored: Double, nudges: Int = 0) -> StatusItemSeatState {
        StatusItemSeatState(stored: stored, appliedByApp: nil, nudges: nudges)
    }

    /// **불변식 — 보이는 자리에 있는 사용자 값은 어떤 경우에도 사용자 것이다.**
    @Test("보이는 자리의 사용자 값은 사용자가 고른 자리다")
    func visibleUserSeatBelongsToTheUser() {
        #expect(userWritten(300).isUserPlaced(isHidden: false))
        // 앱이 심어 둔 값을 사용자가 다른 자리로 옮긴 경우.
        #expect(StatusItemSeatState(stored: 300, appliedByApp: 544, nudges: 0).isUserPlaced(isHidden: false))
    }

    @Test("오너 재현 — 가려진 자리는 사용자가 고른 자리로 보지 않는다")
    func hiddenSeatIsNobodysChoice() {
        #expect(!userWritten(637).isUserPlaced(isHidden: true))
    }

    /// 재지 못한 것을 가려졌다고 부르면 멀쩡한 사용자 자리를 빼앗는다.
    @Test("재 본 적이 없으면 사용자 자리로 둔다")
    func unmeasuredSeatStaysTheUsers() {
        #expect(userWritten(300).isUserPlaced(isHidden: nil))
    }

    @Test("앱이 적은 값은 보이든 가려지든 앱 것이다")
    func appSeatIsNeverTheUsers() {
        let seeded = StatusItemSeatState(stored: 544, appliedByApp: 544, nudges: 0)
        #expect(seeded.isAppPlaced)
        #expect(!seeded.isUserPlaced(isHidden: false))
        #expect(!seeded.isUserPlaced(isHidden: true))
    }

    @Test("정한 적 없는 자리는 임자가 없다")
    func noSeatHasNoOwner() {
        let none = StatusItemSeatState(stored: nil, appliedByApp: nil, nudges: 0)
        #expect(!none.isAppPlaced)
        #expect(!none.isUserPlaced(isHidden: false))
        #expect(!none.isUserPlaced(isHidden: nil))
        #expect(!none.isUserPlaced(isHidden: true))
    }
}

/// 심어 둔 자리로도 가려지면 스스로 한 번 비켜난다.
@Suite("가려진 아이콘 밀어내기")
struct StatusItemNudgeTests {

    private let notched = [MenuBarSpan(minX: 0, maxX: 663), MenuBarSpan(minX: 848, maxX: 1512)]

    private func placement(_ minX: Double, _ maxX: Double, spans: [MenuBarSpan]? = nil) -> StatusItemPlacement {
        StatusItemPlacement(item: MenuBarSpan(minX: minX, maxX: maxX), visibleSpans: spans ?? notched)
    }

    private func seeded(_ position: Double, nudges: Int = 0) -> StatusItemSeatState {
        StatusItemSeatState(stored: position, appliedByApp: position, nudges: nudges)
    }

    /// 실측한 값 620 은 840~877 에 놓여 노치(848)에 물렸다. 그 자리에서 미는 계산을 따라간다 —
    /// 노치 오른쪽 구간(848~)에 여유 40 을 두면 888 이 목표고, 840 에서 48 을 가야 하므로 620-48 = 572.
    @Test("실측 — 노치에 물린 자리를 오른쪽 구간으로 민다")
    func pushesOutOfTheNotch() {
        #expect(StatusItemSeat.nudgedPosition(placement: placement(840, 877), state: seeded(620)) == 572)
    }

    @Test("노치 안에 통째로 들어간 자리도 오른쪽 구간으로 민다")
    func pushesOutOfTheNotchEntirely() {
        // 목표 888, 지금 700 → 188 만큼 가야 한다.
        #expect(StatusItemSeat.nudgedPosition(placement: placement(700, 763), state: seeded(800)) == 612)
    }

    @Test("보이는 아이콘은 밀지 않는다")
    func leavesVisibleIconsAlone() {
        #expect(StatusItemSeat.nudgedPosition(placement: placement(907, 944), state: seeded(544)) == nil)
    }

    /// 밀 때마다 다시 재고 또 미는 길이다. 상한이 헐거우면 아이콘이 메뉴 막대를 걸어 다닌다 —
    /// 사용자 눈에는 아이콘이 스스로 도망 다니는 것으로 보인다. **한두 번이 상한이다.**
    @Test("상한은 한두 번을 넘지 않는다")
    func neverWalksTheMenuBar() {
        #expect(StatusItemSeat.nudgeLimit >= 1)
        #expect(StatusItemSeat.nudgeLimit <= 2)
    }

    /// 상한이 없으면 아이콘이 메뉴 막대를 걸어 다닌다.
    @Test("상한을 넘으면 더 밀지 않는다")
    func stopsAtTheLimit() {
        #expect(StatusItemSeat.nudgedPosition(
            placement: placement(840, 877), state: seeded(620, nudges: StatusItemSeat.nudgeLimit - 1)
        ) != nil)
        #expect(StatusItemSeat.nudgedPosition(
            placement: placement(840, 877), state: seeded(620, nudges: StatusItemSeat.nudgeLimit)
        ) == nil)
    }

    /// **불변식 하나 — 보이는 자리에 있는 사용자 값은 어떤 경우에도 건드리지 않는다.**
    /// 이것이 깨지면 사용자가 ⌘-드래그로 골라 둔 자리를 앱이 빼앗는다.
    ///
    /// 자리는 노치 **왼쪽**(실측 528~591 · 온전히 보인다)으로 잡았다. 오른쪽에 넉넉한 구간(848~1512)이
    /// 남아 있어 **밀려면 밀 수 있는** 자리다. 그래서 보임/가려짐 관문이 사라지면 이 검사가 걸린다.
    @Test("보이는 자리의 사용자 값은 밀지 않는다")
    func neverMovesAVisibleUserSeat() {
        let neverSeeded = StatusItemSeatState(stored: 700, appliedByApp: nil, nudges: 0)
        #expect(StatusItemSeat.nudgedPosition(placement: placement(528, 591), state: neverSeeded) == nil)

        let userMoved = StatusItemSeatState(stored: 700, appliedByApp: 544, nudges: 0)
        #expect(StatusItemSeat.nudgedPosition(placement: placement(528, 591), state: userMoved) == nil)
    }

    /// 보임/가려짐 관문이 이 자리를 실제로 막고 있는지 확인한다 — 같은 자리를 **가려진 화면 구성**에
    /// 두면 앱은 민다. 두 검사가 갈라지는 지점이 곧 그 관문이다.
    @Test("같은 자리가 가려진 구성이면 민다 — 앞 검사가 지키는 것이 무엇인지 못박는다")
    func theSameSeatMovesWhenItIsHidden() {
        let neverSeeded = StatusItemSeatState(stored: 700, appliedByApp: nil, nudges: 0)
        // 노치가 528~591 을 삼킨 구성. 보이는 구간은 왼쪽 끝 토막과 오른쪽 구간뿐이다.
        let swallowed = [MenuBarSpan(minX: 0, maxX: 500), MenuBarSpan(minX: 848, maxX: 1512)]
        #expect(StatusItemSeat.nudgedPosition(
            placement: placement(528, 591, spans: swallowed), state: neverSeeded
        ) == 340)
    }

    /// **오너 기계에서 실제로 일어난 일** (2026-07-30 실측 · 1512pt 화면 · 노치 663~848 · 폭 34pt 항목).
    ///
    /// 오너가 ⌘-드래그로 아이콘을 옮겨 macOS 가 637 을 적었다. 그런데 637 이 놓이는 자리는 803~837 로
    /// **노치 안**이다. 옮긴 사람도 그 자리를 본 적이 없으니, 사용자가 고른 자리로 볼 수 없다.
    ///
    /// 미는 계산 — 노치 오른쪽 구간(848~)에 여유 40 을 두면 888 이 목표고, 803 에서 85 를 가야 하므로
    /// 637-85 = 552. 552 는 911~945 에 놓여 보인다 (같은 날 실측, 세 번 재서 모두 같았다).
    @Test("오너 재현 — 가려진 사용자 값은 민다")
    func pushesAHiddenUserSeat() {
        let ownersSeat = StatusItemSeatState(stored: 637, appliedByApp: nil, nudges: 0)
        #expect(StatusItemSeat.nudgedPosition(placement: placement(803, 837), state: ownersSeat) == 552)
    }

    /// 같은 값, 같은 상태인데 자리가 보이면 손대지 않는다. 판정을 가르는 것은 값이 아니라 **잰 결과**다.
    @Test("실측 — 같은 값이 보이는 자리에 있으면 밀지 않는다")
    func leavesTheSameSeatAloneWhenVisible() {
        let ownersSeat = StatusItemSeatState(stored: 637, appliedByApp: nil, nudges: 0)
        #expect(StatusItemSeat.nudgedPosition(placement: placement(911, 945), state: ownersSeat) == nil)
    }

    /// **불변식 둘 — 가려졌다고 무한히 걷게 하지 않는다.** 사용자가 적은 값이어도 상한은 같다.
    @Test("가려진 사용자 값도 상한에서 멈춘다")
    func hiddenUserSeatsStopAtTheLimit() {
        let oneLeft = StatusItemSeatState(
            stored: 637, appliedByApp: nil, nudges: StatusItemSeat.nudgeLimit - 1
        )
        #expect(StatusItemSeat.nudgedPosition(placement: placement(803, 837), state: oneLeft) != nil)

        let atLimit = StatusItemSeatState(
            stored: 637, appliedByApp: nil, nudges: StatusItemSeat.nudgeLimit
        )
        #expect(StatusItemSeat.nudgedPosition(placement: placement(803, 837), state: atLimit) == nil)
    }

    /// 민 값을 앱 것으로 남기지 않으면 다음 판정이 어긋난다 — 자기가 민 자리를 사용자 자리로 읽는다.
    @Test("사용자 값을 밀고 나면 그 자리는 앱이 정한 자리다")
    func takesOverAfterPushing() {
        let store = MemoryNumberStore()
        store.setDouble(637, forKey: StatusItemSeat.preferredPositionKey(autosaveName: "status-item"))
        let before = StatusItemSeat.state(autosaveName: "status-item", in: store)
        StatusItemSeat.recordNudge(552, autosaveName: "status-item", from: before, in: store)

        let after = StatusItemSeat.state(autosaveName: "status-item", in: store)
        #expect(after.stored == 552)
        #expect(after.appliedByApp == 552)
        #expect(after.nudges == 1)
        #expect(after.isAppPlaced)
    }

    /// 앱이 민 뒤에도 자리는 사용자의 것으로 돌아올 수 있다. 보이는 자리로 옮기면 그때부터 손대지 않는다.
    @Test("사용자가 보이는 자리로 옮기면 그때부터 다시 손대지 않는다")
    func handsTheSeatBack() {
        let store = MemoryNumberStore()
        let hidden = StatusItemSeatState(stored: 637, appliedByApp: nil, nudges: 0)
        StatusItemSeat.recordNudge(552, autosaveName: "status-item", from: hidden, in: store)
        // 사용자가 ⌘-드래그로 다시 옮긴다. macOS 가 새 값을 적는다.
        store.setDouble(300, forKey: StatusItemSeat.preferredPositionKey(autosaveName: "status-item"))

        let state = StatusItemSeat.state(autosaveName: "status-item", in: store)
        #expect(state.isUserPlaced(isHidden: false))
        #expect(StatusItemSeat.nudgedPosition(placement: placement(1123, 1160), state: state) == nil)
    }

    /// 값과 좌표의 어긋남은 기계마다 다를 수 있다. 짐작으로 빼면 엉뚱한 자리로 보낸다.
    @Test("심어 둔 값이 없으면 밀지 않는다")
    func needsAKnownSeat() {
        let unknown = StatusItemSeatState(stored: nil, appliedByApp: nil, nudges: 0)
        #expect(StatusItemSeat.nudgedPosition(placement: placement(840, 877), state: unknown) == nil)
    }

    /// 자리가 아예 없어 화면 밖으로 밀려난 항목이다. 밀 자리가 없으니 말로 알리는 수밖에 없다.
    @Test("어느 화면에도 없으면 밀지 않는다")
    func cannotPushWhatIsNowhere() {
        #expect(StatusItemSeat.nudgedPosition(
            placement: placement(-1944, -1881, spans: []), state: seeded(544)
        ) == nil)
    }

    /// 오른쪽 구간이 항목보다 좁으면 밀어도 다시 가려진다.
    @Test("담을 수 없는 구간으로는 밀지 않는다")
    func skipsSpansThatCannotHoldTheItem() {
        let tight = [MenuBarSpan(minX: 0, maxX: 663), MenuBarSpan(minX: 848, maxX: 878)]
        #expect(StatusItemSeat.nudgedPosition(placement: placement(700, 763, spans: tight), state: seeded(800)) == nil)
    }

    /// 값이 0 이면 이미 오른쪽 끝이다. 같은 값을 다시 심으면 아무것도 달라지지 않은 채 횟수만 깎인다.
    @Test("더 갈 곳이 없으면 미는 시늉을 하지 않는다")
    func doesNotFakeAMove() {
        #expect(StatusItemSeat.nudgedPosition(placement: placement(840, 877), state: seeded(0)) == nil)
    }

    @Test("민 값을 남기면 횟수가 올라간다")
    func countsEachPush() {
        let store = MemoryNumberStore()
        StatusItemSeat.recordSeed(544, autosaveName: "status-item", in: store)
        var state = StatusItemSeat.state(autosaveName: "status-item", in: store)

        StatusItemSeat.recordNudge(500, autosaveName: "status-item", from: state, in: store)
        state = StatusItemSeat.state(autosaveName: "status-item", in: store)
        #expect(state.stored == 500)
        #expect(state.nudges == 1)
        // 민 자리도 앱이 심은 자리다 — 사용자가 옮긴 것으로 오해하면 다시 밀지 못한다.
        #expect(state.isAppPlaced)

        StatusItemSeat.recordNudge(460, autosaveName: "status-item", from: state, in: store)
        #expect(StatusItemSeat.state(autosaveName: "status-item", in: store).nudges == 2)
    }

    /// 거두지 않으면 한 기계에서 평생 두 번만 밀 수 있다. 외부 모니터를 뗐다 붙이면 자리는 다시 어그러진다.
    @Test("보이는 것을 확인하면 횟수를 거둔다")
    func forgetsPushesOnceVisible() {
        let store = MemoryNumberStore()
        StatusItemSeat.recordSeed(544, autosaveName: "status-item", in: store)
        let state = StatusItemSeat.state(autosaveName: "status-item", in: store)
        StatusItemSeat.recordNudge(500, autosaveName: "status-item", from: state, in: store)

        StatusItemSeat.recordVisible(in: store)
        #expect(StatusItemSeat.state(autosaveName: "status-item", in: store).nudges == 0)
        // 자리 자체는 그대로다 — 거두는 것은 횟수뿐이다.
        #expect(StatusItemSeat.state(autosaveName: "status-item", in: store).stored == 500)
    }
}

/// `--diagnose` 가 메뉴 막대에 대해 말하는 한 줄.
@Suite("진단 — 메뉴 막대 아이콘")
struct MenuBarSeatReportTests {

    private let seeded = StatusItemSeatState(stored: 544, appliedByApp: 544, nudges: 0)

    @Test("가려졌으면 고치는 방법까지 말한다")
    func tellsHowToFixIt() {
        let text = MenuBarSeatReport.text(lastKnownHidden: true, state: seeded, hasNotch: true)
        #expect(text.hasPrefix("가려짐: "))
        #expect(text.contains("⌘"))
        #expect(text.contains("오른쪽으로 끌어"))
    }

    @Test("보이면 자리를 말한다")
    func tellsWhereItSits() {
        let text = MenuBarSeatReport.text(lastKnownHidden: false, state: seeded, hasNotch: true)
        #expect(text.hasPrefix("보임 "))
        #expect(text.contains("오른쪽 끝에서 544pt"))
        #expect(text.contains("앱이 정한 위치"))
        // 고칠 것이 없는데 고치는 방법을 말하지 않는다.
        #expect(!text.contains("⌘"))
    }

    /// **없는 값을 지어내지 않는다.** 앱을 띄운 적이 없으면 잰 좌표도 없다.
    @Test("잰 적이 없으면 없다고 말한다")
    func admitsWhenItHasNothing() {
        let text = MenuBarSeatReport.text(
            lastKnownHidden: nil,
            state: StatusItemSeatState(stored: nil, appliedByApp: nil, nudges: 0),
            hasNotch: true
        )
        #expect(text.hasPrefix("확인한 적 없음: "))
        #expect(text.contains("위치를 정한 적 없음"))
        #expect(!text.contains("마지막 확인"))
    }

    @Test("사용자가 옮긴 자리는 그렇다고 말한다")
    func namesWhoMovedIt() {
        let text = MenuBarSeatReport.text(
            lastKnownHidden: false,
            state: StatusItemSeatState(stored: 300, appliedByApp: 544, nudges: 0),
            hasNotch: true
        )
        #expect(text.contains("오른쪽 끝에서 300pt · 사용자가 옮긴 위치"))
    }

    /// 진단의 말과 앱의 판정이 어긋나면, 진단을 읽고도 왜 아이콘이 움직였는지 알 수 없다.
    /// 가려진 자리는 앱이 지켜 주지 않으므로 사용자 자리라고 말하지 않는다.
    @Test("가려진 채 남은 사용자 값은 사용자 자리라고 말하지 않는다")
    func doesNotCallAHiddenSeatTheUsersChoice() {
        let text = MenuBarSeatReport.text(
            lastKnownHidden: true,
            state: StatusItemSeatState(stored: 637, appliedByApp: nil, nudges: 2),
            hasNotch: true
        )
        #expect(text.contains("오른쪽 끝에서 637pt · 사용자가 옮겼지만 가려진 위치"))
    }

    @Test("밀어 본 적이 있으면 몇 번 밀었는지 말한다")
    func reportsPushes() {
        let text = MenuBarSeatReport.text(
            lastKnownHidden: true,
            state: StatusItemSeatState(stored: 460, appliedByApp: 460, nudges: 2),
            hasNotch: true
        )
        #expect(text.contains("앱이 2번 옮겨 봄"))
    }

    @Test("노치 유무는 지금 재서 말하고, 못 재면 말하지 않는다")
    func speaksOnlyOfScreensItCanSee() {
        #expect(MenuBarSeatReport.text(lastKnownHidden: false, state: seeded, hasNotch: false)
            .contains("노치 없는 화면"))
        let unknown = MenuBarSeatReport.text(lastKnownHidden: false, state: seeded, hasNotch: nil)
        #expect(!unknown.contains("노치"))
    }
}
