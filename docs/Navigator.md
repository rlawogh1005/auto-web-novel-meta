# Navigator.md — 명세 현황판 (라이브)

> 이 파일은 docs/에 작성된 실제 명세의 **인덱스이자 진행 현황판**이다.
> 에이전트는 명세를 작성/수정할 때마다 이 표를 갱신한다 (Master §3 Step 5).
> "지금 무엇이 명세돼 있고, 무엇이 빠졌는가"를 한눈에 본다.

---

## 명세 인덱스

> 작성된 명세를 여기 등록한다. 아직 비어 있다면 신규 프로젝트이거나 명세 식별 전 단계다.

| 명세 유형 | 파일 | ID 범위 | 상태 | 최종 갱신 |
|---|---|---|---|---|
| North Star | [North-Star.md](North-Star.md) | NS | 확정 | 2026-05-21 |
| PRD | [PRD.md](PRD.md) | PRD-US-01 ~ PRD-US-05 | 확정 (세부 수치 [확인 필요]) | 2026-05-23 |
| Domain Model | [Domain-Model.md](Domain-Model.md) | Novel(+`assigned_pd_id`), Chapter, StorySpec, Writer, WriterContext, Foreshadow, Episode, ReviewDecision, AgentIdentity, WriterIdentity, ReaderIdentity, ReaderPersona, Comment, **PdAgent** (신규, §4.11) | 검증 대기 | 2026-05-28 |
| Data Model | [Data-Model.md](Data-Model.md) | (Domain Model과 동일 엔티티명) + `generator.writers`, `viewer.reader_personas`, `viewer.comments`, `viewer.comment_runs`, **`pd.pd_agents`** (신규) + ENUM `chapter_status` (+ `abandoned`, − `approved`), `review_decision` + Chapter.`revision_count`/`abandoned_at` + **`novels.assigned_pd_id`** + 부분 유니크 인덱스 **`novels_one_active_per_pd`** | 검증 대기 | 2026-05-28 |
| SRS | [SRS.md](SRS.md) | SRS-F-001 ~ SRS-F-009 | 검증 대기 | 2026-05-28 |
| Sequence / Flow | [Flow-Chapter-Lifecycle.md](Flow-Chapter-Lifecycle.md) | FLOW-CHAPTER-LIFECYCLE | 검증 대기 | 2026-05-26 |
| Sequence / Flow | [Flow-AI-Reader-Comment.md](Flow-AI-Reader-Comment.md) | FLOW-AI-READER-COMMENT | 검증 대기 | 2026-05-23 |

상태 값: `식별됨` → `작성 중` → `검증 대기` → `확정`

---

## 식별 결과 (Master §3 Step 2)

> 이 프로젝트에 **필요하다고 식별된** 명세 유형과 근거. 작성 전에 여기 먼저 기록하고 승인받는다.

지금까지의 식별 범위:
- **walking skeleton 1단계** — "회차 생성 → 검수" 줄기 (2026-05-21 작성 완료).
- **walking skeleton 2단계** — "AI 독자가 published 회차를 읽고 댓글" 줄기 (2026-05-23 작성 완료). 가상결제·좋아요·사람 UI 는 3단계+ 로 보류.
- **walking skeleton 3단계** — "rewrite 루프" 줄기 (2026-05-26 작성 완료). pd reject → generator rewrite → 재검수 루프 + revision_count 상한 → `abandoned` 종착. SRS-F-007/008 신설, Domain §4.10 신설, `approved` 중간 단계 명세 제거(빚 해소). 운영자 개입 모델 / Novel 일시중지 / 회차 번호 갭 정책 / `approved`·`rejected` enum 값 제거 마이그레이션은 후속 빚.
- **walking skeleton 4단계** — "작가-PD 1:1 페어링 골격" 줄기 (2026-05-28 작성 완료). novel 마다 담당 PD 1명 배정, 각 PD 는 자기 담당의 in_review 만 검수 (전역 큐 → 담당별 큐). SRS-F-009 신설 (`PRD-US-02`), Domain §1 `PdAgent` 엔티티 + §3 `PdAgent` 집합체 + §4.11 (1:1 카디널리티 / 부분 유니크) 신설, Data `pd.pd_agents` 테이블 + `novels.assigned_pd_id` NOT NULL FK + `novels_one_active_per_pd` 인덱스 신설 + §7.2 마이그레이션 항목, SRS-F-003 (E) 폴링 Given/Then-6 갱신(`assigned_pd_id` 필터 + 교차 담당 경합 제거). **PD 정체성(SOUL) 도입 / 시너지(담당 PD 의 작가 이력 검수 입력 주입) / Novel 도중 PD 재배정 / PD 명부 부족 운영 정책 / 배정 알고리즘 ADR / 코드·DB 적용 (마이그레이션 SQL 파일 작성, pd CLI `$self_pd_id` 도입, `lock_one_in_review` 담당 필터) 은 모두 후속 빚.**

| 명세 유형 | 필요 판단 근거 (트리거) | 우선순위 | 작성 여부 |
|---|---|---|---|
| Domain Model | "작가"·"독자" 누적 컨텍스트/정체성 + Chapter 상태기계 + 댓글 카디널리티 등 도메인 규칙 다수 → 모델링 없이는 일관성 보장 불가 | 최우선 | ✅ (1·2단계) |
| Data Model | 영속 데이터(PostgreSQL)가 존재 → Master §6 트리거 자동 충족 | 최우선 | ✅ (1·2단계) |
| SRS | 구현해야 할 기능(생성·검수 사이클 + viewer 폴링·댓글 생성)이 정의됨 | 최우선 | ✅ (SRS-F-001 ~ 006) |
| Sequence / Flow | 회차 줄기(generator↔DB↔pd) 와 댓글 줄기(viewer↔DB↔FS) 모두 다단계 상호작용 | 우선 | ✅ (2개 Flow) |
| PRD / North Star | 사람 이해관계자(사용자·운영자) 존재 → 필요 | 후순위 | ✅ (2026-05-21 작성. PRD-US-03 댓글 슬라이스 ↔ SRS-F-005/006 매핑은 2026-05-23 갱신) |
| Module Map | SRS-F의 `owner_module`이 `MOD-GENERATOR`, `MOD-PD`, `MOD-VIEWER`를 인용 → 곧 필요 | 다음 작업 | ❌ |
| ADR | 마이그레이션 도구, FOR UPDATE 락 전략, pd→writer_contexts 직접 쓰기 정책, viewer 폴링 주기·실패 메타 정책 등 결정 미정 | 결정 시 | ❌ |
| API Contract | Phase 1에서 서비스 간 HTTP 호출 없음 (상태기계 + FS 로 통신) → 본 단계에서 불필요 | 보류 | ❌ |
| Glossary | 본 명세 내 엔티티명이 Domain Model에서 통제되어 우선 충분 | 보류 | ❌ |
| Constraints / NFR | 성능·보안·가용성 요구는 본 단계 범위 밖 | 별도 작업 | ❌ |

---

## 추적 무결성 체크 (Master §4)

> 마지막 검증 시점 기준. 위반이 있으면 여기 기록.

| 항목 | 상태 | 비고 |
|---|---|---|
| 고아 SRS 없음 (모든 SRS-F가 PRD 근거를 가짐) | ✅ | SRS-F-001/002/007 → PRD-US-01, SRS-F-003/004/008/009 → PRD-US-02, SRS-F-005/006 → PRD-US-03 (댓글 슬라이스) 매핑 완료. |
| 미구현 PRD 없음 (모든 PRD-US가 SRS로 이어짐) | ⚠️ 부분 | PRD-US-01/02 완전 매핑 (3단계 rewrite/abandoned + 4단계 작가-PD 페어링 포함). PRD-US-03 은 댓글 부분만 SRS-F-005/006 으로 매핑 (가상결제·좋아요는 향후). PRD-US-04 (사람 관람) / PRD-US-05 (운영자) 는 SRS 미작성. |
| 미할당 SRS-F 없음 (각 SRS-F가 1개 모듈에 할당) | ⚠️ 의도된 보류 | SRS는 `MOD-GENERATOR`, `MOD-PD`, `MOD-VIEWER` 를 owner_module로 선언했으나 Module Map은 아직 미작성. SRS-F-007/008 도 같은 모듈 이름 사용. **SRS-F-009 는 owner_module 이 `[확인 필요 — 배정 주체. admin / system]`** — 다른 항목과 달리 어느 기존 모듈에도 자연스럽게 안 붙고 배정 알고리즘 ADR 결정과 함께 결정. Module Map 작성 시 정식 통과. |
| 의존 그래프 DAG (순환 없음) | N/A | Module Map 미작성. |
| 모든 ADR이 Constraint/SRS 인용 | N/A | ADR 미작성. |
| 모든 API Contract가 구현 모듈 보유 | N/A | API Contract 없음(Phase 1). |

마지막 검증: 2026-05-28

---

## 기술 빚 / 미작성 명세 (의도된 보류)

> 본 명세 줄기에서 다루지 않지만, 차후 별도 명세 작업에서 해소해야 하는 항목.

- **Novel 연재 생명주기 명세 미작성** — 현재 `Novel.status`는 `drafting → published → archived` 단순 모델이라 *발행 후에도 연재 지속(published + 작가 active 유지)* 같은 웹소설 연재 구조를 아직 다루지 못한다. Domain Model §4.7의 "active = `Novel.status='drafting'`" 단일 기준도 이 미작성에 의존한다. **회차 줄기 완료 후 Novel 상태기계 별도 명세에서 다룬다.**
- **~~회차 "완성" 판정 기준 미정~~** — **해소 (2026-05-28)**. SRS-F-002 (a) 최소 글자 수 **4000자** (`LENGTH(content)` 단순 글자 수 기준) 확정 (목표 4500~5000자 — SRS-F-001/007 의 분량 지향 절). generator MIN_CHAPTER_LENGTH 1000→4000 코드 정렬 (generator repo PR #33). stale 했던 "MIN=1000 임시 컷오프" 상태 종료. 의미 격상: §F-003 (G2) 는 §F-002 (a) 의 self-check 우회·LLM 재생성 실패 등으로 4000자 미만이 새어 든 경우의 2차 방어선임이 SRS 본문에 명시됨 (죽은 게이트 아님). meta PR #12.
- **회차 분량 "안정화" 미정 — 모델 격상 / 프롬프트 강화 / 분할 생성 ADR 후보** — SRS-F-002 (a) 4000자 하한 + SRS-F-001/007 목표 4500~5000자 명세는 확정됐으나, 실측에서 현 모델(gpt-5-nano)이 4000 경계에서 흔들림 (예: 3526 / 3526 / 4226자 — 명세 하한을 매번 충족하지 못함). 명세 기준 확정과 모델이 매번 충족하는 안정성은 별개 문제. 보완 경로 후보: (a) 프롬프트 행동지시 강화 — 분량 + "사건 추가 허용" 을 SRS-F-007 본문이 요구하나 prompt 측 구현 미정, (b) 상위 모델 격상, (c) 분할 생성 (한 회차 = 다중 LLM 호출 누적). 코드 PR 의 ADR 후보.
- **통합 테스트가 개발용 DB를 직접 TRUNCATE** — 현재 통합 테스트가 개발용 PostgreSQL(5433)에 붙어 `TRUNCATE`를 실행해 개발 데이터가 함께 삭제됨. **테스트용 DB 분리(또는 컨테이너 격리) 필요** — Data Model 환경 절 또는 ADR 후보.
- **~~approve 전이가 in_review→published 직행~~** — **해소 (2026-05-26, walking skeleton 3단계)**. rewrite 루프 명세를 손보면서 Domain §4.1 의 `approved` 중간 단계를 제거하고 `in_review → published` 직행으로 명세 단순화. 1c 구현과 정합. `chapter_status` enum 에서 `approved` 값 자체의 제거 마이그레이션은 별도 빚으로 분리 (아래 항목).
- **pd가 `generator.writer_contexts`에 직접 쓰기 (cross-schema write)** — 식별 결과 §38에 ADR 후보로 적힌 "pd→writer_contexts 직접 쓰기 정책"이 구현되었으나 ADR 미작성. **결정 근거·대안(이벤트, generator 호출) 문서화 필요.**
- **~~viewer / reader / 경제 명세 부재~~** — **부분 해소 (2026-05-23, walking skeleton 2단계)**. AI 독자 댓글 줄기는 SRS-F-005/006 + viewer 스키마 + `FLOW-AI-READER-COMMENT` 로 명세됨. 남은 미작성: **독자 가상결제·좋아요 (walking skeleton 3단계+)**, **사람 사용자의 발행 회차 노출 UI·좋아요·댓글 (확장 1·2단계)**, **viewer 웹 API 컨트랙트** — 사람 UI 또는 외부 시스템 도입 시점에 식별.
- **viewer 폴링 주기 미정** — SRS-F-005가 `[확인 필요]` 로 표기. 실제 운영 시 cron 표현 또는 인터벌 결정 필요. ADR 또는 SRS 보완.
- **viewer 댓글 본문 길이 제한 미정** — Data Model `viewer.comments.content` 는 `text` 무제한. LLM 출력 길이 캡, 사람 표시용 최대 길이 등 정책 미정.
- **viewer LLM 호출 실패 메타 보관 정책 미정** — Data Model `viewer.comment_runs.comment_id` NULL 허용 여부, 별도 실패 로그 테이블 도입 여부. `generator.draft_runs` 와 동일한 `[확인 필요]` 항목과 연동 결정 필요.
- **Domain §4.8 (published만 댓글) 강제 위치 미정** — 트리거 vs 애플리케이션 레이어. Data Model `[확인 필요]`.
- **viewer ↔ generator/pd 동시성 race 미명세** — 회차가 `published` 가 된 직후 viewer가 즉시 폴링·댓글 생성하는 와중에 (정의되지 않은 경로로) 회차 상태가 변동할 가능성. 본 줄기 Domain §4.1 에 `published → 다른 상태` 전이가 없으므로 현재는 무관하지만, Novel 연재 생명주기 명세에서 회차 회수/수정 시나리오를 다룰 때 함께 검토.
- **검증 에이전트 미완 (4단계의 "검증" 부분)** — 현재 GitHub Actions claude 작업물이 자동 검증 없이 PR 로 들어옴. `claude-code-review.yml` 은 `claude[bot]` PR 을 스킵하므로 자동 머지 안전판이 없는 상태. **다음 작업으로 검증 에이전트 별도 도입 필요.**
- **CI 러너에 sibling meta repo 없음** — 각 repo `AGENTS.md §0 읽는 순서` 가 요구하는 `../auto-web-novel-meta/docs/...` 참조를 CI 의 claude 가 건너뜀. smoke/단일 repo 작업은 영향 없으나 meta 참조가 필요한 복잡 작업은 CI 에서 제약. **meta repo 동반 체크아웃 또는 명세 동기화 전략 필요.**
- **CI 러너에 uv / 의존성 미설치** — 각 repo `AGENTS.md` prompt 4번의 검증 (ruff/mypy/pytest) 이 "가능한 경우" 로 완화됨. 진짜 코드 변경 PR 이 들어오면 검증이 실질적으로 비어 있게 됨. **uv 설치 + 의존성 캐시 스텝 추가 필요.**
- **dispatcher Python 3.13 / 타 서비스 3.12 불일치** — 로컬 dispatcher 가 `claude-agent-sdk` 요구사항으로 3.13 사용, generator/pd/viewer 는 3.12 유지. dispatcher 가 참고·로컬 실험용으로 보존되므로 기존 빚 그대로 유지.
- **`chapter_status` enum 값 제거 마이그레이션 (`approved`, `rejected`)** — walking skeleton 3단계 빚. `approved` 는 본 명세 개정으로 미사용이 됐으나 enum 값 자체 제거(destructive)는 후속 마이그레이션으로 분리 (Data Model §7.1). `rejected` 는 1단계 시점부터 미사용이며 동일하게 후속 마이그레이션. Postgres enum drop value 가 직접 미지원이라 새 enum 타입 생성·컬럼 변환·기존 타입 DROP 절차 필요 → ADR 후보.
- **rewrite 루프 MAX 값 미정** — walking skeleton 3단계 빚. Domain §4.10 의 `MAX_REVISION_ATTEMPTS` 값 `[확인 필요 — 기본 3 권장]`. 너무 작으면 정상 검수가 abandoned 폭증, 너무 크면 비용·시간 낭비. 구현 시 결정.
- **rewrite LLM 입력의 feedback_log 보관 윈도우 미정** — walking skeleton 3단계 빚. `[확인 필요 — 구현 시작은 전체 누적. MAX=3 이면 한 회차당 최대 3건이라 양이 적음. 회차당 분량이 커지거나 컨텍스트 한계에 부딪히면 "최근 N건" 윈도우로 재검토]`. 기존 Flow §4.4 빚을 본 명세 결정 방향으로 갱신.
- **abandoned 운영자 가시성 / 알림 / Novel 일시중지 모델 미작성** — walking skeleton 3단계의 부산물 빚. SRS-F-008 은 abandoned 종착 후 generator 가 N+1 fresh 로 자동 진행한다고 정의하나, 운영자가 abandoned 발생을 인지하고 개입할 경로(알림·admin UI·Novel 자체 일시중지)는 본 줄기 범위 밖. Novel 연재 생명주기 명세와 함께 다루는 게 자연스러움.
- **회차 번호 갭 정책 미정** — walking skeleton 3단계 부산물. abandoned 종착으로 `published` 회차 목록에 번호 갭이 발생하는 것을 어떻게 표시·운영할지 (renumber? gap 표시? 사용자에게 hide?) 결정 없음. viewer / web-app / mobile-app 가 published 목록 노출을 명세할 때 함께 다룬다.
- **PD 배정 알고리즘 ADR 미정** — walking skeleton 4단계 빚. SRS-F-009 가 "Novel 활성화 시점에 active PD 1명이 배정된다" 까지만 강제하고 알고리즘(자동 round-robin / 랜덤 / 수동 admin 지정 / 시드)은 `[확인 필요]` 로 보류. 코드 PR 의 ADR 로 결정 필요.
- **PD 명부 부족 시 운영 정책 미정** — walking skeleton 4단계 빚 (YAGNI 로 명세 보류). `active PD < drafting novel 수` 케이스(예: 작가 5명·PD 3명) 의 대기열·알림·수동 배정·Novel 일시중지 모델 미정. 본 줄기에서는 NOT NULL FK 위반으로 Novel 생성이 거부되는 게 기본 동작이며, 그 이상의 운영 경로는 다음 PR.
- **PD 정체성(SOUL) 도입 보류** — walking skeleton 4단계 빚. 본 줄기는 공통 rubric (SRS-F-003 (A)) 으로 PD 가 변별 없이 동작. PD 별 검수 관점·SOUL 이 필요해지면 `pd.pd_agents.identity_path` 컬럼 추가 + `pd-repo/pds/{id}/SOUL.md` 도입 (`generator.writers` 패턴 답습). 시너지 빚과 분리된 별개 항목.
- **시너지 미작성 — 담당 PD 가 그 작가 이력을 검수 LLM 입력에 주입** — walking skeleton 4단계 빚. 본 PR (페어링 골격) 의 자연스러운 다음 단계. SRS-F-003 (B) LLM 호출 입력에 그 Novel 의 `generator.writer_contexts` (big_story_outline / detailed_story_plan / episodes / foreshadows) 또는 누적 `pd.reviews` 등을 포함할지 결정 필요. North Star 의 "여러 작가가 각자 소설 쓰고, 작가마다 전담 PD 1명이 검수하는 군단" 에서 "전담" 의 의미가 단순 1:1 매핑을 넘어 "그 작가를 이해하는 PD" 로 가는 줄기.
- **Novel 도중 PD 재배정 모델 미정** — walking skeleton 4단계 빚. 현재 페어링은 Novel 활성화 시점에 형성되어 종착(`published` / `archived`) 까지 불변. PD 이탈·교체·휴가 시나리오 미정. 재배정 도입 시 `pd.reviews` 에 `pd_id` 컬럼 추가도 같이 필요해진다 (Domain §1 PdAgent 박스 참조).
- **walking skeleton 4단계 코드·DB 적용 PR 미작성 (의도된 일시 갭)** — 본 명세 PR 머지 직후 `pd/` repo 는 여전히 전역 큐로 동작 (`lock_one_in_review` 가 담당 필터 없음). 다음 PR 에서 (a) `db/migrations/2026-*-pairing.sql` 작성 + 적용, (b) pd CLI 가 `$self_pd_id` 입력 받도록, (c) `lock_one_in_review` 가 `novels.assigned_pd_id = $self_pd_id` 필터 추가, (d) Novel 생성 경로(generator 또는 admin)가 `assigned_pd_id` 채우도록. 명세-구현 갭은 본 빚 해소 시 닫힌다.

---

## 변경 이력

- 2026-05-28: 회차 분량 명세 확정 — **SRS-F-002 (a) = 4000자** (`LENGTH(content)` 단순 글자 수 기준; 공백 포함/미포함 구분 없음). SRS-F-001/007 본문에 **목표 4500~5000자** 분량 지향 절 신설 (웹소설 1회차 표준 — 조아라 등 무료연재 신인 관행 4000~4500자 공백 미포함). SRS-F-007 (REWRITE) 본문에 "rewrite 의 의미 = 같은 분량 안에서 단어 교체가 아니라 필요시 새 사건·전개 추가" 명시 (실측 발견: rewrite 가 분량을 안 늘려 점수 정체 사례). §F-002 (a) ↔ §F-003 (G2) 간 값 중복 박기 금지 — (G2) 가 (a) 를 재참조하며, (a) 가 1차 방어선·(G2) 가 self-check 우회 시 2차 방어선이라는 의미 격상. 기술 빚 "회차 완성 판정 기준 미정" 해소. generator repo PR #33 으로 코드 MIN_CHAPTER_LENGTH 1000→4000 정렬. **본 PR 범위 밖 (별개 빚으로 분리)**: 모델이 4000 경계에서 흔들리는 분량 *안정화* (프롬프트 강화 / 모델 격상 / 분할 생성) — 명세 기준 확정과 모델이 매번 충족하는 안정성은 별개 차원. meta PR #12.
- 2026-05-28: pd 검수 명세 엄격화 — **SRS-F-003 (A)~(E) 일괄 개정**. (A) 검수 rubric 4항목 + 가중치 (재미·몰입 35 / 문장 품질 20 / 캐릭터·세계관 일관성 20 / 회차 완결성 25) + **점수 앵커 재작성** — "발행 가치" 의 의미를 좁혀 80 이상 approve 영역 = **장르 상위 30% 급**, 무난한 글은 60~79 needs_revision 영역에 떨어지도록 격상 (90~100 장르 최상위 / 80~89 장르 상위 30% / 70~79 평균보다 조금 나음 / 60~69 평범 / 40~59 reject / 0~39 명백 결함). 임계 수치 자체(80 / 60) 는 그대로지만 의미가 격상. (B) 거부 게이트 4종 신설 — **G1 (캐릭터·세계관·설정 모순) 은 reject 강제로 격상** (모순은 같은 spec 위 rewrite 로 회수 불가능 — rewrite 루프 SRS-F-007 의도와 정합), G2 (최소 길이 미달 — §F-002 (a) 재참조) / G3 (premise 어긋남) / G4 (그 외 치명적 결함 — 인물 이름 뒤바뀜·시점 혼동·문장 단위 붕괴 등 pd 의 제3자 시각 게이트) 는 needs_revision 강제. (C) **LLM 응답 스키마 6필드로 축소** — `item_score_{fun,prose,consistency,completeness}` + `blockers: string[]` + `feedback`. `quality_score` 와 `decision` 은 LLM 응답에서 제거하고 **코드 단독 산출** (실측 발견: LLM 이 항목별 점수 변별은 일관되나 가중합 산술 + 거부 게이트 규칙 적용에 일관적 실패). (E) Then-5 **3-tier decision 분기** — (i) `blockers` 에 G1 사유 → `reject` 강제 / (ii) G2~G4 사유 → `needs_revision` 강제 / (iii) `blockers` 비어 있으면 점수 임계 (≥80 approve / 60~79 needs_revision / <60 reject). (D) `pd.reviews` 영속 컬럼은 본 개정 무변경 — 항목별 점수·`blockers` 영속화는 후속 빚 (`[확인 필요 — 사후 분석용]`). **결정**: 가중치 (35/20/20/25) 유지 / 임계 수치 (80/60) 유지 / 항목 점수·blockers 영속화는 추후 / G1 식별 방식 (자유 텍스트 vs `blocker_codes` 보조 필드 vs prompt prefix 약속) 은 코드 PR 에서 결정. meta PR #9 → #10 → #11.
- 2026-05-28: walking skeleton **명세 줄기 4단계** 추가 — **작가-PD 1:1 페어링 골격**. 전역 큐 모델(pd 가 어떤 in_review 든 집어 검수) → 담당별 큐 모델(각 PD 가 자기 담당 novel 의 in_review 만 검수). Domain Model §1 `PdAgent` 엔티티 신설 (정체성 파일 없음 — 공통 rubric), §1 Novel 에 `assigned_pd_id` 속성 추가 + Aggregate "Novel" 외부 참조 갱신, §3 Aggregate "PdAgent" 신설, §4.11 Novel ↔ PdAgent 카디널리티 / 1:1 페어링 신설 (active = `Novel.status='drafting'` 단일 기준 §4.7 재사용). Data Model §1 `pd.pd_agents` 테이블 신설 (id text PK + active + created_at), `public.novels` 에 `assigned_pd_id text NOT NULL FK → pd.pd_agents(id)` 추가, §3 관계 갱신, §4.1 부분 유니크 인덱스 `novels_one_active_per_pd` 신설 (`novels_one_active_per_writer` 대칭), §4.2 폴링 인덱스 한 줄 갱신 (담당 필터), §5 스키마 분리표 `pd_agents` 행 추가, §7.2 마이그레이션 항목 신설 (Additive + NOT NULL 백필 절차). SRS 상단 박스 4번째 줄기 추가, SRS-F-003 (E) Given/Then-6 갱신 (담당 필터 + 교차 담당 경합 구조적 제거), SRS-F-009 신설 (`PRD-US-02`, owner_module `[확인 필요]`), §4 추적 매트릭스 행 추가. Navigator 인덱스·식별 결과·추적 무결성·기술 빚 5건 신규 · 변경 이력 동시 갱신. **결정**: `assigned_pd_id` NOT NULL (1:1 골격 깨지지 않음) / 배정 알고리즘 = `[확인 필요 — 코드 PR ADR]` / PD 부족 시 = NOT NULL FK 위반으로 거부 (운영 정책 YAGNI) / PD 정체성·시너지(작가 이력 주입) 는 본 줄기 범위 밖 — 다음 줄기. **본 PR 은 명세 4건만** — 코드·DB 적용 (마이그레이션 SQL 파일, pd CLI 변경) 은 다음 PR. **단계 번호 충돌 주의**: 본 변경 이력 위쪽의 "walking skeleton 4단계 (Issue 자동화)" (2026-05-26) 는 GitHub Actions 자율 루프 이관 인프라 작업이며, 본 항목의 "명세 줄기 4단계" 와 차원이 다르다 (인프라 vs 명세).
- 2026-05-26: walking skeleton 3단계 명세 추가 — **rewrite 루프 줄기**. pd reject 시 generator 가 같은 draft 본문을 재작성(rewrite)하는 메커니즘과 무한 재시도 방지(`revision_count` + `abandoned` 종착)를 명세. Domain Model §4.1 상태기계 개정(`approved` 중간 단계 제거 — 1c 구현 정합화, `abandoned` 신규 종착, rewrite 루프 명시), §4.5/§4.6 소폭 append, §4.10 신설(재시도 상한), §5 이벤트 갱신(`ChapterApproved` 제거, `ChapterRewritten`·`ChapterAbandoned` 추가). Data Model `public.chapters` 에 `revision_count`/`abandoned_at` 컬럼, `chapter_status` enum 에 `abandoned` 추가·`approved` 제거(미사용 enum 값 제거 마이그레이션은 §7.1 별도 빚), `feedback_log` 엔트리 형식 확장(`review_id`, `revision_attempt`). SRS-F-001/002/004 소폭 modify, SRS-F-007(rewrite, `MOD-GENERATOR`)·SRS-F-008(abandoned 종착, `MOD-PD`) 신설. Flow-Chapter-Lifecycle 시퀀스에 FRESH/REWRITE 분기, abandoned 분기 추가. Navigator 인덱스·식별 결과·추적 무결성·기술 빚(approve 직행 빚 해소·신규 빚 5건 추가)·변경 이력 동시 갱신. WORLD.md / meta-specs / viewer·댓글 줄기(Flow-AI-Reader-Comment, viewer 스키마, SRS-F-005/006) 무수정. 결정: `approved` 명세 제거 / abandoned 후 N+1 자동 진행(회차 번호 갭 허용) / `needs_revision` 과 `reject` Chapter 영향 동일 / revision_count=0 draft 도 rewrite 모드 동일 처리.
- 2026-05-26: walking skeleton 4단계 (Issue 자동화) 크게 진행 — **로컬 dispatcher → GitHub Actions 자율 루프 이관**. dispatcher repo 는 `claude-agent-sdk` 의 `query()` 로 Issue→작업→PR 을 로컬 walking skeleton 으로 구현해 generator/pd/viewer 3개 repo 순회까지 검증한 뒤, 참고·로컬 실험용으로 보존; **운영 자율화는 GitHub Actions 로 이관**. 3개 Python repo (generator/pd/viewer) 에 `anthropics/claude-code-action@v1` 기반 `auto-issue.yml` 배치 — `auto` 라벨 Issue 부착 시 클라우드에서 claude 가 자동으로 작업해 PR 생성. 인증은 **OAuth 토큰(구독 차감, API 키 아님)** 으로 카드 안전. `permission-mode: acceptEdits` + `allowedTools` 로 git/gh 허용, Sonnet 4.6, `max-turns: 30`. 모바일에서 Issue 만 등록하면 PC 없이 PR 까지 완전 자율 동작 검증됨. 별도로 `claude-code-review.yml` 의 자기검토는 `if` 조건으로 `claude[bot]` PR 을 스킵 — 자기검토 가치가 약하고 required check 로 머지를 막던 문제 해소.
- 2026-05-23: walking skeleton 2단계 명세 추가 — **AI 독자 댓글 줄기**. Domain Model에 ReaderPersona·Comment 엔티티, ReaderIdentity 값 객체 구체화(Writer↔WriterIdentity 패턴 대칭), Aggregate Comment/ReaderPersona, §4.8(published만 댓글)·§4.9(1 persona × 1 chapter = 1 comment), `CommentPosted` 이벤트 추가. Data Model에 `viewer` 스키마 신설 + `viewer.reader_personas`/`comments`/`comment_runs` 3개 테이블, 폴링 인덱스(`(status, published_at)`)·UNIQUE 부분 인덱스, §5 스키마 분리 표·§6.2 정체성 저장소(viewer repo) 절 추가. SRS에 SRS-F-005·006(`MOD-VIEWER`) 추가, PRD-US-03 댓글 슬라이스 매핑. Flow-AI-Reader-Comment.md (`FLOW-AI-READER-COMMENT`) 신설. PRD-US-03 라인에 SRS 매핑 단서 갱신. Navigator의 인덱스/식별 결과/추적 체크/기술 빚/변경 이력 동시 갱신. 회차 줄기(SRS-F-001~004, Domain §4.1~§4.7, Flow-Chapter-Lifecycle.md)는 손대지 않음. WORLD.md / meta-specs/ 무수정.
- 2026-05-21: walking skeleton 1c 완성 — pd가 `in_review` 회차를 OpenAI로 검수해 `published`/`draft` 전이 (SRS-F-003/004). generator(1b)→pd(1c) 절반 시뮬레이터 자동 작동 확인 (실 OpenAI smoke: "강호의 문을 열다" 회차 approve 88점 → `published`).
- 2026-05-21: 구현 진행 — walking skeleton 1a(DB)·1b(generator)·1c(pd) 모두 구현 완료. "명세 → 코드 재현" 줄기는 회차 생성·검수 한정으로 동작.
- 2026-05-21: LLM 공급자 제약 완화 — Claude 고정 → 교체 가능(기본 OpenAI), 비용 사유.
- 2026-05-21: DB walking skeleton 1a — Data-Model.md → 실제 PostgreSQL 컨테이너 구현 (`docker-compose.yml`, `db/schema.sql`, `db/README.md`). 마이그레이션 도구·GRANT 권한 분리·updated_at/published_at/status 전이 트리거는 모두 `[확인 필요]`로 유지. UUID PK 기본값(DEFAULT)도 명세 외 → 미추가. 본 변경은 docs/ 명세 자체에는 새 항목을 추가하지 않음.
- 2026-05-21: 회차 생성→검수 줄기 명세 4건 신규 작성 — Domain Model, Data Model, SRS (SRS-F-001~004), Sequence/Flow (`FLOW-CHAPTER-LIFECYCLE`). Navigator 인덱스/식별 결과/추적 체크 동시 갱신.
- 2026-05-21: 고도화된 작가 개념 확장 — Domain Model에 `Writer` 엔티티, `AgentIdentity`/`WriterIdentity` 값 객체, §4.7 Writer↔Novel 1:N + 동시 active 1개 불변식, Aggregate "Novel" 외부 참조 항목, WriterContext의 정체성↔누적상태 구분 박스 추가. Data Model에 `generator.writers` 테이블, `public.novels.writer_id`, `novels_one_active_per_writer` 부분 유니크 인덱스, §6 정체성 저장소(파일) 절 추가(기존 §6 마이그레이션은 §7로 이동). ReaderIdentity는 개념만 언급(viewer 줄기 대기). Navigator에 Novel 연재 생명주기 미작성을 기술 빚으로 기록.
