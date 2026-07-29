import Foundation
import Testing
@testable import WifiSwitcherCore

/// 설정 창에서 시스템 설정으로 보냈다가 **돌아오는 길**.
///
/// 이 판정이 코어에 있는 이유는, 창을 앞으로 내는 것보다 **언제 내지 않을지**가 어렵기 때문이다.
/// 조건 하나를 빠뜨리면 사용자가 다른 앱에서 일하는 중에 창이 튀어나온다 — 실기에서 거부당한
/// 동작이 그것이다. 조건은 값으로만 이루어져 있으므로 창 없이 전부 재 볼 수 있다.
@Suite("시스템 설정에 다녀오는 길")
struct SystemSettingsTripTests {

    private static let systemSettings = SystemSettingsTrip.systemSettingsBundleIdentifier

    // MARK: - 되돌리는 자리

    @Test("우리가 연 시스템 설정이 끝나면 창을 되돌린다")
    func returnsWhenTheSystemSettingsWeOpenedIsGone() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        let comesBack = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(comesBack)
    }

    /// 시스템 설정은 우리 말고도 열린다 — 메뉴바 메뉴에도 같은 자리로 가는 길이 있고,
    /// 사용자가 직접 열어 둘 수도 있다. **우리가 보낸 것이 아니면 돌아올 자리도 없다.**
    @Test("우리가 열지 않았으면 아무 일도 하지 않는다")
    func staysStillWhenWeDidNotSend() {
        var trip = SystemSettingsTrip()
        let comesBack = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(comesBack == false)
    }

    @Test("다른 앱이 끝난 것은 신호가 아니다")
    func ignoresOtherApplications() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        let onFinder = trip.shouldBringWindowBack(terminatedApp: "com.apple.finder", isWindowOpen: true)
        #expect(onFinder == false)
        // 표식은 남아 있다 — 시스템 설정은 아직 열려 있다.
        let onSystemSettings = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(onSystemSettings)
    }

    @Test("식별자를 모르는 앱이 끝난 것도 신호가 아니다")
    func ignoresApplicationsWithoutIdentifier() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        let onUnknown = trip.shouldBringWindowBack(terminatedApp: nil, isWindowOpen: true)
        #expect(onUnknown == false)
        let onSystemSettings = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(onSystemSettings)
    }

    // MARK: - 한 번만

    /// **이것이 이 타입의 존재 이유다.** 한 번 다녀온 뒤에도 표식이 남아 있으면, 나중에 사용자가
    /// 직접 열어 본 시스템 설정을 닫을 때 창이 다시 튀어나온다 — 그때 사용자는 다른 일을 하고 있다.
    @Test("한 번 되돌린 뒤에는 다시 되돌리지 않는다")
    func returnsOnlyOnce() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        let first = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        let second = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(first)
        #expect(second == false)
    }

    @Test("다시 열면 다시 한 번 되돌린다")
    func armsAgainOnTheNextTrip() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        _ = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        trip.didOpenSystemSettings()
        let comesBackAgain = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(comesBackAgain)
    }

    // MARK: - 돌아올 자리가 없을 때

    /// 사용자가 그 사이 설정 창을 닫았으면 볼 일이 끝난 것이다. 닫은 창을 되살리지 않는다.
    @Test("설정 창이 닫혀 있으면 되돌리지 않는다")
    func doesNotReopenAClosedWindow() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        let comesBack = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: false)
        #expect(comesBack == false)
    }

    /// 창이 닫혀 있어 되돌리지 못한 것도 **다녀온 것은 다녀온 것이다.** 표식을 남겨 두면
    /// 창을 다시 연 뒤 엉뚱한 시점에 튀어나온다.
    @Test("되돌리지 못한 길도 그 자리에서 접는다")
    func closesTheTripEvenWhenItCannotReturn() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        _ = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: false)
        let later = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(later == false)
    }

    @Test("설정 창을 닫으면 다녀오던 길도 접는다")
    func closingTheWindowEndsTheTrip() {
        var trip = SystemSettingsTrip()
        trip.didOpenSystemSettings()
        trip.didCloseWindow()
        let comesBack = trip.shouldBringWindowBack(terminatedApp: Self.systemSettings, isWindowOpen: true)
        #expect(comesBack == false)
    }
}
