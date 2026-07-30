import Foundation
import Testing
@testable import WifiSwitcherCore

/// CLI `validate` 가 앱과 같은 답을 말하는가.
///
/// 예전에는 갈라졌다 — 설치 직후 예시 그대로인 파일을 앱은 `아직 저장 안 됨` 으로,
/// CLI 는 `설정 파일이 유효합니다` 로 말했다. 손으로 값을 고친 사람은 CLI 를 믿고
/// 앱이 왜 안 도는지 알 방법이 없었다. 그 갈라짐이 다시 생기지 않게 붙잡는다.
@Suite("설정 검증 보고 (CLI validate)")
struct ConfigValidationReportTests {

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
          "router": "192.0.2.1", "dns": ["192.0.2.53"] },
        { "name": "auto", "mode": "dhcp" }
      ]
    }
    """

    private static var examplePath: String {
        RepositoryLayout.root.appendingPathComponent("config.example.json").path
    }

    private func write(_ json: String, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent("config.json").path
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - 앱과 같은 판정을 쓴다

    @Test("판정은 앱이 보는 것과 같은 값이다 — 새로 만들지 않는다")
    func reusesAppVerdict() throws {
        try withTemporaryDirectory { directory in
            let path = try write(Self.validJSON, in: directory)
            #expect(ConfigValidationReport.make(path: path).status == AppConfig.inspect(path: path))
        }
        let example = Self.examplePath
        #expect(ConfigValidationReport.make(path: example).status == AppConfig.inspect(path: example))
        #expect(ConfigValidationReport.make(path: "/nonexistent/exem/config.json").status
                == AppConfig.inspect(path: "/nonexistent/exem/config.json"))
    }

    // MARK: - 상태별로 무엇을 말하는가

    @Test("사용자가 저장한 설정은 유효하다고 말하고, 쓸 수 있다고 판정한다")
    func reportsReady() throws {
        try withTemporaryDirectory { directory in
            let path = try write(Self.validJSON, in: directory)
            let report = ConfigValidationReport.make(path: path)
            #expect(report.isReadyForApp)
            let text = report.lines.joined(separator: "\n")
            #expect(text.contains("유효합니다"))
            #expect(text.contains("Wi-Fi"))
            #expect(text.contains("프로필 2개"))
            #expect(text.contains("기본 프로필: auto"))
            // 쓸 수 있는 설정에 "지우세요" 같은 조치가 붙으면 안 된다.
            #expect(!text.contains("_readme"))
        }
    }

    @Test("예시 그대로인 파일은 '유효합니다' 로 끝내지 않는다 — 앱은 이것을 쓰지 않는다")
    func refusesToCallPristineExampleValid() throws {
        try withTemporaryDirectory { directory in
            // 설치 직후의 파일이 곧 예시 파일이다 (install.sh 가 그대로 복사한다).
            let example = try String(contentsOfFile: Self.examplePath, encoding: .utf8)
            let path = try write(example, in: directory)

            let report = ConfigValidationReport.make(path: path)
            #expect(!report.isReadyForApp)

            let text = report.lines.joined(separator: "\n")
            // 형식이 맞다는 사실은 말해 준다 — AppConfig.load 는 이 파일을 통과시킨다.
            #expect((try? AppConfig.load(from: path)) != nil)
            #expect(text.contains("형식은 유효합니다"))
            // 그러나 판정은 앱과 같아야 한다.
            #expect(text.contains("아직 사용자 값이 아닙니다"))
            #expect(text.contains("_readme"))
            #expect(text.contains("자동 전환"))
        }
    }

    @Test("파일이 없으면 없다고 말하고 [설치] 로 안내한다")
    func reportsMissing() {
        let report = ConfigValidationReport.make(path: "/nonexistent/exem/config.json")
        #expect(!report.isReadyForApp)
        let text = report.lines.joined(separator: "\n")
        #expect(text.contains("설정 파일이 없습니다"))
        #expect(text.contains("[설치]"))
    }

    @Test("깨진 설정은 이유를 그대로 옮긴다")
    func reportsUnusable() throws {
        try withTemporaryDirectory { directory in
            let path = try write("{ \"profiles\": [], \"defaultProfile\": \"auto\" }", in: directory)
            let report = ConfigValidationReport.make(path: path)
            #expect(!report.isReadyForApp)
            let text = report.lines.joined(separator: "\n")
            #expect(text.contains("쓸 수 없습니다"))
            #expect(text.contains("이유:"))
        }
    }

    // MARK: - 함정을 설명하는 자리가 실제로 있는가

    @Test("예시 파일이 '_readme 를 지워라' 를 스스로 말한다")
    func exampleFileWarnsAboutItsOwnReadmeBlock() throws {
        // README·install.sh 는 `sudo nano …/config.json` 을 안내한다. 그 길로 들어온 사람이
        // 파일 안에서 이 한 줄을 만나지 못하면, 값을 고쳐도 앱이 무시하는 이유를 알 수 없다.
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.examplePath))
        let object = try JSONSerialization.jsonObject(with: data)
        let readme = (object as? [String: Any])?["_readme"] as? [String]
        guard let readme, let last = readme.last else {
            Issue.record("예시 파일에 _readme 블록이 없습니다")
            return
        }
        #expect(last.contains("_readme"))
        #expect(last.contains("지우"))
    }
}
