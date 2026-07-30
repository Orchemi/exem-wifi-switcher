import Foundation

/// [앱 삭제] 가 무엇을 하는지 말하고, 무슨 일이 일어났는지 말한다.
///
/// ## 왜 이름을 키우는 대신 하는 일을 키웠나
///
/// 이 버튼은 권한 머리말 옆의 작은 [제거…] 였다. 하는 일은 설치물 정리뿐이고 앱 번들은 남았다.
/// 그래서 누른 사람에게는 "앱을 지웠다" 는 느낌이 남지 않았다. 이름만 [앱 삭제] 로 키우면
/// **버튼이 하는 일보다 이름이 커진다.** 이 저장소가 반복해서 고쳐 온 결함이 그것이라
/// (말과 실제가 다른 안내), 이름에 맞게 **앱 번들까지 휴지통으로 옮기고 종료**하도록 바꿨다.
///
/// ## 경계
///
/// sudo 규칙·권한 스크립트·설정을 지우는 것은 전부 `scripts/uninstall.sh` 가 한다.
/// **여기서 그 절차를 다시 구현하지 않는다.** 앱이 맡는 것은 스크립트가 손댈 수 없는 것 하나,
/// 곧 자기 번들을 처분하는 일뿐이다. 실제 이동은 `NSWorkspace.recycle` 이 하고
/// (`rm` 을 쓰지 않는다. 되돌릴 수 없다), 이 타입은 **무엇을 보여줄지**만 답한다.
public enum AppRemoval {

    // MARK: - 버튼과 확인 시트

    /// 설정 창 아래쪽 왼편에 서는 버튼. 누르면 계획을 먼저 보여주므로 말줄임표를 붙인다.
    public static let footerButtonTitle = "앱 삭제…"

    /// 확인 시트에서 실제로 삭제를 시작하는 버튼.
    public static let confirmButtonTitle = "앱 삭제"

    public static let confirmationTitle = "앱을 삭제합니다"

    public static let confirmationBody =
        "관리자 인증을 한 번 받습니다. 아래 항목을 지운 다음 앱 번들을 휴지통으로 옮기고 앱을 종료합니다. "
        + "입력한 네트워크 값도 함께 지워집니다."

    /// 앱이 정정하는 스크립트의 문장.
    ///
    /// **`scripts/uninstall.sh` 에 실제로 있는 문장이어야 한다** (테스트가 대조한다).
    /// 스크립트 문구가 바뀌면 정정할 대상이 사라져, 사용자는 어느 줄 이야기인지 알 수 없는
    /// 안내를 읽게 된다.
    public static let correctedScriptSentence = "이 스크립트가 지우지 않습니다. 직접 지우세요"

    /// 계획 전문(스크립트 `--dry-run` 출력) 뒤에 앱이 덧붙이는 안내.
    ///
    /// 터미널로 부르는 사람에게 위 문장은 여전히 참이므로 **스크립트를 고치지 않는다.**
    /// 대신 앱에서 부르는 길에서만 거짓이 되는 그 한 줄을 여기서 집어 정정한다.
    public static func planAddendum(appName: String = InstallPaths.appName) -> String {
        """
        ===========================================================================
         앱이 덧붙이는 안내
        ===========================================================================

        위 목록의 "\(correctedScriptSentence)" 는
        터미널에서 스크립트를 직접 부를 때의 이야기입니다.

        이 창에서 삭제하면 위 항목을 지운 다음, 앱이 \(appName).app 을
        휴지통으로 옮기고 종료합니다. 휴지통을 비우기 전까지는 되돌릴 수 있습니다.
        """
    }

    /// 확인 시트에 넣을 글. 스크립트가 한 말은 그대로 두고 뒤에 앱의 안내를 붙인다.
    public static func plan(_ scriptPlan: String, appName: String = InstallPaths.appName) -> String {
        let trimmed = scriptPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return planAddendum(appName: appName) }
        return trimmed + "\n\n" + planAddendum(appName: appName)
    }

    // MARK: - 결과

    /// 삭제를 시도한 뒤 실제로 남은 상태.
    ///
    /// 두 단계(스크립트 제거 · 번들 휴지통 이동)가 각각 실패할 수 있어 갈래가 넷이다.
    /// **셋을 하나로 뭉뚱그리면 실패한 자리에서 "지웠습니다" 라고 말하게 된다.**
    public enum Outcome: Equatable, Sendable {
        /// 인증 창을 닫았다. 아무것도 실행되지 않았다
        case cancelled
        /// 제거 스크립트가 실패했다. 번들은 건드리지 않았다
        case scriptFailed(reason: String)
        /// 설치물은 지웠지만 번들을 휴지통으로 옮기지 못했다
        case appBundleRemains(path: String, reason: String)
        /// 설치물을 지우고 번들도 휴지통으로 옮겼다
        case removed
    }

    /// 결과를 옮겨 적는 창의 내용. 무엇을 보여주고 그다음 무엇을 할지까지 여기서 정한다.
    public struct Message: Equatable, Sendable {
        public let title: String
        public let body: String
        /// 경고로 띄울 것인가. 사용자가 손봐야 할 것이 남은 결과에만 붙인다
        public let isWarning: Bool
        /// 이 창을 닫으면 앱이 종료되는가
        public let quitsAfterConfirmation: Bool
        /// 남은 번들을 Finder 에서 보여주는 길을 함께 내놓을 것인가
        public let offersFinderReveal: Bool
        /// 터미널로 이어서 할 수 있는 명령을 함께 내놓을 것인가
        public let offersTerminalCommand: Bool
    }

    public static func message(for outcome: Outcome, appName: String = InstallPaths.appName) -> Message {
        switch outcome {
        case .cancelled:
            return Message(
                title: "인증을 취소해서 삭제하지 않았습니다",
                body: "시스템도 앱도 그대로입니다.",
                isWarning: false,
                quitsAfterConfirmation: false,
                offersFinderReveal: false,
                offersTerminalCommand: false
            )

        case .scriptFailed(let reason):
            // 스크립트는 중간에 멈출 수 있다. '아무것도 바뀌지 않았다' 고 단정하지 않는다.
            return Message(
                title: "앱을 삭제하지 못했습니다",
                body: "\(reason)\n\n앱 번들은 휴지통으로 옮기지 않았습니다. "
                    + "설치한 항목 중 일부가 남아 있을 수 있으니, "
                    + "[터미널 명령 복사] 로 제거 스크립트를 직접 실행해 확인하세요.",
                isWarning: true,
                quitsAfterConfirmation: false,
                offersFinderReveal: false,
                offersTerminalCommand: true
            )

        case .appBundleRemains(let path, let reason):
            // 절반은 됐고 절반은 안 됐다. 양쪽을 다 적어야 사실이 된다.
            return Message(
                title: "설치한 항목은 지웠고 앱만 남았습니다",
                body: "\(appName).app 을 휴지통으로 옮기지 못했습니다: \(reason)\n\n"
                    + "남은 위치: \(path)\n"
                    + "[Finder 에서 보기] 를 눌러 직접 휴지통으로 옮기세요. 앱은 종료하지 않습니다.",
                isWarning: true,
                quitsAfterConfirmation: false,
                offersFinderReveal: true,
                offersTerminalCommand: false
            )

        case .removed:
            return Message(
                title: "앱을 삭제했습니다",
                body: "설치한 항목을 지우고 \(appName).app 을 휴지통으로 옮겼습니다. "
                    + "휴지통을 비우기 전까지는 되돌릴 수 있습니다.\n\n"
                    + "[확인] 을 누르면 앱이 종료됩니다. 알림 설정은 시스템 설정 > 알림 에 남습니다 "
                    + "(macOS 가 명령으로 지우는 방법을 제공하지 않습니다).",
                isWarning: false,
                quitsAfterConfirmation: true,
                offersFinderReveal: false,
                offersTerminalCommand: false
            )
        }
    }
}
