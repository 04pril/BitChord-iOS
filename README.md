# BitChord iOS · 한국어와 앱 내부 프록시

[maanya145/BitChord-iOS](https://github.com/maanya145/BitChord-iOS)를 기반으로 한 개인 포크입니다.
원래 BitChord의 디자인을 유지하면서 한국어 선택, 가사 폰트·표시 설정, 앱 내부 프록시와 재생 위젯 앱 열기 패치를 추가했습니다.

**[IPA 다운로드 / 릴리즈](https://github.com/04pril/BitChord-iOS/releases)** · [원본 README](docs/UPSTREAM-README.md)

## 추가한 기능

- **한국어 선택:** Settings → Language → App language → **한국어**. 홈·검색·보관함·플레이어·설정 등 자주 쓰는 화면의 문구 666개와 프록시·진단 문구를 번역했습니다. 아직 번역하지 않은 화면과 설명은 영어로 표시합니다. 기존 언어도 그대로 선택할 수 있습니다.
- **가사 폰트 설정:** 설정 → 화면 및 플레이어 → **가사 폰트 설정**. 미리보기와 함께 22~44pt 크기, 5단계 굵기를 조절합니다. 전체에 같은 값을 쓰거나 한글·영문을 따로 설정할 수 있으며, 한 줄에 섞인 가사에도 각각 적용합니다. 기본값은 기존 34pt·Heavy에서 32pt·Bold로 낮췄습니다.
- **가사 표시 옵션:** 같은 페이지에서 출처·변경 버튼과 가사 흐림을 조절합니다. 출처는 기본으로 숨기며, 끄면 해당 줄의 공간도 제거됩니다. 번역·로마자 버튼은 가사 위에 겹치지 않도록 가사 영역 하단의 별도 줄에 배치했습니다.
- **애드온 연결 확인:** 공식 앱 인증을 요구하는 매니페스트는 연결 확인 때 검색 API까지 시험해 실제 검색이 거부되면 오류로 표시합니다. `bitchord.confih.tech`는 공식 Android 앱용 하드웨어 인증을 요구하므로 현재 iOS 포크에서는 검색할 수 없습니다.
- **프록시:** 설정에서 **계정 및 연동 → 함께 듣기 → 프록시** 순서로 같은 그룹에 표시됩니다. 앱 내부 WireGuard와 외부 HTTP·HTTPS·SOCKS5를 지원합니다.
- **재생 위젯 앱 열기:** 잠금화면·다이나믹 아일랜드에서 앱이 열리지 않는 경우를 보완하기 위해 실제 설치된 번들 ID를 Now Playing 앱 연결 대상으로 지정합니다. 프록시 화면의 **앱 열기 진단**에서 상태를 확인하거나 이 패치를 끌 수 있습니다.

## 설치

1. Releases에서 `BitChord-1.0.2-20-KR-Proxy.ipa`를 받습니다.
2. Feather 등 서명 도구에서 **본인 인증서로 앱 전체를 재서명**해 설치합니다. 릴리즈 파일의 ad-hoc 서명은 기기에 바로 설치하는 개발자 서명이 아닙니다.
3. 앱 설정의 Language에서 한국어를 선택합니다. 기기의 언어 설정이 한국어이면 자동으로 선택될 수도 있습니다.
4. 프록시를 사용할 경우 본인의 WireGuard `.conf`를 가져오거나 외부 프록시 서버 정보를 입력합니다.
5. 연결 방식을 저장하고 사용을 켠 다음, 앱을 완전히 종료했다가 다시 엽니다. 시스템 VPN을 끈 상태에서 국가 확인과 실제 곡 재생을 확인합니다.

앱의 식별자는 `com.music.bitchord`, 버전은 1.0.2, 빌드 번호는 20입니다. 기존 앱 위에 설치할 때 같은 서명 접근 그룹을 유지해야 Keychain의 로그인·프록시 설정에 계속 접근할 수 있습니다. 달라지면 다시 로그인하거나 프로필을 가져와야 할 수 있습니다.

개인 WireGuard 설정, 개인키, 개인 인증서는 소스나 IPA에 포함하지 않습니다. 프록시 개인키·비밀번호는 기기의 Keychain에 저장하며 진단에는 넣지 않습니다. 사용자 자신의 프로필이 필요합니다.

## 연결 방식과 범위

```
BitChord URLSession API / HTTPAudioSource 음악 캐시
  → 인증된 로컬 SOCKS5·CONNECT
  → wireguard-go + gVisor 사용자 공간 네트워크
  → 사용자가 지정한 WireGuard 서버
```

시스템 VPN 프로필이나 Network Extension을 만들지 않습니다. URLSession에 적용한 프록시가 실패하면 직접 연결로 전환하지 않습니다. WireGuard 모드의 음원 호스트 DNS 조회도 터널에서 처리합니다. 서버 Endpoint가 호스트 이름이면 터널을 만들기 전 기기 DNS로 한 번 조회합니다.

이 범위는 **URLSession을 사용하는 요청과 캐시 HTTP 오디오 경로**입니다. 별도 시스템 프로세스가 처리하는 AVFoundation의 직접 HLS/커버 영상, WebKit 로그인 화면, SMB까지 기기 전체 VPN처럼 처리하는 기능은 아닙니다. 이 경로들은 프록시를 우회할 수 있습니다. 국가 확인 성공만으로 실제 음악 재생 성공을 판단하지 마세요.

표준 단일 피어 WireGuard `.conf`를 사용합니다. `AllowedIPs`에 `0.0.0.0/0`, `DNS`에는 숫자 IP가 필요합니다. 변경한 연결 방식은 앱 재시작 후 적용됩니다.

## 앱 열기 패치

`MRMediaRemoteSetParentApplication`에 실제 번들 ID를 전달합니다. `application-identifier`는 진단용으로 읽을 뿐 수정하지 않습니다. 이 방식은 YTMU에서 사용자 실기기 해결 확인을 받은 패치를 BitChord에 맞춘 것입니다.

**BitChord에서의 실제 아이폰 앱 열기와 음악 재생은 아직 사용자 확인 전입니다.** 비공개 MediaRemote API이므로 다른 기기·서명 조합에서 동작이 다를 수 있습니다. API 미지원이나 Objective-C 예외가 발생하면 연결 요청을 건너뛰거나 해당 실행에서 중단합니다. 요청 횟수 자체는 iOS의 승인을 뜻하지 않습니다.

## YouTube AAC 첫 재생 최적화 (빌드 20)

YouTube에서 제공하는 AAC HTTP 스트림에만 첫 최대 1MiB의 독립 캐시 수신을 적용합니다. AVFoundation의 짧은 탐색 요청이 취소돼도 선행 수신은 유지되며, 같은 범위의 읽기는 진행 중인 fetch를 공유합니다. 첫 데이터가 준비되면 바로 전달하고 전체 수신 완료를 기다리지 않습니다.

곡이나 소스를 교체하거나 로딩을 취소하면 선행 수신도 취소합니다. Opus, 외부 음원, HLS, 로컬 파일에는 이 정책을 적용하지 않습니다. 기존 콘텐츠 길이 검사와 YouTube MP4 duration 보정은 유지합니다. `YouTube AAC opening warmup`과 `opening fetch shared` 로그로 동작을 확인할 수 있습니다. 실제 속도 개선 폭은 실기기 비교가 필요합니다.

## 첫 재생 진단 (빌드 19)

- `AV resource request #… started/completed/cancelled`: AVFoundation이 보낸 각 리소스 요청의 오프셋과 처리 시간.
- `AV read #…`: 요청 범위, 총 처리 시간, 디스크 캐시에서 전달한 바이트와 fetch 스트림에서 전달한 바이트, 첫 fetch 데이터까지 기다린 시간.
- `HTTP range #…`: 각 HTTP Range의 요청·응답 헤더·첫 본문 시각과 종료 때의 수신량·전달량·상태.

`fetch stream`은 AudioCacheStore의 진행 중인 fetch에서 전달받은 바이트입니다. 여러 읽기가 같은 fetch를 공유할 수 있으므로 이 수치만으로 각각 별도 네트워크 요청을 했다고 볼 수는 없습니다. 실제 HTTP 요청 수와 대기 시간은 `HTTP range` 로그와 함께 비교하세요.

## 직접 빌드

Mac, Xcode 27, Go 1.27.x가 필요합니다. Go와 Swift 패키지 의존성을 받을 수 있는 인터넷 연결이 필요합니다.

```sh
git clone https://github.com/04pril/BitChord-iOS.git
cd BitChord-iOS
scripts/make-ipa.sh
```

이 명령이 한국어 카탈로그와 iOS WireGuard 엔진을 준비한 뒤 Release 앱과 확장을 빌드·패키징합니다. 결과는 `build/BitChord-1.0.2-20-KR-Proxy.ipa`입니다. 설치 전 본인의 인증서로 재서명하세요.

GitHub Actions의 **Build IPA**에서도 실행할 수 있습니다. 생성한 IPA는 워크플로 아티팩트로 내려받습니다. Go 엔진 없이 Xcode에서 직접 빌드하려면 먼저 다음 명령을 실행합니다.

```sh
MIN_IOS=17.0 bash WireGuard/build-ios.sh
open BitChord.xcworkspace
```

실기기와 시뮬레이터는 서로 다른 Go 아카이브가 필요합니다. 시뮬레이터 빌드 전에는 `SDK_NAME=iphonesimulator bash WireGuard/build-ios.sh`를 실행합니다.

## 검증한 범위

- iOS arm64 Release 앱·공유 확장·위젯 확장 빌드와 IPA 서명 무결성 검사.
- 설정 저장과 백업 등 BitChordCore 테스트 **155개** 통과. 가사 출처 표시 설정의 기본값과 재실행 후 저장도 포함합니다.
- 실제 UIKit/TextKit으로 혼합 가사의 크기·굵기, 줄바꿈과 폰트 변경 후 레이아웃 갱신을 확인했습니다. 새 설정 화면과 버튼 위치는 실기기 확인이 필요합니다.
- 앱 열기 패치의 모의 미디어 API 검사 **19개** 통과.
- WireGuard 엔진의 `go test -race` 통과.
- 실제 macOS Foundation/Network.framework와 로컬 WireGuard 테스트 피어를 사용해 HTTPS, HTTP 206, 터널 DNS, 연결 실패 시 직접 연결 차단, HTTP·HTTPS·SOCKS5 동작 확인.
- IPA에 포함된 한국어 문자열·복수형 및 포맷 인자 확인.

아이폰 설치, 실제 서비스의 곡 재생, Wi-Fi/셀룰러 전환, 이 BitChord 빌드의 재생 위젯 앱 열기는 별도 실기기 확인이 필요합니다. 릴리즈는 이 범위를 명시한 시험 버전입니다.

```sh
# 엔진 테스트
(cd WireGuard && go test -race ./...)
# Apple 네트워크 스택을 통한 터널 테스트 (Mac)
python3 tests/proxy/run_macos.py
# 앱 열기 로직: 모의 MediaRemote
xcrun clang -fobjc-arc -fblocks tests/nowplaying/harness.m -framework Foundation -o /tmp/nowplaying-check
/tmp/nowplaying-check
```

## 출처와 라이선스

- iOS 앱: [maanya145/BitChord-iOS](https://github.com/maanya145/BitChord-iOS), 기반 커밋 `390b05884987c018b2efffaef535a92d9f3d9999`.
- 원 프로젝트: [kushagrasinghx/BitChord](https://github.com/kushagrasinghx/BitChord).
- 앱 내부 프록시 기반: [04pril/ytmu](https://github.com/04pril/ytmu), `dea97f498f2916535fb5ef292e1f461a8f11ca87`의 엔진·설정 코드. 원래 통합의 기반은 [kes158/YTMusicUltimate](https://github.com/kes158/YTMusicUltimate)입니다. BitChord에 맞게 설정과 통신 진단을 조정했습니다.
- [GPL-3.0](LICENSE), [기존 서드파티 고지](THIRD-PARTY-NOTICES.md), [WireGuard 구성 요소 라이선스](WireGuard/THIRD_PARTY_LICENSES.txt). Automix 등의 기존 AGPL 고지도 유지합니다.

Google·YouTube·Apple의 공식 앱이 아닙니다.
