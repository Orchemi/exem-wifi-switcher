# 설치되는 항목 전부

무엇이 어디에 어떤 소유·권한으로 설치되는지, 그리고 제거하면 무엇이 사라지고 무엇이 남는지 적었습니다.

[← README 로 돌아가기](../README.md) · [문서 목록](./index.md)

이 도구는 `sudoers` 를 수정하고 로그인 항목을 등록합니다. 무엇이 어디에 설치되는지 숨기지 않습니다.

| 경로 | 소유·권한 | 무엇 |
|---|---|---|
| `/usr/local/libexec/exem-wifi-switcher/` | `root:wheel 0755` | 아래 두 스크립트를 담는 디렉터리 |
| `/usr/local/libexec/exem-wifi-switcher/apply` | `root:wheel 0755` | • `networksetup` 호출, **암호 없이 실행**<br>• 인자는 프로필 이름 1개, 화이트리스트 검증 |
| `/usr/local/libexec/exem-wifi-switcher/save-config` | `root:wheel 0755` | • 설정 파일을 아래 `config.json` 경로에 저장합니다<br>• **암호 없이 실행되지 않습니다** |
| `/etc/sudoers.d/exem-wifi-switcher` | `root:wheel 0440` | • `apply` 만 암호 없이 허용합니다<br>• 와일드카드 없이 인자 패턴을 길이별로 고정 |
| `/usr/local/etc/exem-wifi-switcher/` | `root:wheel 0755` | 설정 디렉터리 |
| `/usr/local/etc/exem-wifi-switcher/config.json` | `root:wheel 0644` | 사용자 설정. 사내 IP 값이 여기에만 저장되고 저장소에는 올라가지 않습니다 |
| (파일 아님. macOS 의 로그인 항목 기록) | 사용자 | • 로그인 시 자동 실행(선택), 설정 창에서 등록<br>• `SMAppService` 등록, 파일은 없습니다 |
| `~/Library/LaunchAgents/com.horbis.exem-wifi-switcher.agent.plist` | 사용자 | • **0.1.0 이전 버전**의 로그인 항목<br>• 새 버전 실행 시 자동으로 옮기고 지웁니다 |
| `~/Library/Preferences/com.horbis.exem-wifi-switcher.plist` | 사용자 | 앱이 남기는 설정값(자동 전환 켜짐과 꺼짐 등). 앱이 만듭니다 |

로그인 항목을 확인하고 끄는 경로는 [로그인 시 자동 실행](./settings.md#로그인-시-자동-실행) 에,
`save-config` 가 저장할 때마다 관리자 인증을 받는 이유는
[저장할 때 관리자 인증을 한 번 받습니다](./settings.md#저장할-때-관리자-인증을-한-번-받습니다) 에 적어 두었습니다.

상위 디렉터리(`/usr/local`, `/usr/local/libexec`, `/usr/local/etc`)가 없으면 `root:wheel 0755` 로 만듭니다.
이미 있으면 건드리지 않습니다.

이미 설정 파일이 있으면 **내용은 그대로 두고 소유와 권한만 위 값으로 맞춥니다.**
(예전 버전은 `root:admin 0664` 로 설치했습니다. 그 상태에서는 admin 그룹의 아무 프로세스나 값을 바꿀 수 있습니다)

앱 자체(`EXEM Wifi Switcher.app`)는 설치하신 폴더에 그대로 있습니다. 설치가 앱을 옮기지 않습니다.

## 앱의 설치 버튼이 실행하는 것

앱의 **[설치]** 버튼이 실행하는 것은 이 저장소의 [`scripts/install.sh`](../scripts/install.sh) 그대로입니다.
앱 번들 안(`Contents/Resources/scripts/`)에 같은 파일이 들어 있어서, 터미널로 설치한 사람과
앱으로 설치한 사람의 결과가 같습니다.

누르기 전에 보여주는 목록도 앱이 지어낸 것이 아니라, 그 스크립트가 `--dry-run` 으로 내놓은 내용 그대로입니다.

## 제거하면 무엇이 사라지고 무엇이 남나요

제거하는 방법은 [README 의 제거](../README.md#제거) 에 있습니다. **앱 자체가 함께 사라지는지는 어느 길로
제거하느냐에 따라 갈립니다.**

| 제거하는 길 | 위 표의 설치 항목 | 앱 번들(`EXEM Wifi Switcher.app`) |
|---|---|---|
| 설정 창의 **[앱 삭제…]** | 지웁니다 | 휴지통으로 옮기고 앱이 종료됩니다.<br>휴지통을 비우기 전까지 되돌릴 수 있습니다 |
| 터미널의 `uninstall.sh` | 지웁니다 | 남습니다. 직접 휴지통으로 옮겨 주세요 |

로그인 항목은 앱 번들이 사라지면 macOS가 함께 정리합니다. **[앱 삭제…]** 는 번들을 옮기기 전에 등록도 함께 끕니다.

어느 길로 제거하든 아래 둘은 남으므로 직접 정리해 주세요.

- **알림 권한.** **시스템 설정 > 알림** 에서 `EXEM Wifi Switcher` 항목을 지웁니다.
  macOS는 이것을 명령으로 지우는 방법을 제공하지 않습니다
- `/usr/local/libexec` · `/usr/local/etc` 디렉터리. 이 도구가 만들었더라도 다른 도구가 쓸 수 있어 남깁니다
