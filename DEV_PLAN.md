# iTNe 개발 순서(꼬이지 않게)

1) 데이터 계약 확정
- AI 결과 JSON 스키마 확정
- enum 목록 확정 (category, freshnessHint, amountLabel, usageRole, stateTags)
- config 매핑 키 이름 확정

2) 로컬 저장/DB 스키마
- SQLite 테이블/마이그레이션 작성
- captures, capture_state_tags, capture_events (선택)
- 기본값 정책(ETC/식재료) 확정

3) 모델/DAO 레이어
- Capture 모델
- AIResult 모델
- DAO CRUD + upsert + 태그 재구성

4) 촬영 파이프라인 연결
- 촬영 즉시 파일 저장 + DB 레코드 생성
- 썸네일 생성(선택)

5) AI 비동기 파이프라인
- 촬영 직후 인식 요청 큐잉 
 ㄴ Google Gemini AI API사용
 ㄴ Gemini 2.0 Flash 모델 사용
 ㄴ Rest API 방식으로 generativelanguage.googleapis.com 호출
- 결과 수신 → DB 업데이트
- 실패/타임아웃 처리

6) 분류 로직(안정성)
- confidence 기준 fallback
- “아니다” 처리 시 상위 fallback
- ETC/상위 라벨 처리 규칙

7) UI 오버레이
- 사진 위 아이콘 오버레이
- freshnessHint(⏳) 필수
- amountLabel/secondaryLabel 조건부 표시

8) QA/계측
- 로딩/지연/에러 로그
- 흐름 중단 없는지 확인
- 샘플 데이터 회귀 테스트

9) config 정리
- 표시명/아이콘 매핑
- 다국어/문구 외부화
