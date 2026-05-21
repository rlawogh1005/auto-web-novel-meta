---
spec_type: Data Model / Schema
scope: 회차 생성 → 검수 줄기 (다른 줄기 범위 밖)
status: 검증 대기
updated_at: 2026-05-21
references:
  - meta-specs/Architecture-Design-Meta-Spec-Info.md §Data Model
  - WORLD.md §핵심 엔티티, §공통 규칙
  - docs/Domain-Model.md
---

# Data Model — 회차 생성·검수 줄기

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
| `status` | text | NOT NULL, CHECK ∈ {drafting, published, archived} | |
| `created_at` | timestamptz | NOT NULL, default now() | UTC |
| `updated_at` | timestamptz | NOT NULL, default now() | UTC |

### `public.chapters`
| 컬럼 | 타입 | 키/제약 | 비고 |
|---|---|---|---|
| `id` | UUID | PK | |
| `novel_id` | UUID | FK → `public.novels(id)` ON DELETE CASCADE | |
| `number` | int | NOT NULL, CHECK > 0 | Novel 내 회차 번호 |
| `title` | text | NOT NULL | |
| `content` | text | NOT NULL | 마크다운 본문 |
| `status` | `chapter_status` (enum) | NOT NULL | §2 ENUM 참조 |
| `created_at` | timestamptz | NOT NULL | UTC |
| `updated_at` | timestamptz | NOT NULL | 상태 전이 시 자동 갱신(트리거) |
| `published_at` | timestamptz | NULL | `published` 전이 시점에 기록 |

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
| `feedback_log` | jsonb | NOT NULL, default '[]'::jsonb | pd reject/needs_revision 누적. 값 형식: `[{chapter_number, decision, feedback, at}]` |
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

---

## 2. ENUM 정의

- `chapter_status` = `('draft', 'in_review', 'approved', 'published', 'rejected')`
  - `rejected`는 enum에 남기되 본 줄기에서는 사용하지 않는다 (Domain Model §4.1 참조). 회차 거절은 `status='draft'` 복귀 + `pd.reviews.decision='reject'`로 표현된다.
- `review_decision` = `('approve', 'reject', 'needs_revision')`

---

## 3. 관계 / 카디널리티

```
story_specs (1) ─────────────▶ (N) novels
writers     (1) ─────────────▶ (N) novels           (작가 1명이 여러 작품; 단 status='drafting'은 동시 1개 — §4.1)
novels (1) ──────────────────▶ (N) chapters
novels (1) ──────────────────▶ (1) writer_contexts
novels (1) ──────────────────▶ (N) episodes
novels (1) ──────────────────▶ (N) foreshadows
chapters (1) ────────────────▶ (N) draft_runs
chapters (1) ────────────────▶ (N) reviews          (재검수 가능하므로 1:N)
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
- **한 작가는 동시에 active 소설 1개**: 부분 유니크 인덱스로 Domain Model §4.7을 강제. active 기준은 `Novel.status='drafting'`.
  ```sql
  CREATE UNIQUE INDEX novels_one_active_per_writer
    ON public.novels (writer_id)
    WHERE status = 'drafting';
  ```
- **상태 전이 제약**: enum 차원의 값 제한은 enum이 보장. 허용 전이 그래프(§Domain 4.1)는 애플리케이션 레이어에서 검증(트리거로도 강제 가능 — `[확인 필요]`).

### 4.2 폴링/조회 최적화 인덱스

- **pd 폴링**: `INDEX (status, updated_at) ON public.chapters` — pd가 `WHERE status='in_review' ORDER BY updated_at` 쿼리를 효율적으로 수행하기 위함 (SRS-F-003).
- **generator 다음 번호 조회**: `INDEX (novel_id, number) ON public.chapters` (위 UNIQUE 인덱스가 동일 효과를 가짐).

### 4.3 동시성

- **WriterContext 낙관적 잠금**: 갱신 시 `WHERE novel_id = $1 AND version = $2` 조건으로 UPDATE, 영향 행 수 0이면 재시도. Domain Model §4.4.
- **Chapter 상태 전이 동시성**: `SELECT ... FOR UPDATE`를 status 전이 직전에 사용해 동시 전이 충돌 방지 (pd 폴링이 같은 in_review row를 두 번 집어들지 않도록 — `[확인 필요]` 구현은 `FOR UPDATE SKIP LOCKED` 등으로).

---

## 5. 스키마 분리 (WORLD.md §공통 규칙 — DB 준수)

| 스키마 | 테이블 | 쓰기 권한 |
|---|---|---|
| `public` | `novels`, `chapters`, `story_specs` | admin/generator/pd가 정해진 컬럼만 쓰기 (Chapter.status 전이는 §SRS-F의 owner_module이 관할). `novels.writer_id`는 Novel 생성 시점에 배정. |
| `generator` | `writers`, `writer_contexts`, `episodes`, `foreshadows`, `draft_runs` | generator 전용 쓰기. 단 `writers`는 admin이 시드/활성 토글하고 generator는 읽기 전용. |
| `pd` | `reviews` | pd 전용 쓰기 |

읽기는 어느 서비스에서도 가능. 다른 서비스 스키마에 쓰기를 시도하면 안 된다 (Phase 1 정책).

특수 케이스:
- **Chapter.status 전이**: status 컬럼은 `public`에 있으나 쓰기 권한이 두 서비스에 걸쳐 있다. SRS-F-002는 generator, SRS-F-003/004는 pd가 수행한다. 권한 분리는 DB 레벨 GRANT 또는 애플리케이션 레벨 정책으로 강제 (`[확인 필요]`).
- **WriterContext.feedback_log 갱신**: pd가 reject 시 generator 스키마의 테이블을 갱신해야 하므로 §5 원칙의 예외. 구현 옵션 (둘 다 가능, 결정은 ADR로 추후):
  1. pd가 같은 트랜잭션 안에서 `generator.writer_contexts`에 직접 UPDATE.
  2. pd는 `pd.reviews`에 reject만 기록하고, generator가 다음 cycle에 자기 `reviews` 조회 후 feedback_log를 흡수.
  본 명세에서는 옵션 1 (트랜잭션 원자성) 을 기본으로 가정한다 (Domain Model §4.6 — 동일 트랜잭션 요구).

---

## 6. 정체성 저장소 (DB 아님)

작가 정체성은 PostgreSQL이 아닌 generator repo의 **파일**로 관리된다. DB는 참조만 가진다.

- **경로 규약**:
  - `generator-repo/writers/{writer-id}/SOUL.md` — AgentIdentity 부분 (성격·세계관·가치관·영감 책 이름 목록)
  - `generator-repo/writers/{writer-id}/Literary-Style.md` — 문체·기법
- **권한**: 사람이 설계·편집. 시스템(generator/pd)은 읽기 전용.
- **DB와의 관계**: `generator.writers.identity_path`가 위 디렉토리 경로를 가리킨다. 본문이 DB에 복제되지 않으므로 파일을 단일 진실로 본다.
- **로드 시점**: generator는 회차 생성 사이클에서 `public.novels.writer_id`로 `generator.writers` row를 조회한 뒤 `identity_path`의 두 파일을 읽어 LLM 입력에 포함한다. WriterContext는 별도로 DB에서 읽는다(Domain Model §1 박스 단락 참조).
- **향후 확장**: `SOUL.md`의 `inspirations`(책 이름 목록)를 RAG로 보강할 수 있으나, 본 명세 범위에서는 책 이름 텍스트만 사용한다. RAG 인덱스가 도입되면 별도 테이블/스키마와 ADR로 명세한다.
- **본 명세 범위 밖**: SOUL.md / Literary-Style.md의 실제 내용·템플릿(generator repo 작업).

---

## 7. 마이그레이션 정책

- **마이그레이션 도구 선택**: `[확인 필요]` — Alembic / golang-migrate / Prisma migrate 등 후보. 추후 ADR로 결정.
- **변경 분류**:
  - Additive(컬럼 추가, 새 테이블, 새 인덱스): 자동 적용 가능.
  - Destructive(컬럼 삭제, 타입 변경, enum 값 제거): 사람 승인 + ADR 필수.
- **시간**: 모든 timestamp는 UTC. 컬럼 타입은 `timestamptz` (WORLD.md §시간).
- **다운타임**: Phase 1 단일 인스턴스이므로 큰 마이그레이션은 점검 시간에 일괄. Phase 2 이후 무중단 전략 별도 명세.
