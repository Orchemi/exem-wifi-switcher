import Foundation
import SystemConfiguration
import WifiSwitcherCore

/// 네트워크 변경을 감시한다.
///
/// 폴링이 아니라 `SCDynamicStore` 를 쓴다. Wi-Fi 를 갈아타면 IP 구성이 바뀌기까지 몇 초가 걸리는데,
/// 30초마다 들여다보는 방식으로는 그 사이가 통째로 비어 버린다.
///
/// **이벤트는 몰려서 온다.** Wi-Fi 를 한 번 갈아타는 동안 링크 상태·IP·DNS 가 차례로 바뀌면서
/// 콜백이 여러 번 불린다. 그때마다 전환을 걸면 서로를 물어뜯으므로, 여기서 **디바운스**로 한 번으로 묶는다.
/// (전환이 다시 전환을 부르는 것을 막는 판정은 `AutoSwitchPolicy` 에 따로 있다 — 두 겹이다)
final class NetworkChangeMonitor: @unchecked Sendable {

    /// 얼마나 묶어서 기다릴지는 코어의 순수 계산에 맡긴다 (단위 테스트가 지킨다).
    private let coalescer: EventCoalescer

    private let handler: @Sendable () -> Void
    /// 저장소 접근과 디바운스 상태를 이 큐 하나로 직렬화한다.
    private let queue = DispatchQueue(label: "com.horbis.exem-wifi-switcher.network-monitor")

    private var store: SCDynamicStore?
    private var pending: DispatchWorkItem?
    private var burstStartedAt: Date?

    init(
        quietPeriod: TimeInterval = 1.2,
        maximumDelay: TimeInterval = 6,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.coalescer = EventCoalescer(quietPeriod: quietPeriod, maximumDelay: maximumDelay)
        self.handler = onChange
    }

    /// 마지막 정리. **`stop()` 을 부르지 않고 해제된 경우의 그물이지, 정상 경로가 아니다.**
    ///
    /// 여기서 `queue.sync` 를 쓰면 안 된다. C 콜백은 이 객체를 `passUnretained` 로 붙잡지만,
    /// 그것은 **저장할 때 retain 하지 않는다**는 뜻일 뿐이다 — 콜백 안의 `takeUnretainedValue()` 는
    /// 호출 구간 동안 임시 강참조를 만든다. 콜백이 큐에서 도는 사이 마지막 소유자가 참조를 놓으면
    /// 그 임시 참조가 마지막 참조가 되어 **dealloc 이 이 큐 위에서 일어난다.**
    /// 그때 `deinit` 의 `queue.sync` 는 자기 큐를 기다리는 꼴이 되고 libdispatch 가 즉시 트랩한다.
    ///
    /// 그래서 여기서는 기다리지 않고 끊기만 한다. 감시를 확실히 멈추려면
    /// **소유자가 참조를 놓기 전에 `stop()` 을 부른다** (`Diagnostics` 가 그렇게 한다).
    deinit {
        pending?.cancel()
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
    }

    // MARK: - 수명

    /// 감시를 시작한다.
    /// - Returns: 실제로 붙었는지. **실패를 삼키지 않는다** — 감시가 없으면 자동 전환이
    ///   주기 확인에만 기대게 되므로, 호출한 쪽이 그 사실을 알고 대비해야 한다.
    @discardableResult
    func start() -> Bool {
        queue.sync { [self] in
            guard store == nil else { return true }

            var context = SCDynamicStoreContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            guard let store = SCDynamicStoreCreate(
                nil,
                "com.horbis.exem-wifi-switcher" as CFString,
                NetworkChangeMonitor.callback,
                &context
            ) else { return false }

            guard SCDynamicStoreSetNotificationKeys(store, Self.watchedKeys(), Self.watchedPatterns()),
                  SCDynamicStoreSetDispatchQueue(store, queue)
            else { return false }

            self.store = store
            return true
        }
    }

    /// 감시를 끊는다. **비동기로 미루지 않는다** — 미루면 그 블록이 이 객체를 붙잡고,
    /// 결국 해제가 이 큐 위에서 일어나 `deinit` 의 `queue.sync` 가 자기 큐를 기다리는 교착이 된다
    /// (libdispatch 는 이것을 즉시 트랩으로 잡는다).
    func stop() {
        queue.sync { [self] in
            pending?.cancel()
            pending = nil
            if let store {
                SCDynamicStoreSetDispatchQueue(store, nil)
            }
            store = nil
        }
    }

    // MARK: - 감시 대상
    //
    // 전역 IPv4 구성 + 인터페이스별 IPv4·링크·AirPort. AirPort 항목이 SSID 변경을 알려준다
    // (같은 Wi-Fi 하드웨어에서 다른 네트워크로 갈아타면 IP 가 그대로일 수도 있다).

    private static func watchedKeys() -> CFArray {
        [
            SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4),
            SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetDNS),
        ] as CFArray
    }

    private static func watchedPatterns() -> CFArray {
        [
            SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4),
            SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetLink),
            SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetAirPort),
        ] as CFArray
    }

    /// C 콜백. 아무것도 갈무리하지 않아야 함수 포인터로 넘어간다.
    private static let callback: SCDynamicStoreCallBack = { _, _, info in
        guard let info else { return }
        Unmanaged<NetworkChangeMonitor>.fromOpaque(info).takeUnretainedValue().networkChanged()
    }

    // MARK: - 디바운스

    /// 콜백은 `queue` 위에서 불린다 (`SCDynamicStoreSetDispatchQueue`).
    private func networkChanged() {
        let now = Date()
        let delay = coalescer.delay(now: now, burstStartedAt: burstStartedAt)
        burstStartedAt = burstStartedAt ?? now

        pending?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            burstStartedAt = nil
            pending = nil
            handler()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
