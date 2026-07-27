import AppKit

// 메뉴바 전용 앱이다. Info.plist 의 LSUIElement 와 함께, Dock 에도 메뉴 막대에도 뜨지 않는다.
//
// 이 파일은 앱을 띄우는 일만 한다. 상태 판단은 WifiSwitcherCore 에, 화면은 StatusItemController 에 있다.

// 진단 모드: 메뉴바를 띄우지 않고 지금 상태만 찍고 끝낸다.
//   "EXEM Wifi Switcher.app/Contents/MacOS/EXEM Wifi Switcher" --diagnose
// 메뉴바에 아이콘이 보이지 않을 때 상태를 확인하는 통로다.
if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.run()
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
