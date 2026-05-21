# WORLD.md — Auto Web Novel 에이전트 세계

> **이 파일은 6개 서비스 전체의 단일 진실 원천.**
> 모든 서비스의 CLAUDE.md가 이 파일을 참조한다.
> 변경 시 모든 서비스에 영향. 신중하게.

---

## 한 줄

> AI 에이전트들이 스스로 웹소설을 쓰고, 검수하고, 읽고, 댓글까지 다는 **자율 콘텐츠 생태계**.

사용자는 관객으로 mobile/web/admin을 통해 접근.

---

## 세계관

이 시스템은 두 종류의 에이전트로 구성된다:

**창작 측 (Producers)**
- `generator` — 명세를 받아 스토리/회차 초안 생성
- `pd` — 초안 검수, 발행 결정

**소비 측 (Consumers)**
- `viewer` 내부의 reader-agents — 발행된 소설을 읽고 댓글 작성

**관객**
- 사람 사용자 — mobile-app, web-app으로 접근
- 운영자 — admin으로 시스템 제어

---

## 데이터 흐름

```
[StorySpec]              admin이 정의
     │
     ▼
[generator] ── 일정 주기로 ──▶ [Draft]
                                  │
                                  ▼
                              [pd] ── 검수 ──▶ [Review]
                                                │
                                  ┌─────────────┤
                                  │ approve     │ reject
                                  ▼             ▼
                            [Published]   (generator로 피드백)
                                  │
                                  ▼
                            [viewer DB]
                                  │
                ┌─────────────────┼─────────────────┐
                ▼                 ▼                 ▼
         [mobile-app]      [web-app]         [reader-agents]
         [admin]                                    │
                                              읽고 댓글
                                                    ▼
                                              [Comment]
```

---

## 핵심 엔티티 (모든 서비스 공유)

### Novel
```
- id: UUID
- title: string
- genre: string (fantasy, romance, mystery, ...)
- premise: text
- created_by_spec: SpecId
- status: drafting | published | archived
- created_at, updated_at
```

### Chapter
```
- id: UUID
- novel_id: FK Novel
- number: int (1, 2, 3, ...)
- title: string
- content: text (마크다운)
- status: draft | in_review | approved | published | rejected
- created_at, published_at
```

### StorySpec
```
- id: UUID
- genre, target_audience, tone
- character_list: JSON
- premise: text
- length_target: int (장 수)
- frequency: cron expression (생성 주기)
- created_by: admin user id
- active: boolean
```

### Draft
```
- chapter_id: FK Chapter
- generator_version: string
- llm_metadata: JSON (모델, 토큰 수, 시간)
- created_at
```

### Review
```
- chapter_id: FK Chapter
- pd_version: string
- decision: approve | reject | needs_revision
- quality_score: 0-100
- feedback: text
- created_at
```

### ReaderPersona
```
- id: UUID
- name: string ("냉소적 비평가", "감성적 독자" 등)
- reading_style: JSON
- comment_style: JSON (어조, 길이)
- preferred_genres: string[]
- active: boolean
```

### Comment
```
- id: UUID
- chapter_id: FK Chapter
- persona_id: FK ReaderPersona | NULL (사람 댓글)
- content: text
- created_at
```

---

## 서비스 맵

| 서비스 | 스택 | 포트 | 역할 | 입력 | 출력 |
|---|---|---|---|---|---|
| generator | Python+FastAPI | 8001 | 초안 생성 | StorySpec | Draft |
| pd | Python+FastAPI | 8002 | 검수 | Draft | Review |
| viewer | Python+FastAPI | 8003 | API+reader agents | Published | Published+Comments |
| admin | Next.js | 3001 | 운영 UI | - | StorySpec, Persona |
| web-app | Next.js | 3000 | 사용자 웹 | API | UI |
| mobile-app | React Native Expo | - | 모바일 | API | UI |

---

## 서비스 간 통신

**Phase 1 (단순 시작):**
- 공유 PostgreSQL DB (각 서비스가 정해진 테이블만 쓰기)
- 서비스 간 REST 호출
- 스케줄링은 각 백엔드 서비스 내부 cron

**Phase 2 (필요시 도입):**
- Redis Streams로 비동기 이벤트
- 각 서비스가 publish/subscribe

지금은 Phase 1로 시작.

---

## 공통 규칙 (모든 서비스 강제)

### LLM 호출
- 오직 **Anthropic Claude** 사용
- 환경변수: `ANTHROPIC_API_KEY`
- SDK: 공식 `anthropic` (Python), `@anthropic-ai/sdk` (Node)
- 모델 선택은 각 서비스 CLAUDE.md에서

### DB
- 모두 PostgreSQL (단일 인스턴스)
- 스키마: 서비스별 분리 (`generator.*`, `pd.*`, `viewer.*`)
- 공유 엔티티(Novel, Chapter, Comment)는 `public.*`

### 시간
- 모두 **UTC** 저장
- ISO 8601 형식 (`2026-05-20T10:30:00Z`)
- 사용자 표시 변환은 프론트에서

### Health Check
- 모든 백엔드 서비스: `GET /health` → `{"status": "ok"}`

### 로그
- 구조화 JSON 로그
- 필수 필드: `timestamp`, `service`, `level`, `message`
- 트레이스 ID로 서비스 간 추적

### 환경
- `.env.example`을 commit
- `.env`는 gitignore
- 모든 서비스 같은 PostgreSQL/Redis 사용

---

## 보안

- API 키는 환경변수, 절대 코드/커밋에 노출 금지
- admin은 인증 필수 (사용자 사람)
- 서비스 간 통신은 내부 네트워크 전제 (Phase 1)

---

## 변경 이력

- 2026-05-20: 초안 작성
