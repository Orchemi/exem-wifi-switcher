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
