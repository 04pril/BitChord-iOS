#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Merge reviewed Korean UI strings; retain English for the less-used long tail."""
from pathlib import Path
import copy,json,re
root=Path(__file__).resolve().parents[1]
p=root/'App/BitChord/Resources/Localizable.xcstrings'
j=json.loads(p.read_text());strings=j['strings']
unit=lambda s:{'stringUnit':{'state':'translated','value':s}}
# Each .lproj is looked up directly by the in-app language picker, so seed all
# keys from English to avoid showing resource keys for untranslated screens.
for key,entry in strings.items():
    loc=entry.setdefault('localizations',{})
    if 'ko' not in loc:loc['ko']=copy.deepcopy(loc.get('en',unit(key)))
translated=0;skipped=[]
fmt=lambda s:sorted(re.findall(r'%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?(?:ll|l|z)?[diuoxXfFeEgGaAcCsSp@]',s))
for line in (root/'scripts/localization/ko.tsv').read_text().splitlines():
    if not line:continue
    key,value=line.split('\t',1)
    if key not in strings:raise ValueError('Unknown translation key '+key)
    source=strings[key]['localizations'].get('en',unit(key))
    en=source.get('stringUnit',{}).get('value')
    plural=source.get('variations',{}).get('plural')
    if plural:en=next(iter(plural.values()))['stringUnit']['value']
    if en is None or (fmt(en)!=fmt(value) and key!='shelf_100_on_repeat'):
        skipped.append(key);continue
    strings[key]['localizations']['ko']=({'variations':{'plural':{'other':unit(value)}}} if plural else unit(value));translated+=1
new={
 'proxy_title':('Proxy','프록시'),
 'proxy_subtitle':('In-app WireGuard, HTTP, HTTPS or SOCKS5','앱 내부 WireGuard · HTTP · HTTPS · SOCKS5'),
 'show_lyrics_provider':('Show lyrics source and Change button','가사 출처와 변경 버튼 표시'),
 'show_lyrics_provider_subtitle':('Show the provider caption above the player controls','플레이어에 가사 제공 서비스와 변경 버튼을 표시합니다'),
}
# The native controller also follows the in-app language selection.
source=(root/'App/BitChord/ProxyNative/YTMUWGSettingsController.m').read_text()
for key,value in re.findall(r'WGLOC\(@"([^"]+)", @"((?:[^"\\]|\\.)*)"\)',source):
    new[key]=(json.loads('"'+value+'"'),json.loads('"'+value+'"'))
ko={
'WG_TITLE':'프록시','WG_SECTION_TUNNEL':'연결 설정','WG_SECTION_SERVER':'프록시 서버','WG_SECTION_PROFILE':'WireGuard 프로필','WG_SECTION_CHECKS':'연결 확인','WG_SECTION_RESULT':'진단 결과','WG_ENABLED':'사용','WG_KIND':'연결 방식','WG_IMPORT_FILE':'WireGuard 파일 가져오기','WG_IMPORT_CLIPBOARD':'클립보드에서 가져오기','WG_IMPORT_AGAIN':'WireGuard 파일 다시 가져오기','WG_IMPORT_HINT':'단일 피어가 있는 표준 WireGuard .conf 파일을 선택하세요 (64KB 이하).','WG_CHECK_COUNTRY':'IP·국가 확인','WG_CHECK_CONNECTION':'연결 진단 실행','WG_CHECK_COPY':'진단 복사','WG_CHECK_SCAN':'전송 경로 확인','WG_CANCEL':'취소','WG_DELETE':'삭제','WG_DONE':'완료','WG_OK':'확인','WG_SAVE_CONNECTION':'연결 방식 저장','WG_OPTIONAL':'선택 사항','WG_HOST':'서버 주소','WG_PORT':'포트','WG_USERNAME':'사용자 이름','WG_PASSWORD':'비밀번호','WG_PASSWORD_SAVED':'저장됨 · 비워두면 유지','WG_STATE_OFF':'이번 실행에서는 꺼져 있음','WG_STATE_UNSUPPORTED':'iOS 17 이상에서 사용할 수 있습니다','WG_STATE_WAITING':'프로필을 기다리는 중 · 기기 잠금을 해제하세요','WG_STATE_STARTING':'연결 중…','WG_STATE_RUNNING':'연결됨','WG_STATE_FAILED':'연결 실패 · 직접 연결로 우회하지 않고 요청을 차단합니다','WG_STATE_BLOCKED':'설정을 사용할 수 없어 요청을 차단합니다','WG_CHECKING':'확인 중…','WG_COPIED_TITLE':'복사 완료','WG_COPIED':'진단 내용을 복사했습니다','WG_RESTART_TITLE':'앱을 다시 열어주세요','WG_RESTART_MESSAGE':'설정을 적용하려면 BitChord를 완전히 종료한 뒤 다시 열어주세요.','WG_CLOSE_NOW':'앱 종료','WG_NO_PROFILE_TITLE':'프로필 없음','WG_NO_PROFILE':'WireGuard .conf 파일을 먼저 가져오세요.','WG_IMPORT_FAILED':'가져오지 못했습니다','WG_DELETE_PROFILE':'WireGuard 프로필 삭제','WG_DELETE_MESSAGE':'저장된 WireGuard 프로필을 삭제할까요?','WG_DELETE_FAILED':'삭제하지 못했습니다','WG_FOOTER_TUNNEL':'시스템 VPN 없이 앱 안에서 연결합니다. 설정을 바꾼 뒤 앱을 다시 열어주세요. 연결에 실패하면 직접 연결로 우회하지 않습니다.','WG_FOOTER_PROFILE':'단일 피어와 AllowedIPs 0.0.0.0/0이 있는 표준 .conf를 사용합니다. 개인키는 이 기기의 Keychain에 저장하며 진단에 포함하지 않습니다.','WG_FOOTER_SERVER':'HTTP·HTTPS는 CONNECT 방식입니다. HTTPS는 프록시 인증서를 확인하며 SOCKS5는 사용자 이름·비밀번호 인증을 지원합니다.','WG_CHECKS_NOTE':'국가 확인 후 실제 곡 재생도 확인하세요. 시스템 VPN을 끈 상태에서 테스트하세요.'
}
for key,values in json.loads((root/'scripts/localization/native.json').read_text()).items():
    new[key]=(values['en'],values['ko'])
for key,(en,ko_default) in new.items():
    entry=strings.setdefault(key,{})
    loc=entry.setdefault('localizations',{});loc['en']=unit(en)
    value=ko.get(key,ko_default)
    if fmt(en)!=fmt(value):raise ValueError('Format mismatch in '+key)
    loc['ko']=unit(value)
j['strings']=strings;p.write_text(json.dumps(j,ensure_ascii=False,indent=2,separators=(',', ' : '))+'\n')
print(f'{translated} reviewed Korean entries applied; {len(strings)} entries available including English fallbacks. Format-sensitive entries left unchanged: {skipped}')
