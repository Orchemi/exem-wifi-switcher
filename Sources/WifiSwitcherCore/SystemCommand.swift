import Foundation

/// 외부 프로세스 실행을 한 곳에 모은다.
///
/// 이 파일이 이 패키지에서 **유일하게** 프로세스를 띄우는 곳이다.
/// 다른 파일은 전부 순수 함수라 테스트에서 시스템을 건드리지 않는다.
public enum SystemCommand {

    public struct Result: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String

        public var succeeded: Bool { exitCode == 0 }
    }

    public enum RunError: Error, CustomStringConvertible {
        case launchFailed(String, underlying: Error)
        case timedOut(String, seconds: TimeInterval)

        public var description: String {
            switch self {
            case .launchFailed(let path, let underlying):
                return "실행하지 못했습니다: \(path) (\(underlying))"
            case .timedOut(let path, let seconds):
                return "\(Int(seconds.rounded()))초 안에 응답하지 않아 중단했습니다: \(path)"
            }
        }
    }

    // MARK: - 상한
    //
    // 어떤 호출도 무한히 기다리지 않는다. 이 값들이 없던 시절, `networksetup` 이 응답하지 않으면
    // 갱신 래치(`StatusItemController.isRefreshing`)와 전환 래치(`action = .switching`)가 켜진 채
    // 굳어 **자동 전환이 조용히 영구 정지**했다. 화면에는 마지막 상태가 그대로 떠 있어 사용자는
    // 정상으로 읽고, 빠져나올 길은 앱 재실행뿐이었다.
    //
    // 상한은 "정상 동작이 절대 닿지 못할 만큼 크되, 사람이 고장으로 알아차릴 만큼 작게" 잡는다.

    /// 값 하나를 읽어 오는 명령의 상한.
    ///
    /// `networksetup -getinfo` · `-getdnsservers` · `-listallnetworkservices` · `scutil --dns` 는
    /// 보통 1초 안에 끝난다. 슬립 복귀 직후 `configd` 가 늦게 답하는 경우를 감안해 열 배 남짓 둔다.
    public static let defaultTimeout: TimeInterval = 15

    /// 안에서 외부 명령을 여러 번 부르는 스크립트의 상한.
    ///
    /// `sudo -n apply` 한 번은 `networksetup` 을 최대 다섯 번 부른다
    /// (서비스 목록 · 현재 DNS · DNS 지정 · IPv4 지정 · 실패 시 DNS 되돌리기).
    /// 읽기 한 번의 상한을 그대로 쓰면 정상 동작이 상한에 걸린다. 세 배로 둔다.
    /// `install.sh --dry-run` 도 여러 명령을 부르므로 같은 값을 쓴다.
    public static let scriptTimeout: TimeInterval = 45

    /// SIGTERM 을 보낸 뒤 SIGKILL 까지 주는 유예.
    /// 정리할 것이 있는 프로세스에 그럴 틈을 주되, 매달려 있게 두지는 않는다.
    static let terminationGrace: TimeInterval = 2

    /// argv 배열을 그대로 실행한다. **셸을 경유하지 않는다.**
    ///
    /// - Parameter timeout: 이 시간 안에 끝나지 않으면 SIGTERM, 그래도 남으면 SIGKILL 을 보내고
    ///   `RunError.timedOut` 을 던진다. **호출한 쪽은 반드시 돌아온다.**
    public static func run(
        _ arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = defaultTimeout
    ) throws -> Result {
        precondition(!arguments.isEmpty, "실행할 명령이 비어 있습니다")
        precondition(timeout > 0, "타임아웃은 0보다 커야 합니다")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        // 물려받은 환경변수를 그대로 넘기지 않는다. 필요한 것만 명시적으로 준다.
        process.environment = environment.merging(["PATH": "/usr/sbin:/usr/bin:/sbin:/bin"]) { current, _ in current }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // 두 파이프를 **동시에** 비운다.
        //
        // 한쪽을 끝까지 읽은 뒤 다른 쪽을 읽으면, 자식이 아직 읽지 않은 쪽에 파이프 버퍼(64KB)를
        // 넘겨 쓰는 순간 서로를 기다리며 멈춘다. 자식은 write 에서 막혀 끝나지 못하고, 부모는
        // 그 자식이 끝나야 오는 EOF 를 기다린다. 읽는 **순서를 바꾸는 것으로는 풀리지 않는다** —
        // 어느 쪽이 먼저 넘치는지는 자식이 정한다 (2026-08-03 실측: awk 로 양쪽에 360KB 씩 쓰면 교착).
        let outputDrain = PipeDrain(outputPipe.fileHandleForReading)
        let errorDrain = PipeDrain(errorPipe.fileHandleForReading)

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            outputDrain.stop()
            errorDrain.stop()
            throw RunError.launchFailed(arguments[0], underlying: error)
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            // 먼저 정중하게 부탁하고, 듣지 않으면 죽인다.
            // `sudo` 를 죽여도 이미 root 로 갈라져 나간 자식까지 죽일 수는 없다 —
            // 그래도 이쪽이 매달려 있는 것보다 낫다. `apply` 는 스스로 끝난다.
            process.terminate()
            if exited.wait(timeout: .now() + terminationGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + terminationGrace)
            }
        }

        // 이미 끝난 프로세스가 남긴 마지막 조각이 도착할 틈만 준다. 여기서 무한정 기다리지 않는다
        // (파이프를 물려받은 손자 프로세스가 살아 있으면 EOF 가 영영 오지 않을 수 있다).
        let outputData = outputDrain.finish(within: terminationGrace)
        let errorData = errorDrain.finish(within: terminationGrace)

        if timedOut {
            throw RunError.timedOut(arguments[0], seconds: timeout)
        }
        return Result(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}

/// 파이프 하나를 백그라운드에서 계속 비운다.
///
/// 자식이 쓰는 족족 받아 두므로 파이프 버퍼가 차지 않는다. 읽은 것은 잠금 뒤에 모으고,
/// 언제든 그때까지 받은 만큼을 꺼낼 수 있다 — 상한에 걸려 죽인 프로세스의 출력도 남는다.
private final class PipeDrain: @unchecked Sendable {

    private let handle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private var reachedEnd = false
    private let end = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty {
                self.markEnd()
            } else {
                self.lock.lock()
                self.buffer.append(chunk)
                self.lock.unlock()
            }
        }
    }

    /// EOF 를 최대 `grace` 초까지 기다린 뒤 지금까지 받은 것을 돌려준다.
    func finish(within grace: TimeInterval) -> Data {
        _ = end.wait(timeout: .now() + grace)
        stop()
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    private func markEnd() {
        lock.lock()
        let alreadyEnded = reachedEnd
        reachedEnd = true
        lock.unlock()
        if !alreadyEnded { end.signal() }
    }
}

/// 현재 네트워크 구성을 읽는다 (읽기 전용 — 어떤 것도 바꾸지 않는다).
public struct NetworkStateReader {

    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func readInterfaceInfo() throws -> InterfaceInfo {
        let result = try SystemCommand.run([InstallPaths.networksetupBinary, "-getinfo", service])
        guard result.succeeded else {
            throw NetworkSetupOutput.ParseError.commandFailed(
                result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
        return try NetworkSetupOutput.parseInterfaceInfo(result.standardOutput)
    }

    /// 현재 DNS 설정을 읽는다.
    ///
    /// **"없음" 과 "읽지 못함" 을 구분해 돌려준다.** 프로세스를 띄우는 것 자체가 실패하면
    /// 그것도 `.unreadable` 이다 — 호출한 쪽이 빈 목록으로 오해할 여지를 남기지 않는다.
    public func readDNSServers() -> DNSReading {
        do {
            let result = try SystemCommand.run([InstallPaths.networksetupBinary, "-getdnsservers", service])
            return NetworkSetupOutput.parseDNSReading(output: result.standardOutput, exitCode: result.exitCode)
        } catch {
            return .unreadable("\(error)")
        }
    }

    /// 지금 이름 해석에 실제로 쓰이는 IPv4 리졸버를 읽는다 (`scutil --dns`).
    ///
    /// `-getdnsservers` 와 **보는 것이 다르다.** 그쪽은 수동 지정 값만 보여주고, 이쪽은
    /// DHCP 가 알려준 값까지 보여준다. 수동 지정이 없을 때 설정 창이 제안할 값이 여기서 나온다.
    ///
    /// 읽지 못하면 빈 배열이다. 제안이 없을 뿐이라 실패로 다룰 것이 없다
    /// (사용자는 직접 입력할 수 있고, 화면이 그 사실을 말한다).
    ///
    /// **서비스 이름을 받지 않는다.** `scutil --dns` 는 시스템 전체의 리졸버 구성을 보여준다.
    public func readActiveResolvers() -> [String] {
        guard let result = try? SystemCommand.run([InstallPaths.scutilBinary, "--dns"]),
              result.succeeded
        else { return [] }
        return ScutilDNSOutput.activeResolvers(result.standardOutput)
    }

    /// 시스템에 존재하는 네트워크 서비스 목록.
    public static func availableServices() throws -> [String] {
        let result = try SystemCommand.run([InstallPaths.networksetupBinary, "-listallnetworkservices"])
        guard result.succeeded else { return [] }
        return NetworkSetupOutput.parseNetworkServices(result.standardOutput)
    }
}

extension ApplyCommand {

    /// `sudo -n apply <프로필>` 을 실행한다.
    /// 설치가 안 돼 있으면 sudo 를 호출하기 전에 실패한다.
    @discardableResult
    public static func run(profileName: String) throws -> SystemCommand.Result {
        guard FileManager.default.isExecutableFile(atPath: InstallPaths.applyScript) else {
            throw CommandError.notInstalled(InstallPaths.applyScript)
        }
        // 전환은 안에서 networksetup 을 여러 번 부른다. 읽기 상한을 그대로 쓰면 정상 동작이 걸린다.
        let result = try SystemCommand.run(try arguments(profileName: profileName),
                                           timeout: SystemCommand.scriptTimeout)
        guard result.succeeded else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw CommandError.failed(exitCode: result.exitCode, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}
