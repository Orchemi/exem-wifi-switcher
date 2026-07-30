import Foundation
import Testing
@testable import WifiSwitcherCore

/// [앱 삭제] 가 **한 일과 같은 말을 하는가**.
///
/// 이 자리는 두 번 어긋난 적이 있다. 버튼 이름은 '제거' 인데 하는 일은 설치물 정리뿐이었고,
/// 끝난 뒤 안내는 앱 번들을 직접 지우라고 말했다. 이제 앱이 번들까지 휴지통으로 옮기므로
/// **세 갈래 결과가 각자 사실만 말하는지**를 여기서 못박는다. 실패했는데 "지웠습니다" 라고
/// 말하는 것이 이 도구에서 가장 나쁜 결함이다.
@Suite("앱 삭제")
struct AppRemovalTests {

    private let appName = InstallPaths.appName

    /// 스크립트 dry-run 출력에서 정정 대상이 되는 줄. 실제 출력과 같은 문장이다
    /// (`scripts/uninstall.sh`). 스크립트를 고치지 않고 앱이 덧붙여 바로잡는다.
    private var scriptPlan: String {
        """
        지울 대상 (현재 있는 것만 지웁니다)

          [있음] /etc/sudoers.d/exem-wifi-switcher (sudo 규칙)

        앱 번들(\(InstallPaths.appName).app)은 사용자가 둔 자리에 있어 이 스크립트가 지우지 않습니다. 직접 지우세요.

        [dry-run] 실제로는 아무것도 지우지 않습니다.
        """
    }

    // MARK: - 확인 시트

    @Test("확인 시트는 앱 번들도 휴지통으로 간다고 말한다")
    func planSaysBundleGoesToTrash() {
        let plan = AppRemoval.plan(scriptPlan)
        #expect(plan.contains("휴지통"))
        #expect(plan.contains("\(appName).app"))
    }

    @Test("스크립트 출력은 한 글자도 고치지 않고 앞에 그대로 둔다")
    func planKeepsScriptOutputVerbatim() {
        let plan = AppRemoval.plan(scriptPlan)
        // 계획 전문은 실행할 그 스크립트의 말이다. 앱이 고쳐 쓰면 보여준 것과 실행하는 것이 달라진다.
        #expect(plan.hasPrefix(scriptPlan))
        #expect(plan.hasSuffix(AppRemoval.planAddendum()))
    }

    @Test("'직접 지우세요' 를 정정한다는 것이 드러난다")
    func addendumCorrectsTheScriptLine() {
        let addendum = AppRemoval.planAddendum()
        // 앞의 목록에 남아 있는 문장을 그대로 집어 정정한다. 어느 줄 이야기인지 알 수 없으면
        // 사용자는 서로 어긋나는 두 안내를 나란히 읽게 된다.
        #expect(addendum.contains(AppRemoval.correctedScriptSentence))
        // 터미널로 부르는 사람에게는 그 말이 여전히 참이다. 스크립트가 틀렸다고 말하지 않는다.
        #expect(addendum.contains("터미널"))
        #expect(addendum.contains("휴지통"))
        #expect(!addendum.contains("잘못"))
    }

    @Test("정정하는 문장이 제거 스크립트에 실제로 있다")
    func correctedSentenceExistsInScript() throws {
        // 스크립트 문구가 바뀌면 정정할 대상이 사라진다. 그때 앱의 안내는 앞에 없는 줄을
        // 인용하게 되고, 읽는 사람은 두 안내 중 무엇이 지금 이야기인지 알 수 없게 된다.
        let script = try String(
            contentsOf: RepositoryLayout.root.appendingPathComponent("scripts/uninstall.sh"),
            encoding: .utf8
        )
        #expect(script.contains(AppRemoval.correctedScriptSentence))
    }

    // MARK: - 세 갈래 결과

    @Test("둘 다 성공하면 지웠다고 말하고 앱을 종료한다")
    func removedTellsTheTruth() {
        let message = AppRemoval.message(for: .removed)
        #expect(message.title == "앱을 삭제했습니다")
        #expect(message.body.contains("휴지통으로 옮겼습니다"))
        #expect(message.quitsAfterConfirmation)
        #expect(!message.isWarning)
        #expect(!message.offersFinderReveal)
        #expect(!message.offersTerminalCommand)
    }

    @Test("제거가 실패하면 지웠다고 말하지 않는다")
    func scriptFailureNeverClaimsSuccess() {
        let message = AppRemoval.message(for: .scriptFailed(reason: "권한이 없습니다"))
        #expect(message.title == "앱을 삭제하지 못했습니다")
        // 실패한 자리에서 '지웠습니다' 라고 말한 결함이 실제로 있었다. 그 말은 여기 있을 수 없다.
        for lie in ["삭제했습니다", "지웠습니다", "휴지통으로 옮겼습니다"] {
            #expect(!message.title.contains(lie))
            #expect(!message.body.contains(lie))
        }
        #expect(message.body.contains("권한이 없습니다"))
        // 번들은 건드리지 않았다는 사실을 그대로 적는다.
        #expect(message.body.contains("휴지통으로 옮기지 않았습니다"))
        #expect(message.isWarning)
        #expect(!message.quitsAfterConfirmation)
        #expect(message.offersTerminalCommand)
        #expect(!message.offersFinderReveal)
    }

    @Test("휴지통 이동이 실패하면 앱이 남았다는 사실과 남은 자리를 말한다")
    func trashFailureNamesWhatRemains() {
        let path = "/Applications/\(InstallPaths.appName).app"
        let message = AppRemoval.message(for: .appBundleRemains(path: path, reason: "읽기 전용 볼륨입니다"))
        #expect(message.body.contains(path))
        #expect(message.body.contains("읽기 전용 볼륨입니다"))
        #expect(message.body.contains("휴지통으로 옮기지 못했습니다"))
        // 설치물은 실제로 지웠다. 그것까지 안 한 것처럼 말하면 그것도 거짓이다.
        #expect(message.title.contains("설치한 항목은 지웠"))
        #expect(!message.body.contains("휴지통으로 옮겼습니다"))
        #expect(!message.title.contains("삭제했습니다"))
        #expect(message.isWarning)
        #expect(!message.quitsAfterConfirmation)
        #expect(message.offersFinderReveal)
        #expect(!message.offersTerminalCommand)
    }

    @Test("인증을 취소한 것은 실패가 아니다")
    func cancellationIsNotFailure() {
        let message = AppRemoval.message(for: .cancelled)
        #expect(!message.isWarning)
        #expect(!message.quitsAfterConfirmation)
        for lie in ["삭제했습니다", "지웠습니다", "휴지통"] {
            #expect(!message.body.contains(lie))
        }
    }

    @Test("네 결과가 같은 제목을 쓰지 않는다")
    func everyOutcomeReadsDifferently() {
        let titles = [
            AppRemoval.Outcome.removed,
            .scriptFailed(reason: "x"),
            .appBundleRemains(path: "/tmp/a.app", reason: "x"),
            .cancelled,
        ].map { AppRemoval.message(for: $0).title }
        #expect(Set(titles).count == titles.count)
    }

    @Test("종료로 이어지는 결과는 성공 하나뿐이다")
    func onlySuccessQuits() {
        let outcomes: [AppRemoval.Outcome] = [
            .scriptFailed(reason: "x"), .appBundleRemains(path: "/tmp/a.app", reason: "x"), .cancelled,
        ]
        for outcome in outcomes {
            #expect(!AppRemoval.message(for: outcome).quitsAfterConfirmation)
        }
        #expect(AppRemoval.message(for: .removed).quitsAfterConfirmation)
    }

    // MARK: - 버튼 이름

    @Test("버튼 이름이 하는 일보다 커지지 않는다")
    func buttonTitlesMatchTheWork() {
        // 누르면 곧바로 지우는 것이 아니라 계획을 먼저 보여준다. 말줄임표가 그 사실을 말한다.
        #expect(AppRemoval.footerButtonTitle.hasSuffix("…"))
        #expect(AppRemoval.footerButtonTitle.hasPrefix(AppRemoval.confirmButtonTitle))
        #expect(!AppRemoval.confirmButtonTitle.hasSuffix("…"))
        // 확인 시트는 앱까지 지운다는 것을 제목에서 이미 말한다.
        #expect(AppRemoval.confirmationTitle.contains("앱"))
        #expect(AppRemoval.confirmationBody.contains("휴지통"))
    }
}
