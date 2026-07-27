import Foundation
import Testing
@testable import WifiSwitcherCore

/// `.app` 번들 조립 스크립트가 만드는 Info.plist.
///
/// 문자열 대조가 아니라 **스크립트가 실제로 출력한 plist 를 파싱해서** 본다
/// (`./scripts/build-app.sh --print-plist` 는 빌드 없이 plist 만 찍는다).
/// 여기 있는 키 하나가 빠지면 SSID 조회나 메뉴바 동작이 통째로 막히므로 테스트로 못박는다.
@Suite("앱 번들 Info.plist")
struct AppBundleTests {

    private func plist() throws -> [String: Any] {
        let script = RepositoryLayout.root.appendingPathComponent("scripts/build-app.sh").path
        let result = try SystemCommand.run(["/bin/bash", script, "--print-plist"])
        #expect(result.succeeded, "build-app.sh --print-plist 실패: \(result.standardError)")
        let object = try PropertyListSerialization.propertyList(
            from: Data(result.standardOutput.utf8), options: [], format: nil
        )
        return try #require(object as? [String: Any])
    }

    @Test("스크립트가 문법이 올바른 plist 를 만든다")
    func producesValidPlist() throws {
        #expect(!(try plist()).isEmpty)
    }

    @Test("번들 식별자와 이름이 계획 문서의 값과 같다")
    func hasFixedNaming() throws {
        let plist = try plist()
        #expect(plist["CFBundleIdentifier"] as? String == InstallPaths.bundleIdentifier)
        #expect(plist["CFBundleName"] as? String == InstallPaths.appName)
        #expect(plist["CFBundleDisplayName"] as? String == InstallPaths.appName)
        // 실행 파일 이름도 제품명으로 둔다 — 시스템이 실행 파일 이름을 그대로 보여주는 자리가 있다.
        #expect(plist["CFBundleExecutable"] as? String == InstallPaths.appName)
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
    }

    @Test("Dock 에 뜨지 않는 메뉴바 전용 앱이다")
    func isAgentApp() throws {
        #expect(try plist()["LSUIElement"] as? Bool == true)
    }

    @Test("위치 권한 설명이 있고 한국어로 이유를 밝힌다")
    func explainsLocationUsage() throws {
        // 이 키가 없으면 SSID 조회(Phase 3)가 통째로 막힌다. Phase 0 에서 실증된 전제 조건이다.
        let text = try plist()["NSLocationWhenInUseUsageDescription"] as? String ?? ""
        #expect(text.count >= 20)
        #expect(text.contains("Wi-Fi"))
        #expect(text.range(of: "\\p{Hangul}", options: .regularExpression) != nil)
    }

    @Test("아이콘과 최소 시스템 버전을 지정한다")
    func declaresIconAndMinimumSystem() throws {
        let plist = try plist()
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist["LSMinimumSystemVersion"] as? String == "13.0")
    }

    @Test("Xcode 없이 조립하고 ad-hoc 으로 서명한다")
    func buildsWithoutXcode() throws {
        let script = try String(
            contentsOf: RepositoryLayout.root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8
        )
        #expect(script.contains("swift build"))
        #expect(!script.contains("xcodebuild"))
        // 유료 인증서가 없다. ad-hoc(-) 서명으로 번들 식별자에 권한을 귀속시킨다.
        #expect(script.contains("--sign -"))
        #expect(script.contains("codesign --verify"))
    }

    @Test("아이콘이 아직 없어도 조립이 멈추지 않는다")
    func toleratesMissingIcons() throws {
        // 아이콘은 다른 작업으로 만들어진다. 없으면 앱은 SF Symbols 로 대신 그린다.
        let script = try String(
            contentsOf: RepositoryLayout.root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8
        )
        #expect(script.contains("Resources/icons"))
        #expect(script.contains("아이콘"))
    }
}
