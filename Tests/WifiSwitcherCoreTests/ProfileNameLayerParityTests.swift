import Foundation
import Testing
@testable import WifiSwitcherCore

/// 프로필 이름 규칙은 세 곳에 있다 (다층 방어).
///
///   1. `ProfileName.isValid`            — 앱이 명령을 만들기 전
///   2. `scripts/apply` 의 `validate_profile_name` — root 로 실행된 직후
///   3. `/etc/sudoers.d/…` 의 인자 패턴   — sudo 가 실행 자체를 거부
///
/// **개수를 세는 것만으로는 세 벌이 어긋나는 것을 못 잡는다.** 예를 들어 1번에서 `.` 하나를
/// 허용하도록 바꿔도 패턴 개수는 그대로다. 그래서 여기서는 같은 입력 배열을 세 계층에 그대로
/// 먹이고 **판정이 한 글자도 어긋나지 않는지** 대조한다.
///
/// 어긋나면 어느 쪽이 옳은지는 이 테스트가 정하지 않는다 — 세 곳을 함께 고치라는 신호다.
@Suite("프로필 이름 3계층 판정 일치")
struct ProfileNameLayerParityTests {

    /// 세 계층에 똑같이 먹이는 입력. 허용될 것과 막혀야 할 것을 섞어 둔다.
    ///
    /// NUL 문자는 argv 로 하위 프로세스에 전달할 수 없어 여기 넣지 않는다
    /// (`ProfileNameTests` 가 Swift 계층에서 따로 막는다).
    static let corpus: [String] = [
        // 통과해야 하는 것
        "office", "auto", "dhcp", "home", "a", "A", "Z0", "x-y_z", "office2",
        "abcdefghijklmnop", "0", "9z", "A_B-C",
        // 길이 경계
        "abcdefghijklmnopq", "abcdefghijklmno",
        // 셸 메타문자·인젝션
        "office; rm -rf /", "office;id", "office && id", "office|id", "office&id",
        "$(id)", "`id`", "${HOME}", "office$x", "office\"x", "office'x",
        "office>out", "office<in", "office\\x",
        // 경로 탈출
        "../../etc/passwd", "/etc/sudoers", "./apply", "office/../auto", "office.json", ".office",
        // 글롭
        "*", "office*", "office?", "of[fi]ce", "office~", "office[",
        // 공백·제어문자
        "", " ", "office name", "office\t", "office\n", " office", "office ",
        // 시작 문자 규칙
        "-office", "_office", "-", "_",
        // 비 ASCII
        "사무실", "офис", "office\u{00A0}x", "café",
    ]

    private static func repositoryScript(_ relativePath: String) -> String {
        RepositoryLayout.root.appendingPathComponent(relativePath).path
    }

    /// 아래 두 계층을 한 번의 프로세스로 돌린다 (install.sh --dry-run 이 느려 매번 부르지 않는다).
    private static func lowerLayerVerdicts(for names: [String]) throws -> [(apply: Bool, sudoers: Bool)] {
        let result = try SystemCommand.run(
            ["/bin/bash", repositoryScript("Tests/shell/name-layers.sh")] + names
        )
        guard result.succeeded else {
            throw ParityFailure(description: "name-layers.sh 실패\n\(result.standardOutput)\n\(result.standardError)")
        }
        let lines = result.standardOutput.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
        guard lines.count == names.count else {
            throw ParityFailure(description: "판정 줄 수가 입력 수와 다릅니다 (\(lines.count) ≠ \(names.count))")
        }
        return lines.map { line in
            let parts = line.split(separator: " ")
            return (apply: parts.first == "1", sudoers: parts.last == "1")
        }
    }

    private struct ParityFailure: Error, CustomStringConvertible {
        let description: String
    }

    @Test("같은 입력에 세 계층이 같은 판정을 낸다")
    func layersAgree() throws {
        let verdicts = try Self.lowerLayerVerdicts(for: Self.corpus)

        var mismatches: [String] = []
        for (name, verdict) in zip(Self.corpus, verdicts) {
            let swift = ProfileName.isValid(name)
            guard swift == verdict.apply, swift == verdict.sudoers else {
                mismatches.append(
                    "'\(name.debugDescription)' — Swift \(swift) / apply \(verdict.apply) / sudoers \(verdict.sudoers)"
                )
                continue
            }
        }
        #expect(mismatches.isEmpty, Comment(rawValue: "세 계층의 판정이 어긋납니다:\n" + mismatches.joined(separator: "\n")))
    }

    @Test("입력 목록에 통과·차단이 모두 들어 있다")
    func corpusExercisesBothVerdicts() throws {
        // 전부 거부되는 목록이면 "세 계층이 일치한다" 는 아무것도 보증하지 않는다.
        let accepted = Self.corpus.filter { ProfileName.isValid($0) }
        let rejected = Self.corpus.filter { !ProfileName.isValid($0) }
        #expect(accepted.count >= 10)
        #expect(rejected.count >= 20)
    }

    /// 이 테스트 자체가 살아 있는지 확인한다.
    /// 규칙을 한 글자 넓힌 가짜 계층을 만들면 대조가 **반드시** 깨져야 한다.
    @Test("규칙이 한 곳에서만 넓어지면 대조가 깨진다")
    func detectsSingleLayerDrift() throws {
        // ProfileName.isValid 에 '.' 을 허용한 것과 같은 상태를 흉내낸다.
        func loosened(_ name: String) -> Bool {
            ProfileName.isValid(name) || ProfileName.isValid(name.replacingOccurrences(of: ".", with: ""))
                && name.contains(".") && !name.hasPrefix(".")
        }
        let drifted = Self.corpus.filter { loosened($0) != ProfileName.isValid($0) }
        #expect(drifted.contains("office.json"), "가짜 드리프트를 만들지 못하면 이 대조는 의미가 없다")

        let verdicts = try Self.lowerLayerVerdicts(for: ["office.json"])
        #expect(verdicts[0].apply == false)
        #expect(verdicts[0].sudoers == false)
    }
}
