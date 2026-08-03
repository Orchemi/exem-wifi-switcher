import Foundation
import Testing
@testable import WifiSwitcherCore

/// 외부 프로세스를 실제로 띄워 확인한다. 여기서 부르는 것은 전부 **읽기 전용 도구**라
/// 시스템 상태를 바꾸지 않는다 (`/bin/sleep` · `/bin/echo` · `/usr/bin/env` · `/usr/bin/awk`).
@Suite("외부 프로세스 실행")
struct SystemCommandTests {

    // MARK: - 타임아웃

    @Test("응답하지 않는 명령은 상한에서 끊는다")
    func timesOutOnHangingCommand() {
        let started = Date()
        let error = #expect(throws: SystemCommand.RunError.self) {
            try SystemCommand.run(["/bin/sleep", "30"], timeout: 0.4)
        }

        guard case .timedOut(let path, let seconds)? = error else {
            Issue.record("타임아웃이 아니라 다른 오류가 났습니다: \(String(describing: error))")
            return
        }
        #expect(path == "/bin/sleep")
        #expect(seconds == 0.4)
        // 상한을 넘겨 매달려 있으면 안 된다. 죽이고 돌아오는 데 드는 시간까지 감안해도 넉넉한 값이다.
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("상한 안에 끝나는 명령은 그대로 결과를 돌려준다")
    func returnsBeforeTimeout() throws {
        let result = try SystemCommand.run(["/bin/sleep", "0"], timeout: 10)
        #expect(result.succeeded)
    }

    @Test("상한에 걸린 프로세스는 실제로 죽는다")
    func killsTimedOutProcess() throws {
        // 셸을 경유하지 않으므로 표식을 붙일 자리는 인자뿐이다. 아무도 쓰지 않을 초 값을 표식으로 쓴다.
        let marker = "31771"
        _ = try? SystemCommand.run(["/bin/sleep", marker], timeout: 0.3)

        let survivors = try SystemCommand.run(["/bin/ps", "-A", "-o", "command="], timeout: 10)
        #expect(!survivors.standardOutput.contains("sleep \(marker)"))
    }

    // MARK: - 파이프

    /// stdout 을 끝까지 읽은 **뒤** stderr 를 읽으면, 자식이 stderr 로 파이프 버퍼(64KB)를 넘겨 쓰는
    /// 순간 서로를 기다리며 멈춘다. 자식은 stderr 에 쓰지 못해 진행하지 못하고, 부모는 stdout 의
    /// EOF 를 기다린다. 두 파이프를 **동시에** 비워야만 풀린다.
    @Test("stdout·stderr 를 함께 쏟아내도 멈추지 않는다")
    func drainsBothPipesConcurrently() throws {
        let line = String(repeating: "x", count: 60)
        let program = """
        BEGIN { for (i = 0; i < 6000; i++) { print "\(line)"; print "\(line)" > "/dev/stderr" } }
        """
        let result = try SystemCommand.run(["/usr/bin/awk", program], timeout: 30)

        #expect(result.succeeded)
        // 양쪽 모두 파이프 버퍼(64KB)를 넉넉히 넘긴다.
        #expect(result.standardOutput.utf8.count > 300_000)
        #expect(result.standardError.utf8.count > 300_000)
    }

    @Test("종료 코드와 stderr 를 그대로 전한다")
    func reportsExitCodeAndStandardError() throws {
        let result = try SystemCommand.run(
            ["/usr/bin/awk", "BEGIN { print \"실패 사유\" > \"/dev/stderr\"; exit 3 }"], timeout: 10
        )
        #expect(!result.succeeded)
        #expect(result.exitCode == 3)
        #expect(result.standardError.contains("실패 사유"))
    }

    // MARK: - 환경·셸

    @Test("물려받은 환경변수를 넘기지 않고 PATH 만 준다")
    func passesOnlyPATH() throws {
        setenv("EXEM_WIFI_SWITCHER_TEST_MARKER", "leaked", 1)
        defer { unsetenv("EXEM_WIFI_SWITCHER_TEST_MARKER") }

        let result = try SystemCommand.run(["/usr/bin/env"], timeout: 10)
        let lines = result.standardOutput.split(separator: "\n").map(String.init)
        #expect(lines == ["PATH=/usr/sbin:/usr/bin:/sbin:/bin"])
        #expect(!result.standardOutput.contains("leaked"))
    }

    @Test("명시한 환경변수는 넘어가고 PATH 는 유지된다")
    func mergesExplicitEnvironment() throws {
        let result = try SystemCommand.run(["/usr/bin/env"], environment: ["EXEM_GIVEN": "yes"], timeout: 10)
        #expect(result.standardOutput.contains("EXEM_GIVEN=yes"))
        #expect(result.standardOutput.contains("PATH=/usr/sbin:/usr/bin:/sbin:/bin"))
    }

    /// 셸을 경유하면 아래 인자들이 **명령으로 실행된다.** argv 를 그대로 넘기므로 글자 그대로 간다.
    @Test("셸을 경유하지 않는다")
    func doesNotGoThroughShell() throws {
        let arguments = ["$(id)", "`id`", "a;b", "*", "$HOME"]
        let result = try SystemCommand.run(["/bin/echo"] + arguments, timeout: 10)
        #expect(result.standardOutput == arguments.joined(separator: " ") + "\n")
    }

    @Test("없는 실행 파일은 실행 실패로 알린다")
    func reportsLaunchFailure() {
        let error = #expect(throws: SystemCommand.RunError.self) {
            try SystemCommand.run(["/nonexistent/exem-wifi-switcher/tool"], timeout: 10)
        }
        guard case .launchFailed? = error else {
            Issue.record("실행 실패가 아니라 다른 오류가 났습니다: \(String(describing: error))")
            return
        }
    }

    // MARK: - 상한 값

    @Test("전환 명령의 상한이 읽기 명령보다 넉넉하다")
    func switchingGetsMoreRoomThanReading() {
        // 전환(sudo -n apply)은 안에서 networksetup 을 여러 번 부른다. 읽기 한 번과 같은 상한을 두면
        // 정상 동작이 상한에 걸린다.
        #expect(SystemCommand.scriptTimeout > SystemCommand.defaultTimeout)
        #expect(SystemCommand.defaultTimeout >= 5)
    }
}
