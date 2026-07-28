import AppKit

/// 설치·제거 확인 시트에 들어가는 **계획 전문** 상자.
///
/// 담기는 글은 앱이 짓지 않는다 — 실행할 바로 그 스크립트의 `--dry-run` 출력 그대로다
/// (`InstallerService.preview`). 권한을 요구하는 도구라 무엇을 하는지 감추지 않는 것이
/// 신뢰의 근거인데(RULES.md §6), **읽히지 않는 글은 감춘 것과 같다.**
/// 그래서 이 상자가 지켜야 할 것은 하나다 — 원문을 원문 그대로 보이게 할 것.
///
/// ## 줄바꿈을 하지 않는다
///
/// 원문은 터미널 폭을 전제로 **공백으로 열을 맞춘** 글이다.
///
/// ```
///   apply         root:wheel 0755 — networksetup -setmanual / -setdhcp 를 실행합니다.
///                 이 파일 하나만 암호 없이 root 로 실행됩니다.
/// ```
///
/// 이 글을 좁은 상자에 넣고 자동 줄바꿈을 켜면 두 가지가 한꺼번에 무너진다.
/// 맞춰 둔 열이 어긋나고(딸린 설명이 어느 항목의 것인지 알 수 없게 된다),
/// 줄이 `/` 나 `.` 에서 끊겨 경로·명령이 두 조각으로 읽힌다.
/// **접힌 글은 원문이 아니다.**
///
/// 그래서 접지 않는다. 넘치는 줄은 가로로 스크롤한다 — 터미널에서 보는 것과 같은 모양이다.
/// 대신 상자를 넉넉히 잡아(`width`), 계획 본문은 스크롤 없이 다 들어오게 했다.
/// 가로로 넘치는 것은 sudoers 규칙 전문처럼 **원래 한 줄이 긴** 것들뿐이다.
///
/// ## 스크롤이 있으면 있다고 보여준다
///
/// 계획은 한 화면에 담기지 않는다. macOS 기본 오버레이 스크롤 막대는 손대기 전까지 숨어 있어서,
/// 아래에 더 있다는 사실 자체가 보이지 않는다. 읽고 확인하라고 내놓은 글에서 그것은
/// 읽을 것이 남았다는 사실을 숨기는 셈이다. 그래서 막대를 **항상 띄운다**(`.legacy`).
@MainActor
enum InstallPlanView {

    /// 상자 크기. 계획 본문의 가장 긴 줄이 가로 스크롤 없이 들어오는 폭으로 잡았다
    /// (실측: 계획 본문 최장 줄 ≈ 590pt, sudoers 규칙 전문은 원래 한 줄이 길어 예외다).
    static let width: CGFloat = 720
    static let height: CGFloat = 420

    static func make(_ text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        // 스크롤 막대를 숨기지 않는다 — 남은 글이 있다는 사실이 보여야 한다.
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // 접지 않는다 — 글자 상자를 무한히 넓게 두고, 뷰가 그 폭을 따라 늘어나게 한다.
        let unbounded = CGFloat.greatestFiniteMagnitude
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: unbounded, height: unbounded)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.containerSize = NSSize(width: unbounded, height: unbounded)
        textView.textContainer?.widthTracksTextView = false

        scroll.documentView = textView
        return scroll
    }
}
