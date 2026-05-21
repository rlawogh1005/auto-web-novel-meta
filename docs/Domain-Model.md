---
spec_type: Domain Model
scope: 회차 생성 → 검수 줄기 (다른 줄기 범위 밖)
status: 검증 대기
updated_at: 2026-05-21
references:
  - meta-specs/Domain-Meta-Spec-Info.md §Domain Model
  - WORLD.md §핵심 엔티티
---

# Domain Model — 회차 생성·검수 줄기

> 이 문서는 `auto-web-novel` 시스템의 도메인 중 **회차 1건이 생성되어 검수를 거치는 과정**에 등장하는 개념·규칙만을 다룬다.
> 사용자 댓글, viewer, admin UI 등은 별도 명세에서 다룬다.

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

---

## 3. 집합체 (Aggregates)

일관성 경계로 묶이는 엔티티 그룹과 그 루트(Aggregate Root). 외부에서는 루트를 통해서만 내부에 접근한다.

### Aggregate "Novel"
- **루트**: `Novel`
- **포함**: `Novel + WriterContext(1:1) + Chapter[*]` 및 WriterContext 내부의 값 객체들(Foreshadow/Episode/feedback_log).
- **불변식**: §4의 모든 도메인 규칙은 이 집합체 안에서 보장된다.
- **소유 서비스**: `generator`. 모든 쓰기는 generator를 통과해야 한다 (Chapter.status 전환만 예외 — pd가 직접 수행, §4.1 참조).

### Aggregate "Review"
- **루트**: `Review`
- **포함**: 단일 Review.
- **소유 서비스**: `pd`.
- Review는 Chapter를 참조(`chapter_id`)하지만 Chapter 집합체에 포함되지 않는다. pd는 Novel 집합체 내부 상태(WriterContext 등)를 변경하지 않고, 오직 Chapter.status와 (rejected 시) feedback_log 누적에만 영향을 준다.

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

Phase 2에서 Redis Streams 등을 도입하면 이 이벤트들이 publish 대상이 된다(WORLD.md §서비스 간 통신).
