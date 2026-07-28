import Foundation

/// 설정 창의 **사내 Wi-Fi 이름 칸**이 지금 무엇을 들고, 고칠 수 있어야 하는가.
///
/// 이 칸은 자동 전환의 방아쇠다 — 여기 적힌 이름의 Wi-Fi 에 붙었을 때만 고정 IP 가 걸린다.
/// 그래서 두 가지를 함께 정해야 하고, 둘은 같은 근거(지금 고정 IP 구성인가)를 본다.
///
///   - **값**: 비어 있는 칸은 지금 읽은 이름으로 채운다. 단 **고정 IP 로 돌고 있을 때만** —
///     DHCP 로 도는 자리에서 읽은 이름은 집·카페 이름이고, 그것을 사내 프로필에 넣으면
///     바로 그 자리에서 사내 고정 IP 가 걸린다
///   - **잠금**: 고정 IP 구성에서 이름이 채워져 있으면 잠근다. 앱이 읽어 넣은 값이라
///     사람이 손댈 이유가 없고, 실수로 고치면 나머지 값이 다 맞아도 자동 전환만 조용히
///     걸리지 않는다 — 가장 알아채기 어려운 고장이다
///
/// **판정에 설정 파일은 들어오지 않는다.** 저장한 적이 있든 없든, 사내에서 이름이 채워졌으면
/// 잠근다. (저장을 기준으로 삼으면 자동 입력만 된 첫 실행이 잠기지 않는다)
///
/// 잠그지 않는 두 자리는 되돌릴 길을 남기기 위한 것이다.
///
///   - **사외(DHCP)**: 사내 이름을 처음 넣는 자리이자, 잘못 넣은 이름을 고칠 유일한 자리다
///   - **사내인데 칸이 빔**: 위치 권한이 없어 이름을 못 읽은 경우다. 여기까지 잠그면
///     권한을 끝내 거부한 사람에게 남는 길이 없다
public struct SSIDFieldState: Equatable, Sendable {

    /// 칸에 있어야 할 이름.
    public let name: String
    /// 사람이 고칠 수 있는가.
    public let isEditable: Bool

    public init(name: String, isEditable: Bool) {
        self.name = name
        self.isEditable = isEditable
    }

    /// - Parameters:
    ///   - typed: 지금 칸에 적혀 있는 것. 사용자가 적어 둔 것도 여기로 들어오므로 덮지 않는다.
    ///   - reading: 지금 접속한 Wi-Fi 이름을 읽은 결과.
    ///   - interface: 지금 IPv4 구성. **읽지 못했으면(nil) 잠그지 않는다** — 구성을 모르는 채로
    ///     잠그면 읽기에 실패한 기기에서 칸이 영영 잠긴다.
    public static func resolve(typed: String, reading: SSIDReading, interface: InterfaceInfo?) -> SSIDFieldState {
        let isOffice = interface?.isManual == true
        let name = typed.isEmpty && isOffice ? (reading.name ?? "") : typed
        let isNamed = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return SSIDFieldState(name: name, isEditable: !(isOffice && isNamed))
    }
}
