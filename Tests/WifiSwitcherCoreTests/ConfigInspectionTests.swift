import Foundation
import Testing
@testable import WifiSwitcherCore

/// 앱이 뜰 때 설정 파일을 어떤 상태로 판단하는가.
///
/// "없다 / 예시 그대로다 / 못 쓴다 / 쓸 수 있다" 를 갈라야 온보딩을 띄울지가 정해진다.
@Suite("설정 파일 상태")
struct ConfigInspectionTests {

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exem-wifi-switcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static let validJSON = """
    {
      "version": 1,
      "service": "Wi-Fi",
      "defaultProfile": "auto",
      "profiles": [
        { "name": "office", "mode": "manual", "ip": "192.0.2.10", "subnet": "255.255.255.0",
          "router": "192.0.2.1", "dns": ["192.0.2.53"], "label": "사내 고정 IP" },
        { "name": "auto", "mode": "dhcp" }
      ]
    }
    """

    @Test("파일이 없으면 없다고 한다")
    func detectsMissing() {
        let status = AppConfig.inspect(path: "/nonexistent/exem-wifi-switcher/config.json")
        #expect(status == .missing(path: "/nonexistent/exem-wifi-switcher/config.json"))
    }

    @Test("쓸 수 있는 설정은 값까지 돌려준다")
    func detectsReady() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("config.json").path
            try Data(Self.validJSON.utf8).write(to: URL(fileURLWithPath: path))
            guard case .ready(let config) = AppConfig.inspect(path: path) else {
                Issue.record("쓸 수 있는 설정으로 판단해야 한다")
                return
            }
            #expect(config.profiles.count == 2)
            #expect(config.profile(named: "office")?.label == "사내 고정 IP")
        }
    }

    @Test("설치 스크립트가 복사한 예시 파일은 '아직 설정 전' 으로 본다")
    func detectsPristineExample() throws {
        // 예시 파일에는 설명용 _readme 키가 있고, 앱이 저장할 때는 그 키가 사라진다.
        // 그래서 이 키의 유무가 "사용자가 한 번이라도 저장했는가" 의 표시가 된다.
        let example = RepositoryLayout.root.appendingPathComponent("config.example.json").path
        #expect(AppConfig.inspect(path: example) == .pristineExample(path: example))
    }

    @Test("깨진 설정은 이유를 담아 못 쓴다고 한다")
    func detectsUnusable() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("config.json").path
            try Data("{ \"profiles\": [], \"defaultProfile\": \"auto\" }".utf8).write(to: URL(fileURLWithPath: path))
            guard case .unusable(_, let reason) = AppConfig.inspect(path: path) else {
                Issue.record("못 쓰는 설정으로 판단해야 한다")
                return
            }
            #expect(!reason.isEmpty)
        }
    }

    @Test("저장은 갈아 끼우기로 한다 — 반쯤 쓰인 설정을 남기지 않는다")
    func savesAtomically() throws {
        // 설치된 설정 파일은 root:wheel 0644 라 앱이 직접 쓰지 못한다(ConfigInstaller 가 인증을 받는다).
        // 이 경로는 이미 root 이거나 테스트일 때만 쓰이며, 그때는 갈아 끼우기가 맞다 —
        // 쓰는 도중에 apply 가 읽어 잘린 JSON 을 보는 창을 없앤다.
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("config.json")
            try Data(Self.validJSON.utf8).write(to: url)

            var config = try AppConfig.load(from: url.path)
            config.profiles[0].ip = "192.0.2.11"
            try config.save(to: url.path)

            #expect(try AppConfig.load(from: url.path).profile(named: "office")?.ip == "192.0.2.11")
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.int16Value == 0o644)
        }
    }

    @Test("표시 이름은 설정을 오갈 때 그대로 남는다")
    func labelSurvivesRoundTrip() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("config.json").path
            let config = AppConfig(
                profiles: [
                    NetworkProfile(name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
                                   router: "192.0.2.1", dns: ["192.0.2.53"], label: "사내 고정 IP"),
                    NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)"),
                ],
                defaultProfile: "auto"
            )
            try config.save(to: path)
            #expect(try AppConfig.load(from: path) == config)
        }
    }

    @Test("표시 이름이 지나치게 길거나 제어 문자를 담으면 거부한다")
    func validatesLabel() {
        let long = NetworkProfile(name: "office", mode: .dhcp, label: String(repeating: "가", count: 40))
        #expect(!long.validate().isEmpty)
        let control = NetworkProfile(name: "office", mode: .dhcp, label: "사내\u{0007}")
        #expect(!control.validate().isEmpty)
    }
}
