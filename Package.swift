// swift-tools-version: 6.0
import PackageDescription

// Xcode 없이 Command Line Tools 만으로 빌드된다.
//   swift build      — 빌드
//   swift test       — 단위 테스트 (셸 스크립트 검증 포함)
let package = Package(
    name: "ExemWifiSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WifiSwitcherCore", targets: ["WifiSwitcherCore"]),
        .executable(name: "exem-wifi-switcher-cli", targets: ["ExemWifiSwitcherCLI"]),
        // 메뉴바 앱. 실행 파일 그대로는 위치 권한을 받을 수 없어
        // scripts/build-app.sh 가 '.app' 번들로 조립한다.
        .executable(name: "exem-wifi-switcher-app", targets: ["ExemWifiSwitcherApp"]),
    ],
    targets: [
        .target(name: "WifiSwitcherCore"),
        .executableTarget(name: "ExemWifiSwitcherCLI", dependencies: ["WifiSwitcherCore"]),
        .executableTarget(name: "ExemWifiSwitcherApp", dependencies: ["WifiSwitcherCore"]),
        .testTarget(name: "WifiSwitcherCoreTests", dependencies: ["WifiSwitcherCore"]),
    ]
)
