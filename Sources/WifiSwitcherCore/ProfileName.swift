import Foundation

/// 프로필 이름 규칙.
///
/// 이 이름은 `sudo -n .../apply <이름>` 의 **유일한 인자**로 root 권한 스크립트에 전달된다.
/// 그래서 규칙이 세 곳에 동일하게 존재하며, 셋 다 독립적으로 검증한다(다층 방어).
///
/// 1. 여기 (앱이 명령을 만들기 전)
/// 2. `scripts/apply` 의 `validate_profile_name` (root 로 실행된 직후)
/// 3. `/etc/sudoers.d/exem-wifi-switcher` 의 인자 패턴 (sudo 가 실행 자체를 거부)
///
/// **규칙을 바꾸면 세 곳을 함께 바꿔야 한다.**
public enum ProfileName {

    /// 최대 길이. sudoers 는 "문자 클래스의 반복"을 표현할 수 없어
    /// 길이별 고정 패턴을 나열하는 방식으로 제한하므로, 이 값이 곧 sudoers 줄 수가 된다.
    public static let maxLength = 16

    /// 허용: 첫 글자는 영숫자, 이후는 영숫자·`_`·`-`.
    /// `.` `/` 공백 등은 전부 거부하므로 경로 탈출·셸 메타문자가 원천 차단된다.
    public static func isValid(_ name: String) -> Bool {
        guard (1...maxLength).contains(name.count) else { return false }
        guard name.utf8.count == name.count else { return false }  // 비 ASCII 거부

        for (index, character) in name.enumerated() {
            guard character.isASCII else { return false }
            let isAlphanumeric = character.isLetter || character.isNumber
            if index == 0 {
                guard isAlphanumeric else { return false }
            } else {
                guard isAlphanumeric || character == "_" || character == "-" else { return false }
            }
        }
        return true
    }
}
