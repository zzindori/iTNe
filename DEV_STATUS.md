# iTNe 개발 완료 상태

## ✅ 완료된 항목

### 1) 데이터 계약 확정
- ✅ AI 결과 JSON 스키마: `schemas/ai_result.schema.json`
- ✅ enum 목록 확정 (category, freshnessHint, amountLabel, usageRole, stateTags)
- ✅ config 매핑 키 이름: `assets/app_config.json`

### 2) 로컬 저장/DB 스키마
- ✅ SQLite 테이블/마이그레이션: `lib/data/db/app_database.dart`
- ✅ captures, capture_state_tags, capture_events 테이블 생성
- ✅ 기본값 정책(ETC/식재료) 확정

### 3) 모델/DAO 레이어
- ✅ CaptureRecord 모델: `lib/models/capture_record.dart`
- ✅ AiResult 모델: `lib/models/ai_result.dart`
- ✅ CaptureDao: CRUD + upsert + 태그 재구성 + fallback

### 4) 촬영 파이프라인 연결
- ✅ 촬영 즉시 파일 저장 + DB 레코드 생성
- ✅ 썸네일 생성(선택 사항 - 미구현, 필요 시 추가 가능)

### 5) AI 비동기 파이프라인
- ✅ 촬영 직후 인식 요청 큐잉
- ✅ Google Gemini 2.0 Flash 모델 통합
- ✅ REST API 방식으로 generativelanguage.googleapis.com 호출
- ✅ 결과 수신 → DB 업데이트
- ✅ 실패/타임아웃 처리
- ✅ Mock fallback (AI 비활성화 시)

### 6) 분류 로직(안정성)
- ✅ confidence 기준 fallback (< 0.3: ETC, < 0.55: secondaryLabel 제거)
- ✅ "아니다" 처리 시 상위 fallback
- ✅ ETC/상위 라벨 처리 규칙

### 7) UI 오버레이
- ✅ 사진 위 아이콘 오버레이
- ✅ freshnessHint(⏳) 아이콘 표시
- ✅ amountLabel/secondaryLabel 조건부 표시
- ✅ 카테고리 아이콘 매핑

### 8) QA/계측
- ✅ 로딩/지연/에러 로그 (debugPrint)
- ✅ 흐름 중단 없는지 확인 (비동기 큐, try-catch)
- ⚠️ 샘플 데이터 회귀 테스트 (수동 테스트 필요)

### 9) config 정리
- ✅ 표시명/아이콘 매핑
- ✅ 다국어/문구 외부화 (`app_strings.json`)

## 🔧 설정 가이드

### AI 활성화
1. `ai_enabled: true` (이미 설정됨)
2. API 키 주입:
    ```bash
    flutter run --dart-define=GEMINI_API_KEY=AIzaSyDlIzSBTtwF2-me8782kbbQxXVoCaJKKk0
    ```

### 주요 설정 파일
- `assets/app_config.json`: 앱 동작 설정
- `assets/app_strings.json`: UI 문구
- `lib/config/app_config.dart`: 런타임 키 주입 지원

## 📊 분석 결과
```
flutter analyze
No issues found! (ran in 3.0s)
```

## 🚀 실행 예시
```bash
# Mock AI (개발)
flutter run

# 실제 Gemini API (프로덕션)
flutter run --dart-define=GEMINI_API_KEY=AIza...
```

## 📝 주요 파일 구조
```
lib/
├── config/
│   ├── app_config.dart (설정 + 런타임 키)
│   └── app_strings.dart
├── data/
│   ├── db/
│   │   └── app_database.dart
│   ├── dao/
│   │   └── capture_dao.dart
│   └── services/
│       └── ai_recognition_service.dart (Gemini 통합)
├── models/
│   ├── ai_result.dart
│   ├── capture_record.dart
│   └── captured_photo.dart
├── screens/
│   └── split_camera_screen.dart (촬영 + DB 저장)
└── widgets/
    ├── camera_preview_section.dart
    └── photo_gallery_section.dart (오버레이 + 피드백)
```

## ⚡ 개발 완료
모든 핵심 기능 구현 완료. 사용자 테스트 준비 완료.
