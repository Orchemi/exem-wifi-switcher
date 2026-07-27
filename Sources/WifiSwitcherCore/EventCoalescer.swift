import Foundation

/// 몰려오는 이벤트를 한 번으로 묶기 위해 **얼마나 기다릴지** 계산한다.
///
/// Wi-Fi 를 한 번 갈아타면 링크·IP·DNS 가 차례로 바뀌면서 네트워크 변경 알림이 여러 번 온다.
/// 그때마다 전환을 걸면 자동 전환이 스스로를 밟는다. 그래서 **조용해질 때까지 기다렸다가 한 번만** 움직인다.
///
/// 다만 무한정 미룰 수는 없다. 변경이 계속 이어지는 동안에도 `maximumDelay` 안에는 한 번 처리한다 —
/// 그러지 않으면 "바쁘면 영원히 반응하지 않는" 감시가 된다.
public struct EventCoalescer: Equatable, Sendable {

    /// 마지막 이벤트 이후 이만큼 조용하면 처리한다.
    public let quietPeriod: TimeInterval
    /// 첫 이벤트로부터 아무리 늦어도 이 안에는 처리한다.
    public let maximumDelay: TimeInterval

    public init(quietPeriod: TimeInterval, maximumDelay: TimeInterval) {
        self.quietPeriod = quietPeriod
        self.maximumDelay = maximumDelay
    }

    /// 지금 이벤트가 왔을 때 처리까지 기다릴 시간.
    /// - Parameter burstStartedAt: 지금 이어지고 있는 이벤트 무리의 첫 이벤트 시각. 없으면 지금이 첫 이벤트다.
    public func delay(now: Date, burstStartedAt: Date?) -> TimeInterval {
        let burstStart = burstStartedAt ?? now
        let quietDeadline = now.addingTimeInterval(quietPeriod)
        let hardDeadline = burstStart.addingTimeInterval(maximumDelay)
        return max(0, min(quietDeadline, hardDeadline).timeIntervalSince(now))
    }
}
