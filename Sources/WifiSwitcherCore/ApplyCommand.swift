import Foundation

/// root 권한 스크립트 호출을 조립한다.
///
/// **셸을 거치지 않는다.** 실행 파일 경로와 인자를 배열로 넘기므로
/// 인자에 어떤 문자가 들어 있어도 명령으로 해석될 여지가 없다.
/// 그럼에도 이름을 미리 검증하는 이유는, 잘못된 이름을 sudo 까지 보내지 않기 위해서다.
public enum ApplyCommand {

    public enum CommandError: Error, Equatable, CustomStringConvertible {
        case invalidProfileName(String)
        case notInstalled(String)
        case failed(exitCode: Int32, message: String)

        public var description: String {
            switch self {
            case .invalidProfileName(let name):
                return ValidationError.invalidProfileName(name).description
            case .notInstalled(let path):
                return "권한 스크립트가 설치돼 있지 않습니다: \(path) (scripts/install.sh 를 먼저 실행하세요)"
            case .failed(let exitCode, let message):
                return "네트워크 구성 적용에 실패했습니다 (종료 코드 \(exitCode)) \(message)"
            }
        }
    }

    /// 실행할 argv. 첫 원소가 실행 파일 경로다.
    public static func arguments(profileName: String) throws -> [String] {
        guard ProfileName.isValid(profileName) else {
            throw CommandError.invalidProfileName(profileName)
        }
        // -n: 암호를 물어야 하는 상황이면 조용히 실패한다.
        //     메뉴바 앱에는 암호를 입력할 화면이 없으므로 매달리는 대신 즉시 실패하는 편이 낫다.
        return [InstallPaths.sudoBinary, "-n", InstallPaths.applyScript, profileName]
    }
}
