---
spec_type: SRS (Software Requirements Specification)
scope: 회차 생성·검수 + rewrite 루프 줄기 + AI 독자 댓글 줄기 (사람 UI·가상결제·좋아요는 범위 밖)
status: 검증 대기
updated_at: 2026-05-28
references:
  - meta-specs/Product-Requirements-Meta-Spec-Info.md §SRS
  - docs/Domain-Model.md
  - docs/Data-Model.md
  - docs/Flow-Chapter-Lifecycle.md
  - docs/Flow-AI-Reader-Comment.md
---

# SRS — 회차 생성·검수 + rewrite 루프 + AI 독자 댓글 줄기

> 이 문서는 세 줄기의 기능 요구를 명세한다.
> 1. **회차 줄기 (walking skeleton 1단계)** — 회차 1건이 generator에서 생성되어 pd 검수를 거쳐 published 되거나 다시 draft로 돌아간다.
> 2. **AI 독자 댓글 줄기 (walking skeleton 2단계)** — published 회차에 AI 독자(reader-agent)가 댓글을 단다.
> 3. **rewrite 루프 줄기 (walking skeleton 3단계)** — pd reject 시 generator 가 피드백을 받아 같은 draft 의 본문을 재작성한다. 무한 루프를 방지하기 위해 재시도 상한을 두고 도달 시 `abandoned` 로 종착한다.
>
> NFR(성능·보안·가용성)과 다른 줄기(사람 UI 좋아요/댓글, 독자 가상결제)는 본 명세 범위 밖이다.

> **PRD-US 매핑 안내**: SRS-F-001~004 / SRS-F-007 / SRS-F-008 은 PRD-US-01/02 (작가·PD)에 매핑된다. SRS-F-005~006은 PRD-US-03 (독자) 중 **댓글 부분**에만 매핑된다 — 가상결제·좋아요는 향후 SRS, 미작성.

---

## 1. 범위

**대상 — 회차 줄기 + rewrite 루프**: `StorySpec → generator의 다음 회차 생성 → in_review 전환 → pd 검수 → 상태 전환` 의 흐름. reject 시 `in_review → draft` 복귀 후 generator 가 같은 draft 의 본문을 재작성(rewrite), `revision_count` 가 MAX 도달이면 `in_review → abandoned` 종착. 관련 엔티티는 [Domain-Model.md](Domain-Model.md) (§4.1 상태기계·§4.10 재시도 상한), 스키마는 [Data-Model.md](Data-Model.md), 시퀀스는 [Flow-Chapter-Lifecycle.md](Flow-Chapter-Lifecycle.md) 참조.

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

### SRS-F-001 — 작가의 다음 회차 생성 (FRESH 모드)

**설명**: generator는 활성 StorySpec의 `frequency`에 따라 정해진 주기에 깨어나, 같은 Novel 내 **active draft 가 없을 때**(= rewrite 대상이 없을 때) 해당 Novel의 WriterContext와 직전까지의 Chapter들을 읽어 LLM(WORLD §LLM 호출 규칙)을 호출해 다음 Chapter의 draft 본문을 생성하고 저장한다. 이후 LLM 출력에서 추출 가능한 새 일화/떡밥 정보를 WriterContext에 갱신한다. active draft 가 있는 경우의 동작은 SRS-F-007 (REWRITE 모드) 참조.

**maps_to_prd**: `PRD-US-01`

**owner_module**: `MOD-GENERATOR`

**acceptance**:
- Given:
  - `StorySpec.active=true` 인 Novel이 존재하고, 해당 Novel의 직전 Chapter.number = N (Novel이 새로 생성된 직후라면 N=0)이다.
  - **active draft 없음**: 같은 Novel 내 `status ∈ {draft, in_review}` 인 Chapter가 존재하지 않는다 (Domain §4.3). 정의상 "active draft 없음" ⇔ `status NOT IN ('draft','in_review')`. `published`/`abandoned` 회차는 active 가 아니므로 다음 fresh 생성을 막지 않는다 (`abandoned` 직후 N+1 진행 시 회차 번호 갭 가능 — Domain §4.10).
- When: generator가 `frequency` cron에 의해 깨어나거나 수동 trigger를 받는다.
- Then:
  1. `public.chapters`에 `(novel_id, number=N+1, status='draft', content=…, title=…, revision_count=0)` row가 생긴다.
  2. `generator.draft_runs`에 해당 chapter_id, 모델/토큰/시간 메타 row가 생긴다.
  3. `generator.writer_contexts`의 `episodes` 또는 `foreshadows`가 LLM 출력 기반으로 갱신될 수 있다 (갱신은 동일 트랜잭션 내, `version`을 증가시킴 — Domain §4.4).
  4. 동일 Novel에 대한 다른 generator 호출과 충돌하지 않는다 (선행 acquire 또는 부분 유니크 인덱스가 거부).
- 실패 케이스: LLM 호출 실패 시 chapter row를 만들지 않거나 별도 표시한다 (정책 `[확인 필요]`). draft_runs는 실패 메타만 남길 수 있다.

---

### SRS-F-002 — 완성 판정 후 in_review 전환

**설명**: generator는 자신이 생성하거나 재작성한 `status='draft'` Chapter에 대해 Domain Model §4.5의 완성 판정 기준을 적용해 통과 시 `draft → in_review` 상태 전이를 수행한다. **본 동작은 fresh 모드(SRS-F-001) 와 rewrite 모드(SRS-F-007) 양쪽에 동일하게 적용된다** — 판정 기준은 `revision_count` 값과 무관하다.

**maps_to_prd**: `PRD-US-01`

**owner_module**: `MOD-GENERATOR`

**acceptance**:
- 완성 판정 항목:
  - (a) 최소 글자 수 충족: `[확인 필요]` — 구체 수치는 사람이 채운다.
  - (b) 회차 단위 서사 완결성 자체 점검 통과: 도입–전개–훅 등 항목. 구체 체크리스트는 `[확인 필요]`.
  - (c) WriterContext의 `foreshadows`(paid_off 상태)·`episodes`(기 사실)와 본문 간 모순 없음.
- **§SRS-F-003 와의 관계**: 본 (a)(b)(c) 는 generator 가 `draft → in_review` 전이 자격을 스스로 판단하기 위한 self-check 다. pd 검수(§SRS-F-003)는 같은 차원 — 최소 길이((a) = §F-003 (G2)), 회차 완결성((b) = §F-003 `item_score_completeness`), 일관성·premise((c) ⊂ §F-003 (G1)·(G3)) — 을 독립 rubric 으로 다시 평가한다. **§F-003 (G1) 이 reject 강제로 격상됨에 따라, 본 (c) self-check 는 generator 가 submit 전에 모순을 차단하는 1차 방어선의 의미가 강해진다 — (c) 가 통과한 채로 (G1) 이 트리거되면 같은 spec 위에서 rewrite 해도 회수 가능성이 낮으므로 pd 가 곧장 reject 한다 (SRS-F-003 (B) G1 참조).** 최소 글자 수만 같은 `[확인 필요]` 값을 가리키며(값 중복 박기 금지), 그 외 체크리스트(본 (b) generator self-check vs §F-003 (G4) pd 게이트)는 적용 주체·목적이 다르므로 각자의 `[확인 필요]` 를 가진다.
- Given: SRS-F-001(fresh) 또는 SRS-F-007(rewrite) 로 본문이 채워진 `status='draft'` Chapter가 존재하고, 위 (a)(b)(c)를 모두 통과한다.
- When: generator가 submit-for-review 동작을 수행한다.
- Then:
  1. 해당 Chapter.status가 `draft → in_review`로 전이된다 (`revision_count` 는 변경되지 않음).
  2. `updated_at`이 갱신된다 (pd 폴링의 정렬 기준).
  3. Domain §4.1의 상태기계가 허용하지 않는 전이(예: 이미 `in_review`인 행에 대한 재전이, `draft`가 아닌 행에 대한 호출, 종착 상태에서의 진출)는 거부된다.

---

### SRS-F-003 — pd의 in_review 폴링 및 검수

**설명**: pd는 주기적으로 (주기 `[확인 필요]`) `public.chapters`에서 `status='in_review'`인 행을 `updated_at` 오래된 순으로 조회해, 각 Chapter에 대해 LLM 기반 검수를 수행하고 `pd.reviews`에 결과를 기록한다.

**maps_to_prd**: `PRD-US-02`

**owner_module**: `MOD-PD`

**acceptance**:

#### (A) 검수 기준 (rubric)

- 항목 4개와 가중치 (합 = 100): `재미·몰입 35 / 문장 품질 20 / 캐릭터·세계관 일관성 20 / 회차 완결성 25`.
- 점수 앵커 (각 항목 0–100 점수 산정 시 LLM 이 동일하게 적용). **"발행 가치" 의 의미를 좁힌다 — 80 이상 approve 영역은 장르 상위 30% 급. 무난한 글은 60~79 needs_revision 영역에 떨어져야 정상**:
  - **90~100**: 장르 최상위. 거의 결함 없고 강한 훅. 매우 드물게 줌.
  - **80~89**: 장르 상위 30% 급. 명확한 강점 + 약점 1~2개 이내. approve 가능 영역.
  - **70~79**: 평균보다 조금 나음. 강점 있지만 약점도 분명. needs_revision 기본값.
  - **60~69**: 평범. 명백한 약점 있음. needs_revision 권장.
  - **40~59**: 약점 분명. reject.
  - **0~39**: 명백한 결함. reject.
- 총점 산출: `quality_score = round(0.35·item_score_fun + 0.20·item_score_prose + 0.20·item_score_consistency + 0.25·item_score_completeness)`. 0–100 범위.
- decision 임계 (점수 기반): `quality_score >= 80` → `approve` / `60 <= quality_score < 80` → `needs_revision` / `quality_score < 60` → `reject`. 임계 수치 자체는 변경 없으나 **앵커 격상으로 의미가 격상됨 — `>=80 approve` 는 "장르 상위 30% 급" 을 뜻하며, 무난한 글은 60~79 영역에 떨어진다**. **단 (B) 거부 게이트가 우선**.

#### (B) 거부 게이트 (점수 무관, 트리거 시 `decision` 강제)

다음 중 하나라도 트리거되면 `quality_score` 와 무관하게 `decision` 이 강제된다. 트리거된 사유는 LLM 응답의 `blockers` 배열에 문자열로 1개 이상 남는다. **G1 은 reject 강제 (모순은 rewrite 로 보완 불가), G2~G4 는 needs_revision 강제 (rewrite 로 보완 가능 영역).**

- **(G1) — 트리거 시 `decision='reject'` 강제**: 캐릭터/세계관/설정이 직전 회차 또는 `StorySpec.character_list / StorySpec.premise` 와 모순. 인물·사건·설정 어느 하나라도 어긋나면 트리거. **격상 사유**: 모순은 같은 spec 위에서 rewrite 해도 동일 모순이 재발할 가능성이 높음 — 보완 가능한 약점이 아니라 spec 차원의 결함. rewrite 루프(SRS-F-007) 의 의도와도 정합.
- **(G2) — 트리거 시 `decision='needs_revision'` 강제**: 본문이 최소 길이 미달 — 기준값은 **SRS-F-002 acceptance (a) 의 `[확인 필요]` 와 동일** (재참조; 본 §F-003 에는 값을 박지 않는다). rewrite 로 길이 보완 가능.
- **(G3) — 트리거 시 `decision='needs_revision'` 강제**: 스토리 premise(`StorySpec.premise`) 와 어긋남.
- **(G4) — 트리거 시 `decision='needs_revision'` 강제**: 그 외 "치명적 결함" — 작가가 의도하지 않은 명백한 오류 (예: 인물 이름이 본문 안에서 뒤바뀜, 시점 혼동, 문장 단위 붕괴 등). 구체 체크리스트는 `[확인 필요]`. **(G4) 는 pd 의 제3자 시각 게이트이며, SRS-F-002 (b) 의 generator self-check 기준과는 적용 주체·목적이 다르므로 같은 값을 가리키지 않는다.**

#### (C) LLM 응답 스키마 (pd 가 LLM 에게 강제하는 출력 형식)

> **개정 근거**: 이전 개정은 LLM 에게 `quality_score` 와 `decision` 까지 요구하고 코드가 검증·재산출하는 이중 구조였다. 실측 결과 LLM 이 항목별 점수는 일관되게 변별하면서도 가중합 산술과 거부 게이트 규칙 적용에는 일관적 실패를 보였다. 본 개정은 LLM 응답 책임을 "변별과 사유 (항목 점수 + blockers + feedback)" 로 좁히고, 산술·규칙 적용은 코드 단독 산출로 단일화한다.

- `item_score_fun`: 0–100. 재미·몰입.
- `item_score_prose`: 0–100. 문장 품질.
- `item_score_consistency`: 0–100. 캐릭터·세계관 일관성.
- `item_score_completeness`: 0–100. 회차 완결성 (도입–전개–훅 — SRS-F-002 (b) 의 self-check 와 동일 차원을 pd 가 독립 평가).
- `blockers`: `string[]`. 트리거된 거부 게이트 사유 (없으면 빈 배열).
- `feedback`: 자유 텍스트. reject/needs_revision 시 generator 가 다음 rewrite 입력으로 사용.

`quality_score` 와 `decision` 은 LLM 응답에 포함되지 않는다 — 코드가 항목별 점수와 `blockers` 로부터 (A)·(B) 를 적용해 산출한다 (E 절 Then-2·Then-5 참조).

#### (D) `pd.reviews` 영속 필드 — 본 개정에서 무변경

본 SRS 범위에서 `pd.reviews` row 에 영속되는 컬럼은 기존대로 `(chapter_id, pd_version, decision, quality_score, feedback, created_at)` 다 (Data Model §1 변경 없음). **항목별 점수·`blockers` 영속화는 `[확인 필요 — Data Model §pd.reviews 컬럼 추가, 사후 분석용]`.**

**한계 (후속 빚으로 인식)**: (A)·(B) 산출은 본 개정에서 코드 단독 책임이 됐으므로 "식이 제대로 적용됐는지" 의문은 명세 수준에서 해소됐다. 다만 **입력값인 항목별 점수(`item_score_fun / prose / consistency / completeness`) 와 `blockers` 가 DB 에 영속되지 않으므로**, `pd.reviews` row 에 저장된 `quality_score` 가 어떤 항목 조합에서 나왔는지, 어떤 거부 게이트가 트리거돼 `decision` 이 `'reject'` (G1) 또는 `'needs_revision'` (G2~G4) 으로 강제됐는지 사후에 추적할 수 없다. 자유 텍스트 `feedback` 안에 사유가 들어 있을 거라는 약한 가정에 의존한다. 항목별 점수·`blockers` 컬럼이 추가될 때까지 본 한계는 그대로 남는다.

#### (E) Given / When / Then

- **Given**: `public.chapters` 에 `status='in_review'` 인 row 가 1개 이상 존재한다.
- **When**: pd 의 폴링 cycle 이 실행된다.
- **Then**:
  1. 각 in_review Chapter 에 대해 pd 는 (C) 의 LLM 응답 스키마에 맞춰 LLM(WORLD §LLM 호출 규칙) 을 호출한다.
  2. **LLM 응답에는 `quality_score` 가 없다.** pd 는 LLM 응답의 항목별 점수(`item_score_*`) 로부터 (A) 의 가중합 식을 적용해 `quality_score` 를 산출한다. 코드 단독 산출이므로 LLM 응답과의 불일치·거부 개념은 존재하지 않는다.
  3. pd 는 (2) 의 `quality_score` 와 후술 Then-5 의 `decision` 산출 결과를, LLM 응답에서 추출한 `feedback` 과 함께 `pd.reviews(chapter_id, pd_version, decision, quality_score, feedback, created_at)` row 1건으로 영속한다.
  4. `decision` 은 `approve | reject | needs_revision` 중 하나이며 `quality_score` 는 0–100 (Data §1).
  5. **LLM 응답에는 `decision` 이 없다.** pd 는 LLM 응답의 `blockers` 와 (2) 의 `quality_score` 로부터 다음 규칙으로 `decision` 을 산출한다 — **(B) 게이트의 G1/G2~G4 분리에 맞춰 우선순위 적용**:
     - (i) `blockers` 중 G1 사유(캐릭터/세계관/설정 모순)가 1개 이상이면 → `reject` (점수 무관).
     - (ii) (i) 에 해당하지 않고 `blockers` 가 비어 있지 않으면 (= G2/G3/G4 중 하나 이상 트리거) → `needs_revision` (점수 무관).
     - (iii) `blockers` 가 비어 있으면 → (A) 점수 임계 (`quality_score >= 80 → approve / 60 <= quality_score < 80 → needs_revision / quality_score < 60 → reject`) 적용.

     **G1 사유 식별**: `blockers` 배열의 문자열에서 G1 트리거 여부를 코드가 판별 가능해야 한다. 본 SRS 에서는 식별 방식 자체는 `[확인 필요 — 구현 시 LLM 응답 스키마 보조 필드(예: blocker_codes) 추가 또는 prompt 측 prefix 약속]`. LLM 이 자유 텍스트로만 사유를 적으면 G1/G2~G4 분기가 불가능하므로 본 SRS 개정 이후 코드 PR 에서 같이 해결한다.
  6. 동일 Chapter 에 대한 동시 검수는 직렬화된다 — 동일 in_review row 를 두 pd 인스턴스가 동시에 잡지 못한다 (구현: `FOR UPDATE SKIP LOCKED` 또는 어드바이저리 락, `[확인 필요]`).
- **실패 케이스**: LLM 호출 실패 또는 응답이 (C) 스키마를 만족하지 못함 — 어느 경우든 review row 를 생성하지 않는다. Chapter 는 `in_review` 로 잔류해 다음 cycle 에서 다시 pick up 된다.

---

### SRS-F-004 — 검수 결과에 따른 상태 전환

**설명**: pd는 방금 기록한 `pd.reviews.decision`을 보고 Chapter.status를 다음과 같이 전이시킨다.
- `approve` → Chapter.status를 `in_review → published`로 **직접** 전이하고 `published_at`을 기록한다. (이전 명세의 `approved` 중간 단계는 본 개정에서 제거 — Domain §4.1, 1c 구현 정합화.)
- `reject` 또는 `needs_revision` → Chapter.`revision_count` 를 1 증가시키고, Review.feedback을 `generator.writer_contexts.feedback_log`에 누적한 뒤, 증가한 `revision_count` 가 MAX(§Domain 4.10) **미만이면** Chapter.status를 `in_review → draft`로 되돌리고, **이상이면** Chapter.status를 `in_review → abandoned`로 종착시키고 `abandoned_at` 을 기록한다 (SRS-F-008 참조). 어느 분기든 동일 트랜잭션 (Domain §4.6).

**maps_to_prd**: `PRD-US-02`

**owner_module**: `MOD-PD`

**acceptance**:
- Given: Chapter.status='in_review' + 방금 INSERT 된 pd.reviews row 1건 + 적용 전 Chapter.`revision_count` = R.
- When: pd가 검수 결과에 따른 상태 전이를 적용한다.
- Then:
  1. Domain §4.1의 허용 전이만 발생한다 (그 외 전이 시도는 거부; 종착 상태에서의 진출 시도도 거부).
  2. `approve` 의 경우 동일 트랜잭션 내에서 `in_review → published` 직접 전이가 완료되고 `published_at`이 채워진다. `revision_count` 는 변경되지 않는다.
  3. `reject` / `needs_revision` 의 경우 같은 트랜잭션 안에서 다음이 모두 일어난다:
     - Chapter.`revision_count` 가 R+1 로 갱신되고,
     - `generator.writer_contexts.feedback_log`에 `{chapter_number, decision, feedback, at, review_id, revision_attempt=R+1}` 엔트리가 append 되며 `version`이 증가하고,
     - R+1 < MAX 이면 Chapter.status가 `draft`로 변경되며,
     - R+1 >= MAX 이면 Chapter.status가 `abandoned`로 종착되고 `abandoned_at` 이 기록된다 (SRS-F-008).
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

### SRS-F-007 — 작가의 draft 재작성 (REWRITE 모드)

**설명**: generator 가 깨어났을 때 같은 Novel 에 `status='draft'` 인 active draft 가 이미 존재하면, fresh 생성(SRS-F-001) 대신 그 draft 의 본문을 재작성한다. 입력은 ① 기존 `chapters.content`, ② 같은 `chapter_number` 의 `generator.writer_contexts.feedback_log` 엔트리들, ③ WriterContext (big/detailed plan, episodes, foreshadows), ④ WriterIdentity 파일이다. LLM(WORLD §LLM 호출 규칙) 출력 = 개선된 본문. 본 동작은 `revision_count = 0` (= 아직 reject 받지 않은 미완성 fresh draft) 인 경우에도 동일하게 적용된다 — 그때 feedback_log 부분이 비어 있을 뿐. rewrite 자체는 Chapter.status 를 변경하지 않는다 (`draft` 유지). 이후 §SRS-F-002 완성 판정으로 `in_review` 전이.

**maps_to_prd**: `PRD-US-01`

**owner_module**: `MOD-GENERATOR`

**acceptance**:
- Given:
  - `StorySpec.active=true` 인 Novel 이 존재하고,
  - 같은 Novel 에 `status='draft'` 인 Chapter (= active draft) 가 1개 존재한다 (§Domain 4.3 으로 최대 1개).
  - feedback_log 에 해당 `chapter_number` 의 엔트리 0개 이상 (0개인 경우 = fresh 미완성 보완).
- When: generator 가 `frequency` cron 에 의해 깨어나거나 수동 trigger 를 받는다.
- Then:
  1. LLM 호출이 일어난다. 입력은 위 설명의 ①~④.
  2. 동일 트랜잭션 안에서 다음이 모두 일어난다:
     - `UPDATE public.chapters SET content=$new, updated_at=now() WHERE id=$draft.id` (status·revision_count·number 모두 변경 없음).
     - `INSERT generator.draft_runs (chapter_id, generator_version, llm_metadata)` — rewrite 호출 메타.
     - `episodes`/`foreshadows` 갱신은 일어날 수 있다 (Domain §4.4, `version` 증가).
     - 어느 한 작업이 실패하면 전체 롤백.
  3. 후속 §SRS-F-002 완성 판정이 통과하면 `draft → in_review` 전이.
- 실패 케이스:
  - LLM 호출 실패 시 chapter row 갱신을 하지 않는다 (기존 content 보존). draft_runs 의 실패 메타 보관 여부는 SRS-F-001 과 동일 정책 `[확인 필요]`.
  - rewrite 결과가 §SRS-F-002 완성 판정 미통과 시 Chapter 는 `draft` 로 잔류하며 다음 generator cycle 에서 다시 rewrite 시도 (이때 `revision_count` 는 변하지 않음 — pd 가 증가시키는 값이므로).

---

### SRS-F-008 — 재시도 상한 도달 시 abandoned 종착

**설명**: pd 가 SRS-F-004 의 reject/needs_revision 트랜잭션 안에서 Chapter.`revision_count` 를 증가시킨 결과가 MAX (§Domain 4.10) 이상이면 Chapter.status 를 `in_review → draft` 가 아닌 `in_review → abandoned` 로 종착시킨다. `abandoned` 는 tombstone 으로 보존되며, 다음 generator cycle 에서 해당 Novel 의 N+1 회차로 fresh 진행(SRS-F-001)이 자동으로 일어난다 — abandoned 가 active 아님이기 때문 (SRS-F-001 acceptance 의 "active draft 없음" 정의).

**maps_to_prd**: `PRD-US-02`

**owner_module**: `MOD-PD`

**acceptance**:
- MAX 값: `[확인 필요 — 기본 3 권장]` (Domain §4.10). 애플리케이션 설정으로 보유.
- Given: Chapter.status='in_review' + 방금 INSERT 된 pd.reviews(decision ∈ {reject, needs_revision}) row 1건 + 적용 전 Chapter.`revision_count` = R, 그리고 `R + 1 >= MAX`.
- When: pd 가 SRS-F-004 의 reject/needs_revision 분기를 실행한다.
- Then:
  1. SRS-F-004 의 동일 트랜잭션 안에서 다음이 모두 일어난다:
     - Chapter.`revision_count` = R+1 갱신,
     - feedback_log 누적 (`revision_attempt = R+1`),
     - Chapter.status = `abandoned`, `abandoned_at = now()` 기록.
     - 어느 한 작업이 실패하면 전체 롤백.
  2. abandoned 종착 후 Chapter 는 더 이상 active 가 아니므로 (§Domain 4.3 / §4.10), 다음 generator cycle 에서 SRS-F-001 의 "active draft 없음" 조건을 만족해 N+1 회차로 fresh 진행이 가능하다 — 회차 번호 갭이 발생할 수 있다 (§Domain 4.10).
  3. abandoned 회차의 draft_runs, pd.reviews, feedback_log 누적은 사후 분석 자료로 모두 보존된다 (DELETE 하지 않음).
- 실패 케이스: 본 SRS-F-008 은 SRS-F-004 트랜잭션의 분기이므로 별도 실패 케이스 없음 (SRS-F-004 의 실패 처리에 흡수).
- 본 줄기 범위 밖: abandoned 발생 알림, admin UI 노출, Novel 자체의 일시중지 모델 등 (Navigator 신규 빚).

---

## 3. 비기능 요구사항

본 줄기 범위 밖. 추후 SRS-N 형태로 별도 명세. (성능: 폴링 주기·생성 빈도 / 보안: 서비스 간 권한 / 가용성: 재시도·중단 복구 등)

---

## 4. 추적 매트릭스

| PRD-US | SRS-F | Owner Module | 비고 |
|---|---|---|---|
| `PRD-US-01` | SRS-F-001 | MOD-GENERATOR | 회차 fresh 생성 (active draft 없음 전제) |
| `PRD-US-01` | SRS-F-002 | MOD-GENERATOR | 완성 판정 후 in_review 전환 (fresh / rewrite 공통) |
| `PRD-US-02` | SRS-F-003 | MOD-PD | in_review 폴링·검수 |
| `PRD-US-02` | SRS-F-004 | MOD-PD | 검수 결과 상태 전이 (approve 직행 / reject·revision_count++ → draft 또는 abandoned 분기) |
| `PRD-US-03` (댓글 슬라이스) | SRS-F-005 | MOD-VIEWER | published 폴링·후보 식별 |
| `PRD-US-03` (댓글 슬라이스) | SRS-F-006 | MOD-VIEWER | reader-agent 댓글 생성 |
| `PRD-US-01` | SRS-F-007 | MOD-GENERATOR | active draft 발견 시 본문 재작성 (rewrite, walking skeleton 3단계) |
| `PRD-US-02` | SRS-F-008 | MOD-PD | revision_count >= MAX 도달 시 abandoned 종착 (walking skeleton 3단계) |

> **고지**:
> - `PRD-US-03` 은 본디 "독자 에이전트가 발행 회차에 가상결제·댓글·좋아요로 반응" 전체를 다룬다. 본 SRS의 SRS-F-005/006 은 그 중 **댓글 부분 슬라이스**만 매핑한다. 가상결제·좋아요는 향후 SRS, 미작성.
> - Module 컬럼의 `MOD-GENERATOR`, `MOD-PD`, `MOD-VIEWER` 는 이 SRS에서 이름만 선언한 것이며, Module Map은 별도 명세로 작성될 예정이다. Master §4 "미할당 SRS-F 없음" 검증은 Module Map 작성 시점에 정식 통과한다.
