---
spec_type: SRS (Software Requirements Specification)
scope: 회차 생성·검수 줄기 + AI 독자 댓글 줄기 (사람 UI·가상결제·좋아요는 범위 밖)
status: 검증 대기
updated_at: 2026-05-23
references:
  - meta-specs/Product-Requirements-Meta-Spec-Info.md §SRS
  - docs/Domain-Model.md
  - docs/Data-Model.md
  - docs/Flow-Chapter-Lifecycle.md
  - docs/Flow-AI-Reader-Comment.md
---

# SRS — 회차 생성·검수 + AI 독자 댓글 줄기

> 이 문서는 두 줄기의 기능 요구를 명세한다.
> 1. **회차 줄기 (walking skeleton 1단계)** — 회차 1건이 generator에서 생성되어 pd 검수를 거쳐 published 되거나 다시 draft로 돌아간다.
> 2. **AI 독자 댓글 줄기 (walking skeleton 2단계)** — published 회차에 AI 독자(reader-agent)가 댓글을 단다.
>
> NFR(성능·보안·가용성)과 다른 줄기(사람 UI 좋아요/댓글, 독자 가상결제)는 본 명세 범위 밖이다.

> **PRD-US 매핑 안내**: SRS-F-001~004는 PRD-US-01/02 (작가·PD)에 매핑된다. SRS-F-005~006은 PRD-US-03 (독자) 중 **댓글 부분**에만 매핑된다 — 가상결제·좋아요는 향후 SRS, 미작성.

---

## 1. 범위

**대상 — 회차 줄기**: `StorySpec → generator의 다음 회차 생성 → in_review 전환 → pd 검수 → 상태 전환` 의 흐름. 관련 엔티티는 [Domain-Model.md](Domain-Model.md), 스키마는 [Data-Model.md](Data-Model.md), 시퀀스는 [Flow-Chapter-Lifecycle.md](Flow-Chapter-Lifecycle.md) 참조.

**대상 — AI 독자 댓글 줄기**: `published Chapter → viewer의 폴링 → reader-agent의 LLM 댓글 생성 → viewer.comments INSERT` 의 흐름. 시퀀스는 [Flow-AI-Reader-Comment.md](Flow-AI-Reader-Comment.md) 참조.

**범위 밖**:
- StorySpec/ReaderPersona의 작성·관리 (admin 줄기).
- 사람 사용자의 발행 회차 노출(viewer 웹 API·web-app·mobile-app UI).
- 사람 사용자의 좋아요·댓글 (3단계+).
- AI 독자의 가상결제·좋아요 (3단계+).
- 인증·과금·운영 모니터링 등 NFR.

---

## 2. 기능 요구사항

각 항목은 메타스펙 §SRS의 필수 필드 `maps_to_prd / owner_module / acceptance`를 모두 포함한다.

### SRS-F-001 — 작가의 다음 회차 생성

**설명**: generator는 활성 StorySpec의 `frequency`에 따라 정해진 주기에 깨어나, 해당 Novel의 WriterContext와 직전까지의 Chapter들을 읽어 LLM(WORLD §LLM 호출 규칙)을 호출해 다음 Chapter의 draft 본문을 생성하고 저장한다. 이후 LLM 출력에서 추출 가능한 새 일화/떡밥 정보를 WriterContext에 갱신한다.

**maps_to_prd**: `PRD-US-01`

**owner_module**: `MOD-GENERATOR`

**acceptance**:
- Given: `StorySpec.active=true` 인 Novel이 존재하고, 해당 Novel의 직전 Chapter.number = N (Novel이 새로 생성된 직후라면 N=0)이며, 같은 Novel에 `status ∈ {draft, in_review}` 인 Chapter가 존재하지 않는다 (Domain §4.3).
- When: generator가 `frequency` cron에 의해 깨어나거나 수동 trigger를 받는다.
- Then:
  1. `public.chapters`에 `(novel_id, number=N+1, status='draft', content=…, title=…)` row가 생긴다.
  2. `generator.draft_runs`에 해당 chapter_id, 모델/토큰/시간 메타 row가 생긴다.
  3. `generator.writer_contexts`의 `episodes` 또는 `foreshadows`가 LLM 출력 기반으로 갱신될 수 있다 (갱신은 동일 트랜잭션 내, `version`을 증가시킴 — Domain §4.4).
  4. 동일 Novel에 대한 다른 generator 호출과 충돌하지 않는다 (선행 acquire 또는 부분 유니크 인덱스가 거부).
- 실패 케이스: LLM 호출 실패 시 chapter row를 만들지 않거나 별도 표시한다 (정책 `[확인 필요]`). draft_runs는 실패 메타만 남길 수 있다.

---

### SRS-F-002 — 완성 판정 후 in_review 전환

**설명**: generator는 자신이 생성한 `status='draft'` Chapter에 대해 Domain Model §4.5의 완성 판정 기준을 적용해 통과 시 `draft → in_review` 상태 전이를 수행한다.

**maps_to_prd**: `PRD-US-01`

**owner_module**: `MOD-GENERATOR`

**acceptance**:
- 완성 판정 항목:
  - (a) 최소 글자 수 충족: `[확인 필요]` — 구체 수치는 사람이 채운다.
  - (b) 회차 단위 서사 완결성 자체 점검 통과: 도입–전개–훅 등 항목. 구체 체크리스트는 `[확인 필요]`.
  - (c) WriterContext의 `foreshadows`(paid_off 상태)·`episodes`(기 사실)와 본문 간 모순 없음.
- Given: SRS-F-001로 만든 `status='draft'` Chapter가 존재하고, 위 (a)(b)(c)를 모두 통과한다.
- When: generator가 submit-for-review 동작을 수행한다.
- Then:
  1. 해당 Chapter.status가 `draft → in_review`로 전이된다.
  2. `updated_at`이 갱신된다 (pd 폴링의 정렬 기준).
  3. Domain §4.1의 상태기계가 허용하지 않는 전이(예: 이미 `in_review`인 행에 대한 재전이, `draft`가 아닌 행에 대한 호출)는 거부된다.

---

### SRS-F-003 — pd의 in_review 폴링 및 검수

**설명**: pd는 주기적으로 (주기 `[확인 필요]`) `public.chapters`에서 `status='in_review'`인 행을 `updated_at` 오래된 순으로 조회해, 각 Chapter에 대해 LLM 기반 검수를 수행하고 `pd.reviews`에 결과를 기록한다.

**maps_to_prd**: `PRD-US-02`

**owner_module**: `MOD-PD`

**acceptance**:
- Given: `public.chapters`에 `status='in_review'`인 row가 1개 이상 존재한다.
- When: pd의 폴링 cycle이 실행된다.
- Then:
  1. 각 in_review Chapter에 대해 `pd.reviews`에 `(chapter_id, pd_version, decision, quality_score, feedback, created_at)` row가 생성된다.
  2. `decision`은 `approve | reject | needs_revision` 중 하나이며 `quality_score`는 0–100 범위(Data §1).
  3. 같은 Chapter에 대한 동시 검수는 직렬화된다 — 동일 in_review row를 두 pd 인스턴스가 동시에 잡지 못한다 (구현: `FOR UPDATE SKIP LOCKED` 또는 어드바이저리 락, `[확인 필요]`).
- 실패 케이스: LLM 호출 실패 시 review row를 생성하지 않는다. Chapter는 `in_review`로 잔류해 다음 cycle에서 다시 pick up 된다.

---

### SRS-F-004 — 검수 결과에 따른 상태 전환

**설명**: pd는 방금 기록한 `pd.reviews.decision`을 보고 Chapter.status를 다음과 같이 전이시킨다.
- `approve` → Chapter.status를 `in_review → approved`로 전이한 뒤, 즉시 `approved → published`로 자동 전이하고 `published_at`을 기록한다.
- `reject` 또는 `needs_revision` → Chapter.status를 `in_review → draft`로 되돌리고, Review.feedback을 `generator.writer_contexts.feedback_log`에 누적한다 (Domain §4.6 — 동일 트랜잭션).

**maps_to_prd**: `PRD-US-02`

**owner_module**: `MOD-PD`

**acceptance**:
- Given: Chapter.status='in_review' + 방금 INSERT 된 pd.reviews row 1건.
- When: pd가 검수 결과에 따른 상태 전이를 적용한다.
- Then:
  1. Domain §4.1의 허용 전이만 발생한다 (그 외 전이 시도는 거부).
  2. `approve` 의 경우 동일 트랜잭션 내에서 `approved → published` 자동 전이까지 완료되고 `published_at`이 채워진다.
  3. `reject` / `needs_revision` 의 경우 같은 트랜잭션 안에서 다음이 모두 일어난다:
     - Chapter.status가 `draft`로 변경되고,
     - `generator.writer_contexts.feedback_log`에 `{chapter_number, decision, feedback, at}` 엔트리가 append 되며 `version`이 증가한다.
     - 어느 한 작업이 실패하면 전체 롤백.
  4. 동일 Chapter에 대한 동시 전이는 (SRS-F-003에서 잡은 락에 의해) 직렬화된다.

---

### SRS-F-005 — viewer의 published 회차 폴링·읽기

**설명**: viewer는 주기적으로 (주기 `[확인 필요]`) `public.chapters`에서 `status='published'` 인 행을 조회해, 활성 ReaderPersona 각각에 대해 "아직 댓글을 달지 않은 published chapter" 조합을 식별한다. `public.chapters` 는 viewer에게 **읽기 전용**이다.

**maps_to_prd**: `PRD-US-03` (댓글 부분 슬라이스 — 가상결제·좋아요는 본 SRS 범위 밖)

**owner_module**: `MOD-VIEWER`

**acceptance**:
- Given: `public.chapters`에 `status='published'` 인 row가 1개 이상 존재하고, `viewer.reader_personas`에 `active=true` 인 페르소나가 1명 이상 존재한다.
- When: viewer의 폴링 cycle이 실행된다.
- Then:
  1. viewer는 active persona × `published` chapter 조합 중 `viewer.comments`에 `(chapter_id, author_persona_id)` row가 없는 조합을 후보로 식별한다.
  2. 후보 발견 시 SRS-F-006의 댓글 생성으로 이어진다.
  3. 후보 없음이면 cycle을 종료한다.
- 실패 케이스: DB 조회 실패 시 cycle을 중단하고 다음 cycle에서 다시 시도한다 (특별한 상태 변경 없음).

---

### SRS-F-006 — reader-agent의 댓글 생성

**설명**: viewer는 SRS-F-005가 식별한 `(persona, chapter)` 조합 각각에 대해 persona의 ReaderIdentity 파일 3개(SOUL.md / Reading-Style.md / Comment-Style.md)와 Chapter.content를 LLM(WORLD §LLM 호출 규칙)에 입력해 댓글 본문을 생성한다. 결과는 같은 트랜잭션에서 `viewer.comments` 와 `viewer.comment_runs` 에 INSERT 된다.

**maps_to_prd**: `PRD-US-03` (댓글 부분 슬라이스 — 가상결제·좋아요는 본 SRS 범위 밖)

**owner_module**: `MOD-VIEWER`

**acceptance**:
- Given: SRS-F-005가 식별한 `(persona, chapter)` 후보가 1건 이상 존재한다.
- When: viewer가 댓글 생성 동작을 수행한다.
- Then:
  1. 후보 각각에 대해 LLM 호출이 일어나고 결과 댓글 본문이 만들어진다.
  2. 동일 트랜잭션 안에서 다음이 모두 일어난다:
     - `viewer.comments(id, chapter_id, author_persona_id, content)` row 1건 INSERT.
     - `viewer.comment_runs(id, comment_id, persona_id, viewer_version, llm_metadata)` row 1건 INSERT.
     - 어느 한 작업이 실패하면 전체 롤백.
  3. `UNIQUE (chapter_id, author_persona_id)` (Data §1) 위반은 거부된다 — 두 viewer 인스턴스의 동시 폴링 충돌을 자연 직렬화한다 (Domain §4.9).
  4. `Chapter.status='published'` 가 아닌 회차에 대한 INSERT는 거부된다 (Domain §4.8).
- 실패 케이스: LLM 호출 실패 시 해당 `(persona, chapter)` 조합에 대해 `comments`/`comment_runs` 모두 생성하지 않는다 — 다음 cycle에서 다시 후보가 된다. 실패 메타 별도 보관 여부는 `[확인 필요]`.

---

## 3. 비기능 요구사항

본 줄기 범위 밖. 추후 SRS-N 형태로 별도 명세. (성능: 폴링 주기·생성 빈도 / 보안: 서비스 간 권한 / 가용성: 재시도·중단 복구 등)

---

## 4. 추적 매트릭스

| PRD-US | SRS-F | Owner Module | 비고 |
|---|---|---|---|
| `PRD-US-01` | SRS-F-001 | MOD-GENERATOR | 회차 생성 |
| `PRD-US-01` | SRS-F-002 | MOD-GENERATOR | in_review 전환 |
| `PRD-US-02` | SRS-F-003 | MOD-PD | in_review 폴링·검수 |
| `PRD-US-02` | SRS-F-004 | MOD-PD | 검수 결과 상태 전이 |
| `PRD-US-03` (댓글 슬라이스) | SRS-F-005 | MOD-VIEWER | published 폴링·후보 식별 |
| `PRD-US-03` (댓글 슬라이스) | SRS-F-006 | MOD-VIEWER | reader-agent 댓글 생성 |

> **고지**:
> - `PRD-US-03` 은 본디 "독자 에이전트가 발행 회차에 가상결제·댓글·좋아요로 반응" 전체를 다룬다. 본 SRS의 SRS-F-005/006 은 그 중 **댓글 부분 슬라이스**만 매핑한다. 가상결제·좋아요는 향후 SRS, 미작성.
> - Module 컬럼의 `MOD-GENERATOR`, `MOD-PD`, `MOD-VIEWER` 는 이 SRS에서 이름만 선언한 것이며, Module Map은 별도 명세로 작성될 예정이다. Master §4 "미할당 SRS-F 없음" 검증은 Module Map 작성 시점에 정식 통과한다.
