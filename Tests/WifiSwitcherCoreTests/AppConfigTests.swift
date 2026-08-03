import Foundation
import Testing
@testable import WifiSwitcherCore

@Suite("설정 파일")
struct AppConfigTests {

    private static let validJSON = """
    {
      "version": 1,
      "service": "Wi-Fi",
      "defaultProfile": "auto",
      "profiles": [
        { "name": "office", "mode": "manual", "ip": "192.0.2.10", "subnet": "255.255.255.0",
          "router": "192.0.2.1", "dns": ["192.0.2.53"], "ssids": ["EXAMPLE-AP"] },
        { "name": "auto", "mode": "dhcp", "dns": [], "ssids": [] }
      ]
    }
    """

    /// 임시 디렉터리에서 파일을 다룬다. 실제 설치 경로(/usr/local/etc)는 테스트에서 건드리지 않는다.
    private func withTemporaryFile(contents: String, _ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exem-wifi-switcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("config.json")
        try Data(contents.utf8).write(to: file)
        try body(file.path)
    }

    @Test("정상 설정을 읽는다")
    func loadsValidConfig() throws {
        try withTemporaryFile(contents: Self.validJSON) { path in
            let config = try AppConfig.load(from: path)
            #expect(config.service == "Wi-Fi")
            #expect(config.profiles.count == 2)
            #expect(config.defaultProfile == "auto")
            #expect(config.profile(named: "office")?.mode == .manual)
        }
    }

    @Test("레포의 config.example.json 이 그대로 통과한다")
    func exampleConfigIsValid() throws {
        let example = RepositoryLayout.root.appendingPathComponent("config.example.json")
        let config = try AppConfig.load(from: example.path)
        #expect(config.validate().isEmpty)
        #expect(config.profile(named: config.defaultProfile) != nil)
    }

    @Test("파일이 없으면 그렇게 알린다")
    func reportsMissingFile() {
        #expect(throws: (any Error).self) {
            try AppConfig.load(from: "/nonexistent/exem-wifi-switcher/config.json")
        }
    }

    @Test("형식이 깨진 JSON 은 거부한다")
    func rejectsMalformedJSON() throws {
        try withTemporaryFile(contents: "{ this is not json") { path in
            #expect(throws: (any Error).self) { try AppConfig.load(from: path) }
        }
    }

    @Test("검증에 실패하는 설정은 읽어들이지 않는다")
    func rejectsInvalidConfig() throws {
        let json = """
        {
          "version": 1, "service": "Wi-Fi", "defaultProfile": "auto",
          "profiles": [
            { "name": "office", "mode": "manual", "ip": "192.0.2.10",
              "subnet": "255.255.255.0", "router": "198.51.100.1" }
          ]
        }
        """
        try withTemporaryFile(contents: json) { path in
            #expect(throws: (any Error).self) { try AppConfig.load(from: path) }
        }
    }

    @Test("프로필 이름이 중복되면 잡는다")
    func detectsDuplicateProfileNames() {
        let config = AppConfig(
            profiles: [NetworkProfile(name: "auto", mode: .dhcp), NetworkProfile(name: "auto", mode: .dhcp)],
            defaultProfile: "auto"
        )
        #expect(config.validate().contains(.duplicateProfileName("auto")))
    }

    @Test("같은 SSID 가 두 프로필에 있으면 잡는다")
    func detectsDuplicateSSIDs() {
        let config = AppConfig(
            profiles: [
                NetworkProfile(name: "a", mode: .dhcp, ssids: ["SAME"]),
                NetworkProfile(name: "b", mode: .dhcp, ssids: ["SAME"]),
            ],
            defaultProfile: "a"
        )
        #expect(config.validate().contains(.duplicateSSID("SAME")))
    }

    @Test("기본 프로필이 목록에 없으면 잡는다")
    func detectsUnknownDefaultProfile() {
        let config = AppConfig(profiles: [NetworkProfile(name: "auto", mode: .dhcp)], defaultProfile: "office")
        #expect(config.validate().contains(.unknownDefaultProfile("office")))
    }

    /// 기본 프로필은 **어느 SSID 에도 걸리지 않을 때** 적용된다 — 집·카페·호텔이 전부 여기로 온다.
    /// 그 자리에 고정 IP 프로필이 앉으면 등록하지 않은 모든 네트워크에 사내 IP·DNS 가 걸린다.
    @Test("기본 프로필이 고정 IP 프로필이면 잡는다")
    func detectsManualDefaultProfile() {
        let config = AppConfig(
            profiles: [
                NetworkProfile(
                    name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
                    router: "192.0.2.1", dns: ["192.0.2.53"], ssids: ["EXAMPLE-AP"]
                ),
                NetworkProfile(name: "auto", mode: .dhcp),
            ],
            defaultProfile: "office"
        )
        #expect(config.validate().contains(.manualDefaultProfile("office")))
    }

    @Test("기본 프로필이 DHCP 프로필이면 통과한다")
    func acceptsDHCPDefaultProfile() {
        let config = AppConfig(
            profiles: [
                NetworkProfile(
                    name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
                    router: "192.0.2.1", dns: ["192.0.2.53"], ssids: ["EXAMPLE-AP"]
                ),
                NetworkProfile(name: "auto", mode: .dhcp),
            ],
            defaultProfile: "auto"
        )
        #expect(config.validate().isEmpty)
    }

    /// 존재하지 않는 이름은 **예전 그대로** `unknownDefaultProfile` 이다.
    /// 새 규칙이 그 판정을 가로채면 "이름이 틀렸다" 를 "고정 IP 다" 로 잘못 안내하게 된다.
    @Test("기본 프로필 이름이 없을 때는 모드 규칙이 끼어들지 않는다")
    func unknownDefaultProfileStaysUnknown() {
        let config = AppConfig(profiles: [NetworkProfile(name: "auto", mode: .dhcp)], defaultProfile: "nowhere")
        let errors = config.validate()
        #expect(errors.contains(.unknownDefaultProfile("nowhere")))
        #expect(!errors.contains(.manualDefaultProfile("nowhere")))
    }

    @Test("고정 IP 를 기본 프로필로 둔 설정은 읽어들이지 않는다")
    func refusesLoadingManualDefaultProfile() throws {
        let json = """
        {
          "version": 1, "service": "Wi-Fi", "defaultProfile": "office",
          "profiles": [
            { "name": "office", "mode": "manual", "ip": "192.0.2.10", "subnet": "255.255.255.0",
              "router": "192.0.2.1", "dns": ["192.0.2.53"], "ssids": ["EXAMPLE-AP"] },
            { "name": "auto", "mode": "dhcp", "dns": [], "ssids": [] }
          ]
        }
        """
        try withTemporaryFile(contents: json) { path in
            #expect(throws: (any Error).self) { try AppConfig.load(from: path) }
        }
    }

    @Test("프로필이 하나도 없으면 잡는다")
    func detectsEmptyProfileList() {
        let config = AppConfig(profiles: [], defaultProfile: "auto")
        #expect(config.validate().contains(.emptyProfileList))
    }

    @Test("모르는 버전은 거부한다")
    func detectsUnsupportedVersion() {
        let config = AppConfig(version: 99, profiles: [NetworkProfile(name: "auto", mode: .dhcp)], defaultProfile: "auto")
        #expect(config.validate().contains(.unsupportedVersion(99)))
    }

    @Test("서비스 이름 형태를 본다")
    func validatesServiceName() {
        #expect(AppConfig.isValidServiceName("Wi-Fi"))
        #expect(AppConfig.isValidServiceName("USB 10/100/1000 LAN"))
        #expect(!AppConfig.isValidServiceName(""))
        #expect(!AppConfig.isValidServiceName(" Wi-Fi"))
        #expect(!AppConfig.isValidServiceName("Wi-Fi\nEthernet"))
        #expect(!AppConfig.isValidServiceName(String(repeating: "x", count: 65)))
    }

    @Test("SSID 로 프로필을 고른다")
    func selectsProfileBySSID() throws {
        try withTemporaryFile(contents: Self.validJSON) { path in
            let config = try AppConfig.load(from: path)
            #expect(config.profile(forSSID: "EXAMPLE-AP")?.name == "office")
            #expect(config.profile(forSSID: "카페-와이파이")?.name == "auto")
            #expect(config.profile(forSSID: nil)?.name == "auto")
            // SSID 는 바이트열이라 대소문자가 다르면 다른 네트워크다.
            #expect(config.profile(forSSID: "example-ap")?.name == "auto")
        }
    }

    @Test("저장한 설정을 다시 읽으면 같다")
    func roundTripsThroughDisk() throws {
        try withTemporaryFile(contents: Self.validJSON) { path in
            let original = try AppConfig.load(from: path)
            try original.save(to: path)
            let reloaded = try AppConfig.load(from: path)
            #expect(reloaded == original)
        }
    }

    @Test("검증에 실패하는 설정은 저장하지 않는다")
    func refusesToSaveInvalidConfig() throws {
        try withTemporaryFile(contents: Self.validJSON) { path in
            let broken = AppConfig(profiles: [NetworkProfile(name: "bad name", mode: .dhcp)], defaultProfile: "bad name")
            #expect(throws: (any Error).self) { try broken.save(to: path) }
            // 원본이 그대로 남아 있어야 한다.
            let untouched = try AppConfig.load(from: path)
            #expect(untouched.profiles.count == 2)
        }
    }
}
