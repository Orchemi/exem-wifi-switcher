import Foundation
import Testing
@testable import WifiSwitcherCore

/// 메뉴에 올라가는 **문구의 규율**.
///
/// 메뉴는 문서가 아니지만, 아무 말도 하지 않으면 그것대로 혼란이 남는다. 그래서 보조 줄은
/// **넣되 짧게** — 문장이 아니라 한 구(句)로, 스무 자 안팎으로 줄인다.
///
/// 이 스위트는 개별 문구를 박제하지 않고 **모든 상태를 훑어 성질을 확인한다** —
/// 문구를 고칠 자유는 남기되, 산문이 다시 기어들어오는 것은 막는다.
@Suite("메뉴 문구 규율")
struct StatusModelMenuTextTests {

    /// 앱이 **스스로 짓는** 보조 줄의 목표 길이. 시스템 원문(`StatusModel.lineLimit`)보다 짧다 —
    /// 우리가 고를 수 있는 문구까지 상한에 붙여 쓰면 그게 곧 메뉴 폭이 된다.
    private static let authoredLimit = 22

    private static let office = NetworkProfile(
        name: "office", mode: .manual, ip: "192.0.2.10", subnet: "255.255.255.0",
        router: "192.0.2.1", ssids: ["OFFICE-WIFI"], label: "사내 고정 IP"
    )
    private static let auto = NetworkProfile(name: "auto", mode: .dhcp, label: "자동 (DHCP)")
    private static let config = AppConfig(profiles: [office, auto], defaultProfile: "auto")
    private static let officeInfo = InterfaceInfo(
        configMethod: .manual,
        ip: IPv4Address("192.0.2.10"),
        subnet: SubnetMask("255.255.255.0"),
        router: IPv4Address("192.0.2.1")
    )

    /// 모델이 **스스로 짓는** 문구만 모은다. 시스템이 준 원문(`interfaceError`·전환 실패 메시지·
    /// 설정 파일 오류)은 여기서 다루지 않는다 — 그쪽은 길이 상한으로만 다스린다.
    private static func authoredStrings(_ model: StatusModel) -> [String] {
        [model.headline] + model.autoSwitchNotes
    }

    /// 모든 갈래를 한 번씩 지나가는 입력 모음.
    private static var everyState: [StatusInput] {
        let holds: [AutoSwitchHold?] = [
            nil, .disabled, .busy, .locationPermissionRequired, .locationPermissionDenied,
            .wifiOff, .notAssociated, .ssidUnavailable("인터페이스를 찾지 못했습니다"),
            .configUnavailable, .helperNotInstalled, .noMatchingProfile(ssid: "OTHER-WIFI"),
            .alreadyApplied(profile: "office"), .manualOverride(profile: "auto"),
            .settling(profile: "office"), .ineffective(profile: "office"),
            .backoff(profile: "office", retryAt: Date(timeIntervalSince1970: 1_800_000_000)),
            .givenUp(profile: "office", failures: 5),
        ]
        let configs: [ConfigStatus] = [
            .ready(config), .missing(path: "/tmp/none.json"), .pristineExample(path: "/tmp/x.json"),
        ]
        let readings: [SSIDReading] = [
            .connected("OFFICE-WIFI"), .wifiOff, .notAssociated,
            .permissionDenied, .permissionNotDetermined, .unavailable("인터페이스 없음"),
        ]

        var inputs: [StatusInput] = []
        for hold in holds {
            for reading in readings {
                inputs.append(StatusInput(
                    config: .ready(config), interface: officeInfo, helperInstalled: true,
                    autoSwitchEnabled: true, ssid: reading, autoSwitchHold: hold
                ))
            }
        }
        for config in configs {
            for helper in [true, false] {
                inputs.append(StatusInput(
                    config: config, interface: officeInfo, helperInstalled: helper,
                    autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
                    autoSwitchHold: .alreadyApplied(profile: "office")
                ))
            }
        }
        inputs.append(StatusInput(
            config: .ready(config), interface: officeInfo, helperInstalled: true,
            action: .switching(profile: "office"), autoSwitchEnabled: true,
            ssid: .connected("OFFICE-WIFI")
        ))
        return inputs
    }

    // MARK: - 산문 금지

    @Test("모델이 짓는 문구는 문장이 아니라 명사구다")
    func noProse() {
        // 마침표를 찍고 있으면 그것은 메뉴 항목이 아니라 설명문이다.
        // 종결어미(…습니다 · …하세요)도 같은 신호다.
        let sentenceEndings = ["습니다", "하세요", "됩니다", "합니다", "입니다"]
        for input in Self.everyState {
            let model = StatusModel.resolve(input)
            for text in Self.authoredStrings(model) {
                #expect(!text.hasSuffix("."), "마침표로 끝난다: \(text)")
                for ending in sentenceEndings {
                    #expect(!text.contains(ending), "문장이다: \(text)")
                }
            }
        }
    }

    @Test("한 항목이 메뉴 폭을 혼자 정하지 않는다")
    func nothingIsTooWide() {
        for input in Self.everyState {
            let model = StatusModel.resolve(input)
            for text in Self.authoredStrings(model) {
                #expect(text.count <= Self.authoredLimit, "너무 길다(\(text.count)자): \(text)")
            }
            if let detail = model.detail {
                #expect(detail.count <= StatusModel.lineLimit, "보조 줄이 너무 길다: \(detail)")
            }
        }
    }

    // MARK: - 보조 줄의 모양

    @Test("보조 줄은 접두 하나로 주 항목과 갈린다")
    func secondaryLinesArePrefixed() {
        #expect(StatusModel.secondaryLine("Wi-Fi 없음") == "- Wi-Fi 없음")

        // 접두는 그리는 자리에서 **한 번만** 붙인다. 모델이 미리 붙여 두면 두 번 붙는다.
        for input in Self.everyState {
            let model = StatusModel.resolve(input)
            for text in model.autoSwitchNotes + [model.detail].compactMap({ $0 }) {
                #expect(!text.hasPrefix(StatusModel.secondaryPrefix), "접두가 이미 붙어 있다: \(text)")
                #expect(!text.isEmpty)
            }
        }
    }

    @Test("보조 줄은 많아야 둘이다 — 셋째 줄부터는 메뉴가 아니라 문서다")
    func atMostTwoNotes() {
        for input in Self.everyState {
            let notes = StatusModel.resolve(input).autoSwitchNotes
            #expect(notes.count <= 2, "보조 줄이 \(notes.count)개다: \(notes)")
        }
    }

    @Test("시스템이 준 긴 원문은 잘라서 싣는다 — 전문은 알림·설정 창·진단이 들고 있다")
    func clipsForeignText() {
        let long = String(repeating: "긴", count: 200)
        let unusable = StatusModel.resolve(StatusInput(config: .unusable(path: "/tmp/x.json", reason: long)))
        #expect(unusable.detail?.count == StatusModel.lineLimit)
        #expect(unusable.detail?.hasSuffix("…") == true)

        let unreadable = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: nil, interfaceError: long
        ))
        #expect(unreadable.detail?.count == StatusModel.lineLimit)

        let failed = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo,
            action: .failed(profile: "office", message: long)
        ))
        #expect(failed.detail?.count == StatusModel.lineLimit)
    }

    @Test("짧은 원문은 손대지 않는다")
    func keepsShortTextIntact() {
        let model = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo,
            action: .failed(profile: "office", message: "sudo: a password is required")
        ))
        #expect(model.detail == "sudo: a password is required")
    }

    // MARK: - 조용한 정상 상태

    @Test("문제가 없으면 경고성 항목이 하나도 나오지 않는다")
    func quietWhenHealthy() {
        let model = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo, helperInstalled: true,
            autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .alreadyApplied(profile: "office"), notifications: .allowed
        ))
        #expect(!model.needsLocationPermission)
        #expect(!model.needsNotificationPermission)
        #expect(!model.canRetryAutoSwitch)
        #expect(!model.needsSetup)
        // 조용하다고 말이 없는 것은 아니다 — 무엇을 보고 있는지 한 줄은 읽혀야 한다.
        #expect(model.autoSwitchNotes == ["Wi-Fi OFFICE-WIFI"])
        #expect(model.detail == "192.0.2.10 → 192.0.2.1")
    }

    // MARK: - 같은 말을 두 번 하지 않는다

    @Test("머리말이 이미 말한 것을 자동 전환 아래에 되풀이하지 않는다")
    func doesNotRepeatHeadline() {
        let unset = StatusModel.resolve(StatusInput(
            config: .missing(path: "/tmp/none.json"), helperInstalled: false,
            autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .configUnavailable
        ))
        #expect(unset.headline == "초기 설정하기")
        // 무엇이 비었는지는 머리말에 딸린 보조 줄이 말한다.
        #expect(unset.detail == "사내 IP 미등록")
        #expect(unset.autoSwitchNotes.isEmpty)

        let noHelper = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo, helperInstalled: false,
            autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .helperNotInstalled
        ))
        #expect(noHelper.detail == "설정 창에서 설치")
        #expect(noHelper.autoSwitchNotes.isEmpty)
    }

    @Test("값이 없는 것과 예시가 남은 것을 구분한다")
    func distinguishesUnsetCauses() {
        let pristine = StatusModel.resolve(StatusInput(config: .pristineExample(path: "/tmp/x.json")))
        #expect(pristine.headline == "초기 설정하기")
        #expect(pristine.detail == "예시 설정 그대로")
    }

    /// 메뉴 첫 줄은 눌러서 설정 창을 여는 자리다(`MenuStyle.headline`). 설정이 아직 없는 상태에서
    /// 그 줄에 상태만 적어 두면, 눌러야 하는 자리라는 사실이 어디에도 남지 않는다.
    ///
    /// 그래서 **온보딩이 필요한 상태의 머리말은 할 일**이어야 한다. 문구를 박제하지 않고
    /// 성질만 확인한다 — '…하기' 로 끝나는 행동 문구인가.
    @Test("설정이 필요한 상태의 머리말은 상태가 아니라 할 일이다")
    func setupHeadlineIsAnAction() {
        let unsetStates: [ConfigStatus] = [
            .missing(path: "/tmp/none.json"),
            .pristineExample(path: "/tmp/x.json"),
        ]
        for config in unsetStates {
            let model = StatusModel.resolve(StatusInput(config: config))
            #expect(model.needsSetup)
            #expect(model.headline.hasSuffix("하기"), "머리말이 할 일로 읽히지 않는다: \(model.headline)")
        }

        // 반대쪽 — 손댈 것이 없는 정상 상태는 상태를 말한다. 행동 문구로 바뀌면 안 된다.
        let ready = StatusModel.resolve(StatusInput(config: .ready(Self.config), interface: Self.officeInfo))
        #expect(!ready.needsSetup)
        #expect(!ready.headline.hasSuffix("하기"))
    }

    @Test("막힌 권한은 상태 한 줄과 조치 항목을 함께 낸다")
    func pairsStateWithAction() {
        // 조치만 있으면 무슨 일이 일어나고 있는지 읽히지 않고,
        // 상태만 있으면 어디로 가야 하는지 알 수 없다. 둘을 짧게 함께 낸다.
        let denied = StatusModel.resolve(StatusInput(
            config: .ready(Self.config), interface: Self.officeInfo,
            autoSwitchEnabled: true, ssid: .connected("OFFICE-WIFI"),
            autoSwitchHold: .alreadyApplied(profile: "office"), notifications: .denied
        ))
        #expect(denied.needsNotificationPermission)
        #expect(denied.autoSwitchNotes == ["Wi-Fi OFFICE-WIFI", "알림 꺼짐"])

        for (reading, hold) in [
            (SSIDReading.permissionDenied, AutoSwitchHold.locationPermissionDenied),
            (.permissionNotDetermined, .locationPermissionRequired),
            (.permissionDenied, .busy),
        ] {
            let model = StatusModel.resolve(StatusInput(
                config: .ready(Self.config), interface: Self.officeInfo,
                autoSwitchEnabled: true, ssid: reading, autoSwitchHold: hold
            ))
            #expect(model.needsLocationPermission)
            #expect(model.autoSwitchNotes.first?.contains("위치 권한") == true)
        }
    }

    // MARK: - 진단은 메뉴보다 많이 말해도 된다

    @Test("판정 이유는 메뉴에서 감춰도 진단에는 남는다")
    func diagnosticsKeepsTheReason() {
        // 메뉴는 머리말·액션이 대신 말하므로 note 를 비우지만, `--diagnose` 에는 이유가 있어야 한다.
        let profiles = Self.config.profiles
        for hold in [
            AutoSwitchHold.configUnavailable, .helperNotInstalled,
            .locationPermissionDenied, .locationPermissionRequired,
        ] {
            let reason = StatusModel.autoSwitchReason(hold, ssid: .connected("OFFICE-WIFI"), profiles: profiles)
            #expect(reason?.isEmpty == false, "\(hold) 의 이유가 비어 있다")
        }
    }
}
