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

        public var description: String {
            switch self {
            case .launchFailed(let path, let underlying):
                return "실행하지 못했습니다: \(path) (\(underlying))"
            }
        }
    }

    /// argv 배열을 그대로 실행한다. **셸을 경유하지 않는다.**
    public static func run(_ arguments: [String], environment: [String: String] = [:]) throws -> Result {
        precondition(!arguments.isEmpty, "실행할 명령이 비어 있습니다")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        // 물려받은 환경변수를 그대로 넘기지 않는다. 필요한 것만 명시적으로 준다.
        process.environment = environment.merging(["PATH": "/usr/sbin:/usr/bin:/sbin:/bin"]) { current, _ in current }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(arguments[0], underlying: error)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
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
        let result = try SystemCommand.run(try arguments(profileName: profileName))
        guard result.succeeded else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw CommandError.failed(exitCode: result.exitCode, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}
