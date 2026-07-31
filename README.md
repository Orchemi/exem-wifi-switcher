# EXEM Wifi Switcher

사내 Wi-Fi에 접속하면 고정 IP(수동 구성)로, 그 밖의 네트워크에서는 DHCP로 **자동 전환**하는 macOS 메뉴바 앱입니다.  
터미널 없이 앱으로 쉽게 설치합니다.

<p align="center"><img src="docs/screenshots/menubar-menu.png" width="196" alt="메뉴바 아이콘을 눌러 펼친 메뉴. '사내 고정 IP' 프로필에 체크 표시가 붙어 있고, '자동 전환' 이 켜져 있어 프로필 항목은 흐리게 보이는 상태. 그 아래에 설정과 종료." /><br><sub>평소에는 이 메뉴만 보입니다. 지금 설정값을 체크 표시로 알 수 있습니다.</sub></p>

## EXEM 사내 전용입니다

- **범용 Wi-Fi 전환 도구가 아닙니다.** 다루는 네트워크는 **사내 Wi-Fi** `EXEM` 하나뿐이고, 넣어야 하는 값은 **사내에서만 얻을 수 있습니다**
- **공개 저장소인 이유.** 이 도구는 `sudoers` 에 **암호 없이 root 로 실행되는 규칙**을 설치합니다. 위험한 권한을 요구하는만큼 투명하게 공개하고자 [요구하는 권한](https://github.com/Orchemi/exem-wifi-switcher/wiki/permissions)과 [무엇이 어디에 설치되는지](https://github.com/Orchemi/exem-wifi-switcher/wiki/what-gets-installed), [설치 버튼이 실제로 실행하는 스크립트](./scripts/install.sh)를 공개해 두었습니다
- **읽은 값을 저장하지 않습니다.** 확인한 Wi-Fi 이름과 위치는 어디에도 저장하지 않고 외부로도 보내지 않습니다

## 설치

<p align="center"><a href="https://github.com/Orchemi/exem-wifi-switcher/releases/latest/download/EXEM-Wifi-Switcher.zip"><img src="docs/assets/download-button.svg" width="214" height="60" alt="최신 버전 내려받기. 누르면 앱 zip 파일을 바로 내려받습니다." /></a><br><sub>macOS 13 이상 · 바뀐 내용과 SHA-256 은 <a href="https://github.com/Orchemi/exem-wifi-switcher/releases/latest">릴리즈 노트</a>에 있습니다.</sub></p>

> [!WARNING]
> **앱을 처음 열면 macOS 가 한 번 막습니다.** 이 앱이 Apple 의 공증(notarization)을 받지 않았기 때문이고, 앱에 문제가 있어서가 아닙니다.
>
> **시스템 설정 > 개인정보 보호 및 보안 > 보안** 에서 **[그래도 열기]** 를 누르고 앱을 다시 열면 됩니다. 한 번만 하면 됩니다.
>
> 자세한 내용은 [처음 열 때 macOS 가 막습니다](https://github.com/Orchemi/exem-wifi-switcher/wiki/first-open-blocked) 에 있습니다.

- **관리자 계정이 필요합니다.** `전환 권한 설치`와 `설정 저장`이 각각 관리자 인증을 한 번 받습니다.
- **앱을 처음 열면 위치 권한 창이 먼저 뜹니다.**
- Intel Mac에서 Homebrew가 `/usr/local` 을 소유하고 있으면 설치되지 않습니다. 이유는 [한계](https://github.com/Orchemi/exem-wifi-switcher/wiki/limitations)를 참고하세요.

1. 압축을 풀고 `EXEM Wifi Switcher.app` 을 **응용 프로그램** 폴더로 옮깁니다
2. 앱을 엽니다. 처음에는 macOS 가 막으므로 **위 경고의 여는 방법**을 한 번 거칩니다
3. 설정 창의 **권한** 항목에서 **[설치]** 를 누릅니다. 무엇을 어디에 설치할지 먼저 보여주고, 확인하면 관리자 암호를 한 번 묻습니다
4. 사내 **Wi-Fi 이름·IP·서브넷 마스크·라우터·DNS 서버** 를 입력하고 저장합니다. 저장할 때 관리자 암호를 **한 번 더** 묻습니다. 이것이 마지막입니다 ([설정하기](https://github.com/Orchemi/exem-wifi-switcher/wiki/settings))

## 제거

설정 창 아래 왼쪽의 **[앱 삭제…]** 를 누릅니다. 지울 목록을 먼저 보여주고 관리자 인증을 한 번 받습니다. 설치한 항목을 지운 다음 **앱 자체도 휴지통으로 옮기고 종료합니다.** 휴지통을 비우기 전까지는 되돌릴 수 있습니다. 무엇을 되돌리고 **무엇이 남는지**는 [설치되는 항목 전부](https://github.com/Orchemi/exem-wifi-switcher/wiki/what-gets-installed) 에 있습니다.

앱이 열리지 않아 **[앱 삭제…]** 를 누를 수 없다면 [터미널로 제거하는 방법](https://github.com/Orchemi/exem-wifi-switcher/wiki/what-gets-installed#앱이-열리지-않아-앱-삭제-를-누를-수-없다면)이 있습니다.

## 더 알아보기


| 하시려는 것                                     | 읽을 곳                                                                                      |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 값을 넣고 저장하고 싶습니다                     | [설정하기](https://github.com/Orchemi/exem-wifi-switcher/wiki/settings)                      |
| 언제 무엇으로 바뀌는지 알고 싶습니다            | [자동 전환](https://github.com/Orchemi/exem-wifi-switcher/wiki/auto-switching)               |
| 이 앱이 어떤 권한을 왜 요구하는지 알고 싶습니다 | [요구하는 권한](https://github.com/Orchemi/exem-wifi-switcher/wiki/permissions)              |
| 이 앱이 무엇을 어디에 설치하는지 보고 싶습니다  | [설치되는 항목 전부](https://github.com/Orchemi/exem-wifi-switcher/wiki/what-gets-installed) |
| 무언가 동작하지 않습니다                        | [문제 해결](https://github.com/Orchemi/exem-wifi-switcher/wiki/troubleshooting)              |
| 소스를 읽고 직접 빌드하고 싶습니다              | [직접 빌드하기](https://github.com/Orchemi/exem-wifi-switcher/wiki/building)                 |


회사 밖에서 먼저 설치한 경우 · 업데이트 · 한계를 비롯한 나머지 문서는 [Wiki](https://github.com/Orchemi/exem-wifi-switcher/wiki) 에 있고, 이 저장소에 코드를 올리거나 릴리즈를 만드신다면 [커밋·배포 전에 반드시 지켜야 할 것](./RULES.md) 을 먼저 읽어 주세요.

## 문제 신고

취약점을 포함한 문제 제보는 [SECURITY.md](./SECURITY.md) 를 봐 주세요.

## 라이선스

[MIT](./LICENSE)