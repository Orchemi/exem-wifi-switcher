import Foundation
import Testing
@testable import WifiSwitcherCore

/// 설정 창 머리말이 **저장 전과 저장 후를 가르는가.**
///
/// 실기에서 난 일: 사내에서 창을 열면 앱이 지금 구성을 읽어 다섯 칸을 채우는데,
/// 그 화면이 저장을 마친 화면과 똑같이 보였다. 사용자는 끝난 줄 알았고 메뉴만
/// 계속 '초기 설정하기' 였다 — 설정 파일은 설치가 놓아둔 예시 그대로였다.
@Suite("설정 창 머리말")
struct SettingsIntroTests {

    @Test("저장된 값을 보고 있으면 저장됐다고 말한다")
    func saysSavedWhenShowingStoredProfile() {
        let intro = SettingsIntro.resolve(
            hasSavedProfile: true, isOfficeConfiguration: true, hasValues: true, configFailure: nil
        )
        #expect(intro == .saved)
    }

    /// **이 한 줄이 이번 고장의 답이다.** 값이 차 있어도 저장 전이면 그렇다고 말한다.
    @Test("지금 구성을 읽어 채운 값은 저장 전이라고 말한다")
    func saysUnsavedWhenValuesCameFromCurrentConfiguration() {
        let intro = SettingsIntro.resolve(
            hasSavedProfile: false, isOfficeConfiguration: true, hasValues: true, configFailure: nil
        )
        #expect(intro == .unsavedFromCurrentConfiguration)
        #expect(intro.text.contains("아직 저장 안 됨"))
    }

    @Test("사외에서 손으로 넣은 값도 저장 전이라고 말한다")
    func saysUnsavedForHandTypedValues() {
        let intro = SettingsIntro.resolve(
            hasSavedProfile: false, isOfficeConfiguration: false, hasValues: true, configFailure: nil
        )
        #expect(intro == .unsaved)
        #expect(intro.text.contains("아직 저장 안 됨"))
    }

    @Test("채울 값이 없으면 언제 채워지는지 말한다")
    func tellsWhenValuesWillArrive() {
        let intro = SettingsIntro.resolve(
            hasSavedProfile: false, isOfficeConfiguration: false, hasValues: false, configFailure: nil
        )
        #expect(intro == .nothingToFillYet)
    }

    /// 읽지 못한 파일을 두고 '저장됐다/안 됐다' 를 말하면 둘 다 믿을 수 없게 된다.
    @Test("설정 파일을 읽지 못한 것이 언제나 먼저다")
    func unreadableConfigWinsOverEverything() {
        let intro = SettingsIntro.resolve(
            hasSavedProfile: true, isOfficeConfiguration: true, hasValues: true,
            configFailure: "형식이 올바르지 않습니다"
        )
        #expect(intro == .unreadableConfig("형식이 올바르지 않습니다"))
        #expect(intro.text.contains("형식이 올바르지 않습니다"))
    }

    /// 저장 전 화면과 저장 후 화면이 **같은 문구를 쓰면** 이 줄은 아무것도 가르지 못한다.
    @Test("저장 전과 저장 후는 다른 문구다")
    func savedAndUnsavedNeverShareWording() {
        let saved = SettingsIntro.saved.text
        for unsaved in [SettingsIntro.unsavedFromCurrentConfiguration, .unsaved] {
            #expect(unsaved.text != saved)
            #expect(unsaved.text.contains("저장 안 됨"))
            #expect(!saved.contains("저장 안 됨"))
        }
    }
}
