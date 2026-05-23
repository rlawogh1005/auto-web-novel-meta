---
spec_type: Domain Model
scope: 회차 생성·검수 줄기 + AI 독자 댓글 줄기 (사람 UI·가상결제·좋아요는 범위 밖)
status: 검증 대기
updated_at: 2026-05-23
references:
  - meta-specs/Domain-Meta-Spec-Info.md §Domain Model
  - WORLD.md §핵심 엔티티
---

# Domain Model — 회차 생성·검수 + AI 독자 댓글 줄기

> 이 문서는 `auto-web-novel` 시스템의 도메인 중 **회차 1건이 생성되어 검수를 거치는 과정**(walking skeleton 1단계)과 **발행된 회차에 AI 독자가 댓글을 다는 과정**(walking skeleton 2단계)에 등장하는 개념·규칙만을 다룬다.
> 사람 UI(좋아요·댓글), 독자 가상결제, admin UI 등은 별도 명세에서 다룬다.

이 명세는 Master §4 참조 그래프상 **Data Model의 근거**다. 엔티티 이름은 Glossary가 작성되기 전까지 본 문서가 단일 진실 원천이며, Data Model은 여기에서 정의된 이름을 그대로 따른다.

---

## 1. 핵심 엔티티

식별자(고유 ID)를 가지고 생명주기 동안 동일성을 유지하는 개념.

### Novel

소설 1편을 표현하는 최상위 엔티티.

| 속성 | 설명 |
|---|---|
| `id` | UUID. 불변. |
| `title` | 제목. |
| `genre` | 장르(fantasy, romance, mystery, …). |
| `premise` | 한두 문단 분량의 전제. |
| `created_by_spec` | 이 Novel을 만들어낸 `StorySpec`의 ID. |
| `status` | `drafting` \| `published` \| `archived`. |

**생명주기**: admin이 StorySpec을 활성화하면 generator가 `Novel(status=drafting)`을 만들고, 적어도 1개 회차가 `published` 되면 `published`로 승격(이 줄기 외 정책). 본 줄기에서는 주로 `drafting`.

### Chapter

소설 내 한 회차. 본 명세의 중심 엔티티.

| 속성 | 설명 |
|---|---|
| `id` | UUID. 불변. |
| `novel_id` | 소속 Novel. 불변. |
| `number` | 회차 번호(1, 2, 3, …). 같은 Novel 내 유일. |
| `title` | 회차 제목. |
| `content` | 본문(마크다운). |
| `status` | `draft` \| `in_review` \| `approved` \| `published` \| `rejected`. |

**생명주기**: 도메인 규칙 §4.1 상태기계를 따른다.

### StorySpec

admin(사람)이 소설을 어떻게 만들지 정의한 생성 기준. 본 명세에서는 **읽기 전용 입력**으로만 등장한다 (StorySpec 자체의 작성·수정은 admin 줄기 범위).

| 속성 | 설명 |
|---|---|
| `id` | UUID. |
| `genre`, `target_audience`, `tone` | 소설의 결을 정의. |
| `character_list` | 등장인물 정의(JSON). |
| `premise` | 시작 전제. |
| `length_target` | 목표 회차 수. |
| `frequency` | 생성 주기(cron 표현). |
| `active` | 활성화 여부. |

### Writer

회차를 생성하는 "작가"의 정체성을 가진 엔티티. 한 Writer는 여러 Novel을 이력으로 가질 수 있으나, 본 줄기에서는 동시에 `status='drafting'`인 Novel을 최대 1개만 진행한다 (§4.7).

| 속성 | 설명 |
|---|---|
| `id` | 작가 식별자 슬러그 (예: `writer-alpha`). 불변. 정체성 파일 디렉토리 이름과 일치한다. |
| `identity_ref` | 정체성 파일 디렉토리 경로 참조 (예: `writers/writer-alpha/`). DB에는 경로만, 본문은 파일. |
| `active` | 현재 활동 중 여부. 비활성 작가에게는 새 Novel을 배정하지 않는다. |
| `created_at` | 작가가 시스템에 등록된 시각 (UTC). |

**생명주기**: 사람이 generator repo의 `writers/{id}/` 디렉토리에 정체성 파일(SOUL.md, Literary-Style.md)을 만들고 시스템에 등록한다. WriterIdentity의 본문은 파일이 단일 진실이며 거의 변하지 않는다 (§2 값 객체 — AgentIdentity / WriterIdentity 참조).

### WriterContext

본 명세에서 새로 도입하는 엔티티. **"작가"는 별도의 프로세스가 아니라 generator가 Novel별로 유지하는 누적 상태**이며, 그 누적 상태를 표현한 것이 WriterContext다.

Novel 1개당 정확히 1개의 WriterContext가 존재하며, generator가 회차를 생성할 때마다 갱신된다.

| 속성 | 설명 |
|---|---|
| `novel_id` | Novel과 1:1. PK 겸 FK. |
| `big_story_outline` | "큰 스토리 설계". 전체 서사 아치(시작·중반·결말의 윤곽). 텍스트. |
| `detailed_story_plan` | "세부 스토리 설계". 가까운 수개~수십 회차 분량의 구체 진행 계획. 구조화 데이터(JSON). |
| `episodes` | "일화". 지금까지 일어난 사건의 회차별 요약 목록(아래 값 객체 Episode 참조). |
| `foreshadows` | "떡밥". 심어둔 떡밥과 회수 상태 추적 목록(값 객체 Foreshadow 참조). |
| `chapter_bodies` | 이미 쓴 회차 본문 인덱스(전체 본문은 Chapter.content에 있고, 여기서는 빠른 회수용 인덱스/요약). |
| `feedback_log` | pd의 reject/needs_revision 피드백 누적. 다음 생성 시 LLM 입력에 포함. |
| `version` | 갱신 일련번호(낙관적 잠금/디버깅용). |

**생명주기**: Novel 생성 시 함께 만들어지고, Novel과 함께 폐기된다. 외부에서 Novel을 거치지 않고 직접 조회·수정할 수 없다(§3 집합체 참조).

> **정체성(파일) ↔ 누적 상태(DB) 구분**
> - **WriterIdentity** = "작가가 누구인가" (SOUL · 문체 · 영감). 거의 불변. **파일**(§2 값 객체).
> - **WriterContext** = "이 Novel에서 지금까지 무엇을 알고/계획했는가" (큰·세부 설계, 일화, 떡밥, 피드백). 회차마다 갱신. **DB**.
> - 두 가지는 다른 것이며, generator는 회차 생성 시 둘 모두를 LLM 입력에 포함한다 (정체성 = 고정 페르소나, 컨텍스트 = 누적 상태).

### Review

pd가 한 차례 검수를 수행한 결과 1건.

| 속성 | 설명 |
|---|---|
| `id` | UUID. |
| `chapter_id` | 대상 Chapter. |
| `pd_version` | 검수를 수행한 pd 빌드 식별자. |
| `decision` | `approve` \| `reject` \| `needs_revision`. (값 객체 ReviewDecision 참조) |
| `quality_score` | 0–100. |
| `feedback` | 자유 텍스트. reject/needs_revision 시 WriterContext.feedback_log로 누적된다. |
| `created_at` | UTC. |

한 Chapter는 여러 Review를 가질 수 있다(rejected → draft → 재생성 → 다시 in_review → 재검수 흐름이 발생할 수 있으므로).

### ReaderPersona

발행된 회차를 읽고 댓글을 다는 "AI 독자"의 정체성을 가진 엔티티. Writer↔WriterIdentity 패턴과 완전 대칭. 시스템에 등록된 한 명의 독자 1:1에 대응한다.

| 속성 | 설명 |
|---|---|
| `id` | 독자 식별자 슬러그 (예: `reader-alpha`). 불변. 정체성 파일 디렉토리 이름과 일치한다. |
| `identity_ref` | 정체성 파일 디렉토리 경로 참조 (예: `readers/reader-alpha/`). DB에는 경로만, 본문은 파일. |
| `active` | 현재 활동 중 여부. 비활성 페르소나는 새 댓글 생성 대상에서 제외된다. |
| `created_at` | 페르소나가 시스템에 등록된 시각 (UTC). |

**생명주기**: 사람이 viewer repo의 `readers/{id}/` 디렉토리에 정체성 파일(SOUL.md, Reading-Style.md, Comment-Style.md)을 만들고 시스템에 등록한다. ReaderIdentity의 본문은 파일이 단일 진실이며 거의 변하지 않는다 (§2 값 객체 — AgentIdentity / ReaderIdentity 참조).

### Comment

발행된 Chapter 1건에 대한 한 ReaderPersona의 댓글 1건. AI 독자 댓글 줄기의 중심 엔티티.

| 속성 | 설명 |
|---|---|
| `id` | UUID. 불변. |
| `chapter_id` | 대상 Chapter. 항상 `Chapter.status='published'` 인 회차여야 한다 (§4.8). |
| `author_persona_id` | 작성자 ReaderPersona. nullable — WORLD.md `Comment.persona_id NULL = 사람 댓글` 정의를 보존하기 위해 nullable이지만 본 줄기(AI 독자 댓글)에서는 항상 채워진다. 사람 UI는 3단계+ 범위 밖. |
| `content` | 댓글 본문 (텍스트). |
| `created_at` | UTC. |

> **WORLD.md `Comment.persona_id` 와의 정합**: 본 명세는 컬럼명을 `author_persona_id` 로 더 분명히 했으나 의미는 동일하다 — `ReaderPersona` FK, NULL = 사람 댓글. 본 줄기 INSERT는 항상 NOT NULL로 채운다.

**생명주기**: viewer가 SRS-F-005·006의 폴링 cycle에서 published 회차 × active 페르소나 조합 중 아직 댓글이 없는 (chapter, persona) 쌍에 대해 LLM으로 본문을 생성해 INSERT한다. 같은 (Chapter, ReaderPersona) 쌍에 대해 최대 1건만 존재한다 (§4.9).

---

## 2. 값 객체 (Value Objects)

식별자 없이 속성 묶음만으로 동등성이 결정되는 개념. WriterContext 내부에서 주로 등장한다.

### Foreshadow (떡밥)

```
{
  label: 짧은 식별 문구 (예: "주인공의 출생 비밀"),
  planted_in_chapter: int,                  -- 떡밥이 처음 등장한 회차
  expected_payoff_around_chapter: int|null, -- 회수 예정 회차(없으면 미정)
  status: open | paid_off,                  -- 회수 여부
  notes: text                               -- 보조 설명
}
```

### Episode (일화)

```
{
  chapter_number: int,
  summary: 한두 문장의 요약,
  key_events: string[]                      -- 사건 키워드 (이름 등장, 갈등, 반전 등)
}
```

### ReviewDecision

```
{
  verdict: approve | reject | needs_revision,
  quality_score: 0..100,
  feedback: text
}
```

### AgentIdentity

모든 에이전트(작가/독자)가 공유하는 정체성 베이스. 식별자 없이 속성 묶음으로 표현되며, 본 시스템에서는 **파일로 관리되는 읽기 전용 입력**이다 (DB 아님).

```
{
  SOUL:         text,        -- 성격 / 세계관 / 가치관
  inspirations: string[]     -- 영감의 원천. MVP에서는 "책 이름" 목록만
                             -- (LLM이 이미 가진 지식을 활성화; 본문/저작권 자료 불포함)
}
```

- **저장 위치**: 파일. DB에는 본문을 두지 않는다.
- **향후 확장**: `inspirations`를 RAG(검색 기반 보강)로 확장할 여지가 있으나 본 명세에서는 책 이름 텍스트 목록만 명세한다.

### WriterIdentity

`AgentIdentity`를 확장해 작가의 문체·기법을 더한 값.

```
{
  ...AgentIdentity,          -- SOUL + inspirations
  literary_style: text       -- 문체 · 서술 기법 (시점, 호흡, 비유 성향 등)
}
```

- **저장 위치**: generator repo의 `writers/{writer-id}/` 디렉토리.
  - `SOUL.md` — AgentIdentity 부분 (성격·세계관·가치관·영감 책 이름)
  - `Literary-Style.md` — 문체·기법
- **본 명세 범위**: "그런 파일이 존재하고 이런 역할을 한다"는 개념·관계만 정의한다. 실제 내용·템플릿은 generator repo 작업.
- Writer 엔티티(§1)는 자신의 WriterIdentity 디렉토리를 `identity_ref`로 참조한다.

### ReaderIdentity

`AgentIdentity`를 확장해 독자의 읽기 취향·댓글 스타일을 더한 값. AI 독자(reader-agent)가 사용할 정체성이다.

```
{
  ...AgentIdentity,         -- SOUL + inspirations
  reading_style: text,      -- 무엇에 반응하는지 (서스펜스 선호, 캐릭터 중심, 클리셰 민감 등)
  comment_style: text       -- 댓글 어조·길이 (냉소적/감성적, 한 줄/문단형 등)
}
```

- **저장 위치**: viewer repo의 `readers/{reader-id}/` 디렉토리.
  - `SOUL.md` — AgentIdentity 부분 (성격·세계관·가치관·영감 책 이름)
  - `Reading-Style.md` — 읽기 취향 / 어떤 요소에 반응하는지
  - `Comment-Style.md` — 댓글 어조·길이
- **본 명세 범위**: "그런 파일이 존재하고 이런 역할을 한다"는 개념·관계만 정의한다. 실제 내용·템플릿은 viewer repo 작업.
- ReaderPersona 엔티티(§1)는 자신의 ReaderIdentity 디렉토리를 `identity_ref`로 참조한다.

> **WORLD.md `ReaderPersona` 와의 정합**: WORLD.md는 `reading_style: JSON`, `comment_style: JSON` 을 단일 ReaderPersona 묶음으로 정의한다. 본 명세는 Writer↔WriterIdentity 패턴을 그대로 적용해 `ReaderPersona`(엔티티, DB) ↔ `ReaderIdentity`(값 객체, 파일) 로 분리하고, 본문을 파일로 옮겼다. WORLD.md 자체는 수정하지 않는다 — docs/가 본 줄기 범위에서 더 정밀한 모델을 가진다는 위계는 회차 줄기(Writer 분리)에서 이미 확립된 방식과 동일.

---

## 3. 집합체 (Aggregates)

일관성 경계로 묶이는 엔티티 그룹과 그 루트(Aggregate Root). 외부에서는 루트를 통해서만 내부에 접근한다.

### Aggregate "Novel"
- **루트**: `Novel`
- **포함**: `Novel + WriterContext(1:1) + Chapter[*]` 및 WriterContext 내부의 값 객체들(Foreshadow/Episode/feedback_log).
- **외부 참조**: Novel은 자신을 쓰는 Writer를 1개 참조(`writer_id`)한다. Writer는 별도 집합체이며 Novel 집합체에 포함되지 않는다 — WriterIdentity의 본문이 파일에 있고 DB가 소유하지 않기 때문이다.
- **불변식**: §4의 모든 도메인 규칙은 이 집합체 안에서 보장된다. Writer↔Novel 카디널리티는 §4.7에서 별도로 강제한다.
- **소유 서비스**: `generator`. 모든 쓰기는 generator를 통과해야 한다 (Chapter.status 전환만 예외 — pd가 직접 수행, §4.1 참조).

### Aggregate "Review"
- **루트**: `Review`
- **포함**: 단일 Review.
- **소유 서비스**: `pd`.
- Review는 Chapter를 참조(`chapter_id`)하지만 Chapter 집합체에 포함되지 않는다. pd는 Novel 집합체 내부 상태(WriterContext 등)를 변경하지 않고, 오직 Chapter.status와 (rejected 시) feedback_log 누적에만 영향을 준다.

### Aggregate "Comment"
- **루트**: `Comment`
- **포함**: 단일 Comment.
- **소유 서비스**: `viewer`.
- **외부 참조**: Chapter 1개(`chapter_id`)와 ReaderPersona 1개(`author_persona_id`)를 참조하지만 어느 쪽 집합체에도 포함되지 않는다. viewer는 Novel 집합체 내부 상태(Chapter.content 등)를 변경하지 않고 오직 자기 스키마(comments / comment_runs / reader_personas)와 `public.chapters` 읽기만 한다.

### Aggregate "ReaderPersona"
- **루트**: `ReaderPersona`
- **포함**: 단일 ReaderPersona.
- **외부 참조**: ReaderIdentity 디렉토리 경로(`identity_ref`) 1개.
- ReaderPersona는 Writer와 같은 이유로 별도 집합체 루트다 — ReaderIdentity 본문이 파일(viewer repo)에 있어 DB가 소유하지 않기 때문이다.

---

## 4. 도메인 규칙 / 불변식

항상 참이어야 하는 비즈니스 규칙. 위반은 거부된다.

### 4.1 Chapter 상태기계 (이 명세의 중심)

```
        ┌──────────────────────────────────────────────────┐
        │                                                  │
        ▼                                                  │
     [draft] ──── generator 완성 판정 ────▶ [in_review]    │
        ▲                                       │          │
        │                                       │          │
        │            pd: reject                 │          │
        │       │ pd: needs_revision            │          │
        │       ▼                               │          │
        │  feedback 누적 후 draft로 복귀         │          │
        └───────────────────────────────────────┘          │
                                                           │
                            pd: approve                    │
                                │                          │
                                ▼                          │
                          [approved] ──자동──▶ [published]──┘ (종착)
```

**전이 규칙**:
- 허용 전이: `draft → in_review`, `in_review → approved`, `approved → published`, `in_review → draft`.
- `approved`와 `published`는 본 줄기의 종착 상태다. 다시 `draft`로 돌아가지 않는다.
- 위 외의 전이는 거부된다 (예: `draft → approved` 직접 전이, `published → rejected` 등).
- `rejected`는 상태 enum에 존재하지만 본 줄기에서는 사용하지 않는다 (rejected 결정은 Chapter.status를 `draft`로 되돌리고 Review.decision에만 기록). Data Model에서는 enum에 유지하되 본 줄기에서는 미사용으로 표시한다.

**전이를 수행하는 주체**:
- `draft → in_review`: generator (SRS-F-002).
- `in_review → approved → published`: pd (SRS-F-004).
- `in_review → draft`: pd (SRS-F-004).

### 4.2 회차 번호 단조 증가
같은 `novel_id` 내 `Chapter.number`는 1부터 빈틈없이 단조 증가한다. 새 회차는 항상 `max(number) + 1`로 만든다.

### 4.3 한 번에 한 회차
같은 `novel_id` 내 `status ∈ {draft, in_review}`인 Chapter는 동시에 최대 1개 존재한다. 이전 회차가 `approved/published`로 종착하거나 다시 `draft`로 돌아온 뒤라야 다음 회차 생성이 가능하다.

### 4.4 WriterContext 동시성
하나의 Novel에 대한 WriterContext 갱신은 직렬화돼야 한다. generator의 다음 회차 생성과 pd의 reject 피드백 누적이 동시에 발생할 경우, 잃어버린 갱신(lost update)을 방지하기 위해 `version` 컬럼을 이용한 낙관적 잠금 또는 행 잠금을 사용한다 (구현 정책은 Data Model §제약·인덱스 + 추후 ADR에서 결정).

### 4.5 작가 완성 판정 기준
generator가 Chapter를 `draft → in_review`로 보낼 자격이 있다고 판단하려면 다음을 모두 만족해야 한다.

1. **최소 글자 수 충족**: `[확인 필요]` — 사람이 채울 구체 수치.
2. **회차 단위 서사 완결성 자체 점검 통과**: 도입–전개–훅 구조가 존재하는지, 본문 끝이 다음 회차로 이어지는 훅인지 등 자체 체크리스트. 구체 항목은 `[확인 필요]`.
3. **WriterContext의 떡밥/일화와 모순 없음**: 본문이 `foreshadows`의 `paid_off` 상태나 `episodes`의 기 사실과 충돌하지 않는다.

세 조건 모두 통과해야 §4.1의 `draft → in_review` 전이가 허용된다.

### 4.6 피드백 누적
Review.decision이 `reject` 또는 `needs_revision`일 때, 해당 Review.feedback은 WriterContext.feedback_log에 누적된다. 이 누적은 Chapter.status를 `in_review → draft`로 되돌리는 동일 트랜잭션 내에서 일어난다(부분 적용 금지).

### 4.7 Writer ↔ Novel 카디널리티 / 동시 active 1개

- Writer ↔ Novel = **1:N**. 한 Writer는 여러 Novel을 이력으로 가질 수 있다.
- 본 줄기 범위에서 **"active(회차 생성 진행 중)"의 판정은 `Novel.status='drafting'`** 단일 기준으로 한다.
- **한 Writer가 동시에 `status='drafting'`인 Novel은 최대 1개**. 종착(`published` 또는 `archived`)에 이른 뒤에야 같은 Writer에게 다음 Novel을 배정할 수 있다.
- 이 불변식은 Data Model의 부분 유니크 인덱스(`novels_one_active_per_writer`)로 강제된다.
- `published` 이후에도 추가 회차가 생성되는 웹소설형 연재 구조는 Novel 상태기계 별도 명세 영역이며 본 줄기 범위 밖이다 (Navigator.md "기술 빚" 참조).

### 4.8 댓글 대상 제약 (published 회차에만)

Comment는 `Chapter.status='published'` 인 회차에만 달릴 수 있다. 다른 상태(`draft`, `in_review`, `approved`)의 Chapter에 대한 Comment INSERT는 거부된다. 강제 위치는 Data Model의 트리거 또는 애플리케이션 레이어 (`[확인 필요]`).

이 불변식은 1단계 줄기의 종착 상태(`published`)가 2단계 줄기의 입력이 됨을 보장한다.

### 4.9 1 ReaderPersona × 1 Chapter = 1 Comment

같은 `(chapter_id, author_persona_id)` 쌍에 대해 Comment는 최대 1건 존재한다. walking skeleton 2단계의 단순화 가정 — 한 독자가 한 회차에 여러 번 의견을 남기거나 스레드를 다는 것은 본 명세 범위 밖이다. Data Model의 `UNIQUE (chapter_id, author_persona_id)` 가 강제한다.

미래에 동일 페르소나의 다회차 댓글·스레드 모델이 필요해지면 별도 명세에서 본 §4.9를 갱신한다.

---

## 5. 도메인 이벤트

도메인에서 의미 있는 사건. 본 명세에서는 **개념적으로만** 정의하며, Phase 1에서는 별도 이벤트 버스(메시지 큐 등)를 도입하지 않는다 — 상태 컬럼의 변경이 곧 이벤트 발생을 의미한다.

| 이벤트 | 발생 조건 | 발화 주체 |
|---|---|---|
| `ChapterDrafted` | 새 Chapter row가 `status=draft`로 삽입됨 | generator |
| `ChapterSubmittedForReview` | Chapter.status가 `draft → in_review` 전이 | generator |
| `ChapterApproved` | Chapter.status가 `in_review → approved` 전이 | pd |
| `ChapterPublished` | Chapter.status가 `approved → published` 전이 | pd (자동 전이) |
| `ChapterRejected` | Chapter.status가 `in_review → draft` 전이 + feedback 누적 | pd |
| `CommentPosted` | 새 Comment row가 `viewer.comments`에 INSERT됨 | viewer |

Phase 2에서 Redis Streams 등을 도입하면 이 이벤트들이 publish 대상이 된다(WORLD.md §서비스 간 통신).
