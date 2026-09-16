# 창맞춤 · WindowFit

단축키와 가장자리 드래그로 창을 정리하는 macOS 메뉴 막대 앱입니다. Swift와 Apple 기본 프레임워크로 만들었으며 외부 패키지는 필요하지 않습니다.

## 기능

- 좌우·상하 절반, 네 모서리 4분할
- 메뉴 막대와 Dock을 제외한 화면에 맞추기
- 가운데 배치 및 원래 위치·크기 복원
- 제목 막대를 가장자리로 끌어 놓기와 배치 미리보기
- 다중 모니터 좌표 처리
- Chrome의 확장 접근성 모드에서 발생하는 창 크기 변경 충돌 처리

## 빌드와 실행

검증 환경: Apple Silicon, macOS 26.6.2, Xcode의 Swift 6.3.3. 다른 환경에서의 호환성은 검증하지 않았습니다.

```sh
git clone https://github.com/Harry1757/windowfit.git
cd windowfit
./build.command
open 창맞춤.app
```

처음 실행하면 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 창맞춤을 허용하세요. 앱은 Dock 대신 메뉴 막대에 표시됩니다.

개인용 임시 코드 서명을 사용합니다. 다시 빌드한 뒤 설정이 켜져 있어도 권한이 적용되지 않는다면, 손쉬운 사용 목록에서 이전 항목을 제거하고 현재 앱을 다시 추가하세요.

## 단축키

모든 키에 **Control + Option**을 함께 누릅니다.

| 키 | 동작 |
|---|---|
| ← / → | 왼쪽 / 오른쪽 절반 |
| ↑ / ↓ | 위쪽 / 아래쪽 절반 |
| U / I | 왼쪽 위 / 오른쪽 위 |
| J / K | 왼쪽 아래 / 오른쪽 아래 |
| Return | 화면에 맞추기 |
| C | 가운데로 |
| Delete | 원래 위치·크기로 |

메뉴에서 같은 동작을 선택할 수 있습니다. 드래그 중 Option을 누른 채 놓으면 자동 배치를 취소합니다. macOS 자체 가장자리 타일링과 겹칠 때는 둘 중 하나를 꺼 주세요.

## 검증

```sh
./test.command
```

화면 절반·사분면 계산, 홀수 픽셀, 음수 좌표의 보조 모니터, 가장자리 감지를 검사합니다.

앱 메뉴의 **임시 창으로 배치 점검**은 별도 프로세스의 임시 창을 사용해 10개 배치와 복원을 검사합니다. 손쉬운 사용 권한이 필요하며 결과는 앱 옆 `verification.json`에 저장됩니다.

개발 환경에서 실제 Chrome 창 10개 배치를 검증했고, 사용자가 단축키와 드래그 동작을 확인했습니다. 모든 macOS 버전과 앱을 보장하는 호환성 검증은 아닙니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `Source/main.swift` | 메뉴 막대, 단축키, 손쉬운 사용을 통한 창 제어, 드래그 및 진단 |
| `Source/Layout.swift` | 배치 좌표와 가장자리 판정 |
| `Source/GeometryTests.swift` | 배치 계산 검사 |
| `build.command` | 앱 빌드 및 로컬 서명 |
| `test.command` | 계산 검사 실행 |

앱은 네트워크 요청을 보내지 않습니다. 진단 기록에는 앱 식별자와 창 좌표가 로컬로 저장될 수 있으며, 생성된 실행 앱·진단 기록·개인 환경의 검사 결과는 저장소에서 제외합니다.

## 제한

- 앱별 최소 창 크기는 강제로 줄일 수 없습니다.
- macOS 전체 화면 모드에서는 먼저 전체 화면에서 나와야 합니다.
- 복원 기록은 실행 중인 앱의 메모리에만 보관합니다.
- 로그인 시 자동 실행, 업데이트 배포, App Store 배포는 포함하지 않습니다.

자세한 설명은 [사용방법.md](사용방법.md)를 참고하세요.

기술 참고: [Apple 창 속성 변경 API](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue), [Rectangle의 접근성 창 크기 변경 처리](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift).
