# dummy 아바타 (개발용)

M-A 마일스톤("소켓 없이 펫이 화면/창 위를 돌아다닌다")을 클론 직후 바로 실행 가능하게 하기 위한 개발용 더미 아바타입니다.
`manifest.json`은 `protocol` 저장소 6절 스키마를 그대로 따릅니다.

## 아직 없는 실 자산 (강상우 담당, 추가 예정)

- `dummy.usdz` — Meshy 프리셋 등을 리네이밍한 수준으로 충분 (02_pet-app.md "아바타 리소스 소비" 절 참고). 필수 클립: `idle`, `walk`. 권장: `climb`, `fall`, `land`, `point`, `type`, `listen`, `react_click`, `react_drag`.
- `sounds/*.wav` — `manifest.json`의 `sounds` 테이블이 참조하는 7개 파일.

usdz/오디오 바이너리는 Git LFS로 추적합니다 (`.gitattributes` 참고). 이 폴더에 실 파일을 추가하기 전까지 `AvatarLoader`는 누락 클립을 idle로 폴백하고 시작 시 경고를 남기도록 설계되어 있습니다 (02_pet-app.md F2).
