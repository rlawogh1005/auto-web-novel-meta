---
spec_type: Data Model / Schema
scope: 회차 생성·검수 + rewrite 루프 줄기 + AI 독자 댓글 줄기 + 작가-PD 1:1 페어링 골격 (사람 UI·가상결제·좋아요는 범위 밖)
status: 검증 대기
updated_at: 2026-05-28
references:
  - meta-specs/Architecture-Design-Meta-Spec-Info.md §Data Model
  - WORLD.md §핵심 엔티티, §공통 규칙
  - docs/Domain-Model.md
---

# Data Model — 회차 생성·검수 + rewrite 루프 + AI 독자 댓글 + 작가-PD 페어링 줄기

> 이 문서는 [docs/Domain-Model.md](Domain-Model.md) 의 엔티티를 PostgreSQL 스키마로 구현한 결과를 명세한다.
> 엔티티명은 Domain Model과 1:1로 대응한다(같은 이름은 같은 개념).
> WORLD.md의 엔티티 스키마·시간(UTC)·스키마 분리 규칙을 준수한다.

---

## 1. 엔티티 목록 (테이블)

각 테이블의 속성·타입·키. 스키마는 §4 스키마 분리 절을 따른다.

### `public.novels`
| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `title` | text | NOT NULL | |
| `genre` | text | NOT NULL | |
| `premise` | text | NOT NULL | |
| `created_by_spec` | UUID | FK → `public.story_specs(id)` | |
| `writer_id` | text | NOT NULL, FK → `generator.writers(id)` ON DELETE RESTRICT | 이 Novel을 쓰는 작가. cross-schema FK 허용(Novel의 본질적 속성). |
| `assigned_pd_id` | text | NOT NULL, FK → `pd.pd_agents(id)` ON DELETE RESTRICT | 이 Novel 을 검수하는 PD. `writer_id` 와 동일 정당화 (cross-schema FK, Novel 의 본질적 속성). Novel 활성화 시점에 배정되어 종착까지 불변 (Domain §4.11). |
| `status` | text | NOT NULL, CHECK ∈ {drafting, published, archived} | |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |
| `updated_at` | timestamptz | NOT NULL, default now() | UTC |

### `public.chapters`
| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `novel_id` | UUID | FK → `public.novels(id)` ON DELETE CASCADE | |
| `number` | int | NOT NULL, CHECK > 0 | Novel 내 회차 번호. `abandoned` 종착 시 번호 갭 발생 가능 (Domain §4.10) |
| `title` | text | NOT NULL | |
| `content` | text | NOT NULL | 마크다운 본문. rewrite 시 갱신(SRS-F-007) |
| `status` | `chapter_status` (enum) | NOT NULL | §2 ENUM 참조 |
| `revision_count` | int | NOT NULL, default 0, CHECK >= 0 | reject/needs_revision 시 +1 (SRS-F-004). MAX 도달이면 `abandoned` 종착 (Domain §4.10) |
| `created_at` | timestamptz | NOT NULL | UTC |
| `updated_at` | timestamptz | NOT NULL | 상태 전이 시 자동 갱신(트리거) |
| `published_at` | timestamptz | NULL | `published` 전이 시점에 기록 |
| `abandoned_at` | timestamptz | NULL | `abandoned` 전이 시점에 기록 (`published_at` 패턴 대칭) |

### `public.story_specs`
| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `genre` | text | NOT NULL | |
| `target_audience` | text | NOT NULL | |
| `tone` | text | NOT NULL | |
| `character_list` | jsonb | NOT NULL | |
| `premise` | text | NOT NULL | |
| `length_target` | int | NOT NULL | 목표 장 수 |
| `frequency` | text | NOT NULL | cron 표현 |
| `active` | boolean | NOT NULL, default false | |
| `created_by` | UUID | NOT NULL | admin user id |
| `created_at` | timestamptz | NOT NULL | UTC |

### `generator.writers`
회차를 생성하는 작가의 등록 정보. 정체성 본문 자체는 DB가 아닌 파일(generator repo)에 있고, 본 테이블은 *어느 작가가 존재하고 어디서 정체성을 읽어와야 하는가*만 추적한다.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | text | PK | 작가 슬러그 (예: `writer-alpha`). 파일 디렉토리 이름과 일치. 불변. |
| `identity_path` | text | NOT NULL | generator repo 내 정체성 디렉토리 경로 (예: `writers/writer-alpha/`). 본문(SOUL.md, Literary-Style.md)은 파일. |
| `active` | boolean | NOT NULL, default true | 비활성 시 새 Novel 배정 불가 |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |

> **정체성 본문은 DB가 아니다.** SOUL.md / Literary-Style.md의 실제 텍스트는 generator repo의 파일(읽기 전용). DB는 참조 경로와 활성 여부만 가진다. 상세 정책은 §6 참조.

### `generator.writer_contexts`
Novel 1:1. 작가의 누적 상태(큰/세부 스토리 설계, 일화, 떡밥, 피드백 로그).

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `novel_id` | UUID | PK, FK → `public.novels(id)` ON DELETE CASCADE | 1:1 |
| `big_story_outline` | text | NOT NULL, default '' | 큰 스토리 설계 |
| `detailed_story_plan` | jsonb | NOT NULL, default '{}'::jsonb | 세부 스토리 설계 |
| `chapter_bodies_index` | jsonb | NOT NULL, default '[]'::jsonb | 회차 본문 인덱스/요약 |
| `feedback_log` | jsonb | NOT NULL, default '[]'::jsonb | pd reject/needs_revision 누적. 값 형식: `[{chapter_number, decision, feedback, at, review_id, revision_attempt}]`. `review_id` 는 `pd.reviews(id)` FK 참조(추적성). `revision_attempt` 는 그 시점의 Chapter.`revision_count`(디버깅·LLM 입력 정렬). generator rewrite(SRS-F-007) 시 chapter_number 필터로 해당 회차 누적분을 LLM 입력에 포함 — 보관 윈도우 정책 `[확인 필요 — 구현 시작은 전체 누적. MAX=3 이면 한 회차당 최대 3건이라 양이 적음. 회차당 분량이 커지거나 컨텍스트 한계에 부딪히면 "최근 N건" 윈도우로 재검토]` |
| `version` | int | NOT NULL, default 0 | 낙관적 잠금용 |
| `updated_at` | timestamptz | NOT NULL | UTC |

### `generator.episodes`
WriterContext의 "일화" 값 객체를 행 단위로 풀어 저장.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `novel_id` | UUID | FK → `public.novels(id)` ON DELETE CASCADE | |
| `chapter_number` | int | | Chapter.number와 의미적으로 연결 |
| `summary` | text | NOT NULL | |
| `key_events` | jsonb | NOT NULL, default '[]'::jsonb | string[] |
| PK | `(novel_id, chapter_number)` | | |

### `generator.foreshadows`
WriterContext의 "떡밥" 값 객체.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `novel_id` | UUID | FK → `public.novels(id)` ON DELETE CASCADE | |
| `label` | text | NOT NULL | |
| `planted_in_chapter` | int | NOT NULL | |
| `expected_payoff_around_chapter` | int | NULL | |
| `status` | text | NOT NULL, CHECK ∈ {open, paid_off} | |
| `notes` | text | NOT NULL, default '' | |

### `generator.draft_runs`
generator의 LLM 호출 1회분 메타데이터. WORLD.md의 `Draft` 개념을 generator 스키마로 분리해 보관.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `chapter_id` | UUID | FK → `public.chapters(id)` ON DELETE CASCADE | 실패 호출의 경우 NULL 허용? → 본 명세에서는 NOT NULL. 실패 시 chapter row를 만들지 않고 `draft_runs`도 만들지 않거나, 실패 전용 별도 컬럼으로 표시한다 (구체 정책은 `[확인 필요]`) |
| `generator_version` | text | NOT NULL | |
| `llm_metadata` | jsonb | NOT NULL | 모델/토큰/소요시간/seed 등 |
| `created_at` | timestamptz | NOT NULL | UTC |

### `pd.pd_agents`
PD 의 등록 정보. `public.novels.assigned_pd_id` 의 FK 대상. **`generator.writers` 와 달리 정체성 파일이 없다** — 본 줄기에서 PD 는 공통 rubric (SRS-F-003 (A)) 으로 동작하므로 인스턴스별 변별이 없다. 명부는 식별자와 활성 여부만 보유한다 (Domain §1 PdAgent, §4.11).

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | text | PK | PD 슬러그 (예: `pd-alpha`). 불변. |
| `active` | boolean | NOT NULL, default true | 비활성 시 새 Novel 배정 불가. |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |

> **정체성 본문 컬럼(`identity_path`) 부재**. 본 줄기에서 PD 는 공통 rubric 이므로 `generator.writers` / `viewer.reader_personas` 와 달리 정체성 디렉토리 참조가 없다. 향후 PD 별 정체성(SOUL · 검수 관점) 이 필요해지면 그때 `identity_path` 컬럼을 추가한다 (Navigator 빚). 본 명세에서 명부의 변별은 **`id` 슬러그만으로 충분** — pd 인스턴스가 자신을 `$self_pd_id` 로만 인지하고 폴링한다 (SRS-F-003 (E)).

### `pd.reviews`
pd의 검수 결과 1건.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `chapter_id` | UUID | FK → `public.chapters(id)` ON DELETE CASCADE | |
| `pd_version` | text | NOT NULL | |
| `decision` | `review_decision` (enum) | NOT NULL | §2 ENUM 참조 |
| `quality_score` | int | NOT NULL, CHECK 0..100 | |
| `feedback` | text | NOT NULL, default '' | |
| `created_at` | timestamptz | NOT NULL | UTC |

> **`pd_id` 컬럼 부재 — 본 줄기에서 의도된 선택**. Review row 에 어느 PdAgent 가 검수했는지 영속하지 않는다. Novel ↔ PdAgent 페어링(§4.11)이 불변이므로 `Review.chapter_id → Chapter.novel_id → Novel.assigned_pd_id` 경유로 사후 추적이 가능하다. **Novel 도중 PD 재배정이 도입되면 이 경유 추적이 무너지므로** `pd_id` 컬럼 추가가 필요해진다 (Navigator 빚).

### `viewer.reader_personas`
AI 독자(reader-agent)의 등록 정보. 정체성 본문은 DB가 아닌 파일(viewer repo)에 있고, 본 테이블은 *어느 페르소나가 존재하고 어디서 정체성을 읽어와야 하는가*만 추적한다. `generator.writers`와 완전 대칭.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | text | PK | 페르소나 슬러그 (예: `reader-alpha`). 파일 디렉토리 이름과 일치. 불변. |
| `identity_path` | text | NOT NULL | viewer repo 내 정체성 디렉토리 경로 (예: `readers/reader-alpha/`). 본문(SOUL.md, Reading-Style.md, Comment-Style.md)은 파일. |
| `active` | boolean | NOT NULL, default true | 비활성 시 새 댓글 생성 대상에서 제외 |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |

> **정체성 본문은 DB가 아니다.** SOUL.md / Reading-Style.md / Comment-Style.md의 실제 텍스트는 viewer repo의 파일(읽기 전용). DB는 참조 경로와 활성 여부만 가진다. 상세 정책은 §6 참조.

### `viewer.comments`
한 ReaderPersona가 한 published Chapter에 단 댓글 1건.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `chapter_id` | UUID | NOT NULL, FK → `public.chapters(id)` ON DELETE CASCADE | published만 허용 — 강제 위치는 트리거 또는 애플리케이션 (`[확인 필요]`, Domain §4.8) |
| `author_persona_id` | text | NULL, FK → `viewer.reader_personas(id)` ON DELETE RESTRICT | 사람 댓글(NULL) 호환 위해 nullable. 본 줄기(AI 독자 댓글) INSERT는 항상 NOT NULL로 채움 — WORLD.md `Comment.persona_id` 정의 보존 |
| `content` | text | NOT NULL | 댓글 본문 |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |

**유니크 제약**:
```sql
CREATE UNIQUE INDEX comments_one_per_persona_per_chapter
  ON viewer.comments (chapter_id, author_persona_id)
  WHERE author_persona_id IS NOT NULL;
```
Domain Model §4.9 강제. `WHERE author_persona_id IS NOT NULL` 부분 인덱스이므로 사람 댓글(NULL)에는 제약이 걸리지 않는다 — 본 줄기 범위에서 충분.

### `viewer.comment_runs`
viewer의 LLM 호출 1회분 메타데이터. `generator.draft_runs` / `pd.reviews` 패턴과 동일.

| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `comment_id` | UUID | FK → `viewer.comments(id)` ON DELETE CASCADE | 실패 호출의 경우 NULL 허용 여부 `[확인 필요]`. 본 명세 기본은 NOT NULL — 실패 시 comment row를 만들지 않고 comment_runs도 만들지 않거나, 실패 전용 별도 컬럼/테이블로 표시. |
| `persona_id` | text | NOT NULL, FK → `viewer.reader_personas(id)` | |
| `viewer_version` | text | NOT NULL | |
| `llm_metadata` | jsonb | NOT NULL | 모델/토큰/소요시간/seed 등 |
| `created_at` | timestamptz | NOT NULL | UTC |

---

## 2. ENUM 정의

- `chapter_status` = `('draft', 'in_review', 'published', 'abandoned', 'rejected')`
  - `abandoned` (신규) — 재시도 상한 도달 종착 (Domain §4.10). pd 가 reject/needs_revision 트랜잭션 안에서 `revision_count` 가 MAX 이상이면 이 값으로 전이.
  - `rejected` — enum 에 남기되 본 줄기에서는 사용하지 않는다 (Domain §4.1 참조). 회차 거절은 `pd.reviews.decision='reject'` 에 기록되고 Chapter.status 는 `draft` 또는 `abandoned` 로 전이된다. enum 값 제거는 후속 빚 (Navigator 기록).
  - 이전 명세에 있던 `approved` 값은 본 개정에서 enum 에서 **제거**된다 (Domain §4.1, 1c 구현 정합화). 마이그레이션 절차는 §7 참조 — `[확인 필요]`.
- `review_decision` = `('approve', 'reject', 'needs_revision')`
  - 본 줄기에서 `reject` 와 `needs_revision` 의 Chapter 상태 영향은 동일하다 (둘 다 §4.6 / §4.10 분기 적용). 두 값을 분리해 두는 이유는 pd 판정 의도 보존·분석·통계 목적이며, generator 의 rewrite 동작(SRS-F-007)도 두 값을 구분하지 않는다.

---

## 3. 관계 / 카디널리티

```
story_specs (1) ─────────────▶ (N) novels
writers     (1) ─────────────▶ (N) novels           (작가 1명이 여러 작품; 단 status='drafting'은 동시 1개 — §4.1)
pd_agents   (1) ─────────────▶ (N) novels           (PD 1명이 여러 작품 이력; 단 status='drafting'은 동시 1개 — §4.1)
novels (1) ──────────────────▶ (N) chapters
novels (1) ──────────────────▶ (1) writer_contexts
novels (1) ──────────────────▶ (N) episodes
novels (1) ──────────────────▶ (N) foreshadows
chapters (1) ────────────────▶ (N) draft_runs
chapters (1) ────────────────▶ (N) reviews          (재검수 가능하므로 1:N)
chapters (1) ────────────────▶ (N) comments        (published 회차에 ReaderPersona가 댓글; 1 persona × 1 chapter = 1 — §4.1)
reader_personas (1) ─────────▶ (N) comments
comments (1) ────────────────▶ (1) comment_runs    (LLM 호출 메타 1:1)
```

- 모든 자식 테이블은 부모 Novel 또는 Chapter의 삭제 시 CASCADE.
- `episodes.chapter_number`는 `chapters.number`와 의미적으로 연결되지만 별도 FK 컬럼을 두지 않는다 (chapters의 PK가 `id`이고 `number`는 보조키이므로 복합 FK로만 표현 가능; 본 명세에서는 애플리케이션 수준 일관성으로 충분).

---

## 4. 제약 / 인덱스

### 4.1 일관성 제약

- **회차 번호 유일**: `UNIQUE (novel_id, number) ON public.chapters` — Domain Model §4.2.
- **한 번에 한 회차**: 부분 유니크 인덱스로 Domain Model §4.3을 강제.
  ```sql
  CREATE UNIQUE INDEX chapters_one_active_per_novel
    ON public.chapters (novel_id)
    WHERE status IN ('draft', 'in_review');
  ```
  `abandoned` 와 `published` 는 active 가 아니므로 다음 회차 fresh 생성을 막지 않는다 (Domain §4.10). 회차 번호는 `UNIQUE (novel_id, number)` 로 유일하지만 abandoned 종착으로 인한 **번호 갭은 허용**된다.
- **한 작가는 동시에 active 소설 1개**: 부분 유니크 인덱스로 Domain Model §4.7을 강제. active 기준은 `Novel.status='drafting'`.
  ```sql
  CREATE UNIQUE INDEX novels_one_active_per_writer
    ON public.novels (writer_id)
    WHERE status = 'drafting';
  ```
- **한 PD 는 동시에 active 소설 1개** (Domain §4.11 — 1:1 페어링 골격): 부분 유니크 인덱스로 강제. active 기준은 `novels_one_active_per_writer` 와 동일하게 `Novel.status='drafting'` (Domain §4.7 정의 재사용).
  ```sql
  CREATE UNIQUE INDEX novels_one_active_per_pd
    ON public.novels (assigned_pd_id)
    WHERE status = 'drafting';
  ```
- **상태 전이 제약**: enum 차원의 값 제한은 enum이 보장. 허용 전이 그래프(§Domain 4.1)는 애플리케이션 레이어에서 검증(트리거로도 강제 가능 — `[확인 필요]`). 종착 상태(`published`, `abandoned`)에서의 진출 전이는 모두 거부된다.
- **재시도 상한 (`revision_count` ↔ `status` 정합)**: `revision_count` 증가와 `in_review → draft` / `in_review → abandoned` 전이는 동일 트랜잭션에서 일어나야 한다 (Domain §4.6 / §4.10). MAX 값 자체는 DB CHECK 가 아닌 애플리케이션 설정으로 보유 (`[확인 필요 — 기본 3 권장]`).
- **댓글 대상 published 제약** (Domain §4.8): `viewer.comments` INSERT 시 `public.chapters.status='published'` 인지 검증. 트리거(예: `BEFORE INSERT ON viewer.comments`) 또는 애플리케이션 레이어 (`[확인 필요]` — 트리거 비용 vs 보장 강도).
- **1 ReaderPersona × 1 Chapter = 1 Comment** (Domain §4.9): 위 §1 `comments_one_per_persona_per_chapter` 부분 유니크 인덱스가 NOT NULL 케이스에서 강제. 사람 댓글(NULL)은 제외.

### 4.2 폴링/조회 최적화 인덱스

- **pd 폴링**: `INDEX (status, updated_at) ON public.chapters` — pd가 `WHERE status='in_review' ORDER BY updated_at` 쿼리를 효율적으로 수행하기 위함 (SRS-F-003). 본 줄기 SRS-F-009 (1:1 페어링) 으로 pd 폴링이 자기 담당 novel 의 in_review 만 본다 (`chapters` c JOIN `novels` n WHERE `n.assigned_pd_id = $self`). 1:1 페어링이라 한 PD 당 in_review 가 보통 0~1 개이므로 기존 `(status, updated_at)` 인덱스로 충분. JOIN 효율을 위한 추가 인덱스 (예: `(assigned_pd_id, status)` ON `public.novels`) 도입 여부는 `[확인 필요 — 코드 PR 측정 후 결정]`.
- **viewer 폴링**: `INDEX (status, published_at) ON public.chapters` — viewer가 `WHERE status='published'` 회차를 효율적으로 조회하기 위함 (SRS-F-005). 신규 published를 시간순으로 훑거나 `published_at > $cursor` 페이지네이션에 사용.
- **comments 검색**: `INDEX (chapter_id, created_at) ON viewer.comments` — 특정 회차의 댓글 시간순 조회.
- **generator 다음 번호 조회**: `INDEX (novel_id, number) ON public.chapters` (위 UNIQUE 인덱스가 동일 효과를 가짐).

### 4.3 동시성

- **WriterContext 낙관적 잠금**: 갱신 시 `WHERE novel_id = $1 AND version = $2` 조건으로 UPDATE, 영향 행 수 0이면 재시도. Domain Model §4.4.
- **Chapter 상태 전이 동시성**: `SELECT ... FOR UPDATE`를 status 전이 직전에 사용해 동시 전이 충돌 방지 (pd 폴링이 같은 in_review row를 두 번 집어들지 않도록 — `[확인 필요]` 구현은 `FOR UPDATE SKIP LOCKED` 등으로).
- **viewer 댓글 생성 동시성**: 두 viewer 인스턴스가 동시에 같은 `(persona, chapter)` 후보를 잡았을 때 `comments_one_per_persona_per_chapter` 부분 유니크 인덱스가 두 번째 INSERT를 거부한다 (자연 직렬화). 명시적 행 락이 더 나은지는 `[확인 필요]`.

---

## 5. 스키마 분리 (WORLD.md §공통 규칙 — DB 준수)

| 스키마 | 테이블 | 쓰기 권한 |
|---|---|---|
| `public` | `novels`, `chapters`, `story_specs` | admin/generator/pd가 정해진 컬럼만 쓰기 (Chapter.status 전이는 §SRS-F의 owner_module이 관할). `novels.writer_id` 와 `novels.assigned_pd_id` 는 Novel 생성 시점에 배정 (1:1 페어링, Domain §4.7 / §4.11). viewer는 `public.chapters` **읽기 전용** (SRS-F-005). |
| `generator` | `writers`, `writer_contexts`, `episodes`, `foreshadows`, `draft_runs` | generator 전용 쓰기. 단 `writers`는 admin이 시드/활성 토글하고 generator는 읽기 전용. |
| `pd` | `reviews`, `pd_agents` | `pd.reviews` 는 pd 전용 쓰기. `pd.pd_agents` 는 admin 이 시드/활성 토글하고 pd 는 읽기 전용 (`generator.writers` / `viewer.reader_personas` 와 동일 패턴). |
| `viewer` | `reader_personas`, `comments`, `comment_runs` | viewer 전용 쓰기. 단 `reader_personas`는 admin이 시드/활성 토글하고 viewer는 읽기 전용 (`writers`와 동일 패턴). |

읽기는 어느 서비스에서도 가능. 다른 서비스 스키마에 쓰기를 시도하면 안 된다 (Phase 1 정책).

viewer는 SQLAlchemy로 `public.chapters`(읽기) + `viewer.*`(쓰기)에 직접 접근한다.

특수 케이스:
- **Chapter.status 전이**: status 컬럼은 `public`에 있으나 쓰기 권한이 두 서비스에 걸쳐 있다. SRS-F-002는 generator, SRS-F-003/004는 pd가 수행한다. 권한 분리는 DB 레벨 GRANT 또는 애플리케이션 레벨 정책으로 강제 (`[확인 필요]`).
- **WriterContext.feedback_log 갱신**: pd가 reject 시 generator 스키마의 테이블을 갱신해야 하므로 §5 원칙의 예외. 구현 옵션 (둘 다 가능, 결정은 ADR로 추후):
  1. pd가 같은 트랜잭션 안에서 `generator.writer_contexts`에 직접 UPDATE.
  2. pd는 `pd.reviews`에 reject만 기록하고, generator가 다음 cycle에 자기 `reviews` 조회 후 feedback_log를 흡수.
  본 명세에서는 옵션 1 (트랜잭션 원자성) 을 기본으로 가정한다 (Domain Model §4.6 — 동일 트랜잭션 요구).

---

## 6. 정체성 저장소 (DB 아님)

에이전트 정체성(작가·독자)은 PostgreSQL이 아닌 각 서비스 repo의 **파일**로 관리된다. DB는 참조만 가진다.

### 6.1 작가 정체성 (generator repo)

- **경로 규약**:
  - `generator-repo/writers/{writer-id}/SOUL.md` — AgentIdentity 부분 (성격·세계관·가치관·영감 책 이름 목록)
  - `generator-repo/writers/{writer-id}/Literary-Style.md` — 문체·기법
- **권한**: 사람이 설계·편집. 시스템(generator/pd)은 읽기 전용.
- **DB와의 관계**: `generator.writers.identity_path`가 위 디렉토리 경로를 가리킨다. 본문이 DB에 복제되지 않으므로 파일을 단일 진실로 본다.
- **로드 시점**: generator는 회차 생성 사이클에서 `public.novels.writer_id`로 `generator.writers` row를 조회한 뒤 `identity_path`의 두 파일을 읽어 LLM 입력에 포함한다. WriterContext는 별도로 DB에서 읽는다(Domain Model §1 박스 단락 참조).
- **향후 확장**: `SOUL.md`의 `inspirations`(책 이름 목록)를 RAG로 보강할 수 있으나, 본 명세 범위에서는 책 이름 텍스트만 사용한다. RAG 인덱스가 도입되면 별도 테이블/스키마와 ADR로 명세한다.
- **본 명세 범위 밖**: SOUL.md / Literary-Style.md의 실제 내용·템플릿(generator repo 작업).

### 6.2 독자 정체성 (viewer repo)

- **경로 규약**:
  - `viewer-repo/readers/{reader-id}/SOUL.md` — AgentIdentity 부분 (성격·세계관·가치관·영감 책 이름 목록)
  - `viewer-repo/readers/{reader-id}/Reading-Style.md` — 무엇에 어떻게 반응하는지
  - `viewer-repo/readers/{reader-id}/Comment-Style.md` — 댓글 어조·길이
- **권한**: 사람이 설계·편집. 시스템(viewer)은 읽기 전용.
- **DB와의 관계**: `viewer.reader_personas.identity_path`가 위 디렉토리 경로를 가리킨다. 본문이 DB에 복제되지 않으므로 파일을 단일 진실로 본다.
- **로드 시점**: viewer는 댓글 생성 사이클(SRS-F-006)에서 `viewer.reader_personas` row를 조회한 뒤 `identity_path`의 파일 3개를 읽어 LLM 입력에 포함한다.
- **본 명세 범위 밖**: SOUL.md / Reading-Style.md / Comment-Style.md의 실제 내용·템플릿(viewer repo 작업).

---

## 7. 마이그레이션 정책

- **마이그레이션 도구 선택**: `[확인 필요]` — Alembic / golang-migrate / Prisma migrate 등 후보. 추후 ADR로 결정.
- **변경 분류**:
  - Additive(컬럼 추가, 새 테이블, 새 인덱스): 자동 적용 가능.
  - Destructive(컬럼 삭제, 타입 변경, enum 값 제거): 사람 승인 + ADR 필수.
- **시간**: 모든 timestamp는 UTC. 컬럼 타입은 `timestamptz` (WORLD.md §시간).
- **다운타임**: Phase 1 단일 인스턴스이므로 큰 마이그레이션은 점검 시간에 일괄. Phase 2 이후 무중단 전략 별도 명세.

### 7.1 walking skeleton 3단계 (rewrite 루프) 마이그레이션 항목

- **Additive — 자동 적용 가능**:
  - `public.chapters` 컬럼 추가: `revision_count INT NOT NULL DEFAULT 0`, `abandoned_at TIMESTAMPTZ NULL`.
  - `chapter_status` enum 값 추가: `abandoned` (`ALTER TYPE chapter_status ADD VALUE 'abandoned';`).
  - `generator.writer_contexts.feedback_log` 엔트리 형식 확장(`review_id`, `revision_attempt`). 컬럼 타입(`jsonb`) 변경 없음, 새 엔트리부터 적용. 기존 엔트리는 누락 키로 남기되 application 이 nullable 로 읽음.

- **Destructive — 사람 승인 + ADR 필수** `[확인 필요]`:
  - `chapter_status` enum 값 제거: `approved`. 절차:
    1. 사전 점검: `SELECT count(*) FROM public.chapters WHERE status='approved';` 이 0 인지 확인 (1c 구현이 이미 `in_review → published` 직행이라 0 이어야 함).
    2. enum 값 제거는 Postgres 가 직접 지원하지 않으므로 새 enum 타입 생성 → 컬럼 타입 변환 → 기존 타입 DROP 순서. 또는 enum 값을 "사용 안 함"으로만 표시하고 제거는 후속 마이그레이션으로 보류.
    3. 결정·절차는 별도 ADR 권장 (대안: `approved` 값을 코드에서만 거부하고 enum 에는 유지).
  - `chapter_status` enum 값 제거: `rejected` (본 줄기 미사용). **본 마이그레이션에서는 제거하지 않는다** — 후속 빚 (Navigator 기록).

### 7.2 walking skeleton 4단계 (작가-PD 1:1 페어링 골격) 마이그레이션 항목

> 본 항목은 명세이며 실제 SQL 파일 (`db/migrations/2026-05-pairing.sql` 또는 적절한 이름) 의 작성·적용은 **별도 코드 PR** 책임이다. 본 문서는 SQL 본문의 **구조와 절차** 만 정의한다 (§7.1 패턴 답습).

- **Additive — 자동 적용 가능 (idempotent)**:
  - `pd.pd_agents` 테이블 신규 생성 (`CREATE TABLE IF NOT EXISTS pd.pd_agents (id text PRIMARY KEY, active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now());`).
  - `public.novels.assigned_pd_id` 컬럼 추가 (`ALTER TABLE public.novels ADD COLUMN IF NOT EXISTS assigned_pd_id text;`) — 우선 nullable 로 추가, 백필 후 NOT NULL 부착.
  - FK 제약 추가 (`pg_constraint` 존재 체크 후 `ALTER TABLE public.novels ADD CONSTRAINT novels_assigned_pd_id_fkey FOREIGN KEY (assigned_pd_id) REFERENCES pd.pd_agents(id) ON DELETE RESTRICT;`. `2026-05-rewrite.sql` 의 `chapters_revision_count_check` 패턴 답습 — `DO $$ BEGIN IF NOT EXISTS ... END$$;`).
  - 부분 유니크 인덱스 `novels_one_active_per_pd` (`CREATE UNIQUE INDEX IF NOT EXISTS novels_one_active_per_pd ON public.novels (assigned_pd_id) WHERE status = 'drafting';`).

- **NOT NULL 강제 절차** (Additive 안에서 마지막 단계):
  1. **사전**: `pd.pd_agents` 에 active=true PD row 1건 이상 시드 (예: `INSERT INTO pd.pd_agents (id) VALUES ('pd-alpha') ON CONFLICT DO NOTHING;`).
  2. **백필**: 기존 `public.novels` row 가 있다면 `UPDATE public.novels SET assigned_pd_id = '<seed_pd_id>' WHERE assigned_pd_id IS NULL;` 로 채운다. 배정 알고리즘은 본 줄기 범위 밖이므로 마이그레이션 시점에는 단일 시드 PD 로 일괄 백필이 자연스럽다. 실 데이터가 비어있으면 (개발 DB 초기 상태) 본 단계 생략 가능.
  3. **NOT NULL 부착**: `ALTER TABLE public.novels ALTER COLUMN assigned_pd_id SET NOT NULL;` (재실행 안전 — 이미 NOT NULL 이면 PG 가 무시).

- **시드 순서 제약**: 본 마이그레이션 적용 후 새 Novel 을 생성하려면 `pd.pd_agents` 가 비어있지 않아야 한다. 기존 `generator.writers` 시드와 동일한 운영 절차로 admin 이 PD 명부를 먼저 시드한다. PD 명부 부족 시 운영 정책(대기열 / 알림 / 수동 배정) 은 본 줄기 범위 밖 (Navigator 빚).

- **Destructive — 없음**. 본 줄기는 컬럼 삭제·타입 변경·enum 값 제거 없이 Additive 만으로 완료된다.
