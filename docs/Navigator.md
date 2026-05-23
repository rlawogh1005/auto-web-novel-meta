# Navigator.md — 명세 현황판 (라이브)

> 이 파일은 docs/에 작성된 실제 명세의 **인덱스이자 진행 현황판**이다.
> 에이전트는 명세를 작성/수정할 때마다 이 표를 갱신한다 (Master §3 Step 5).
> "지금 무엇이 명세돼 있고, 무엇이 빠졌는가"를 한눈에 본다.

---

## 명세 인덱스

> 작성된 명세를 여기 등록한다. 아직 비어 있다면 신규 프로젝트이거나 명세 식별 전 단계다.

| 명세 유형 | 파일 | ID 범위 | 상태 | 최종 갱신 |
|---|---|---|---|---|
| Domain Model | [Domain-Model.md](Domain-Model.md) | Novel, Chapter, StorySpec, Writer, WriterContext, Foreshadow, Episode, ReviewDecision, AgentIdentity, WriterIdentity, ReaderIdentity(개념) | 검증 대기 | 2026-05-21 |
| Data Model | [Data-Model.md](Data-Model.md) | (Domain Model과 동일 엔티티명) + `generator.writers` + ENUM `chapter_status`, `review_decision` | 검증 대기 | 2026-05-21 |
| SRS | [SRS.md](SRS.md) | SRS-F-001 ~ SRS-F-004 | 검증 대기 | 2026-05-21 |
| Sequence / Flow | [Flow-Chapter-Lifecycle.md](Flow-Chapter-Lifecycle.md) | FLOW-CHAPTER-LIFECYCLE | 검증 대기 | 2026-05-21 |

상태 값: `식별됨` → `작성 중` → `검증 대기` → `확정`

---

## 식별 결과 (Master §3 Step 2)

> 이 프로젝트에 **필요하다고 식별된** 명세 유형과 근거. 작성 전에 여기 먼저 기록하고 승인받는다.

이번 작업의 식별 범위는 **"회차 생성 → 검수" 줄기에 한정**한다. 다른 줄기(viewer, admin UI, 사용자 댓글)에 필요한 명세는 별도 식별 작업에서 다룬다.

| 명세 유형 | 필요 판단 근거 (트리거) | 우선순위 | 작성 여부 |
|---|---|---|---|
| Domain Model | "작가" 누적 컨텍스트 + Chapter 상태기계 등 도메인 규칙 다수 → 모델링 없이는 일관성 보장 불가 | 최우선 | ✅ |
| Data Model | 영속 데이터(PostgreSQL)가 존재 → Master §6 트리거 자동 충족 | 최우선 | ✅ |
| SRS | 구현해야 할 기능(생성·검수 사이클)이 정의됨 | 최우선 | ✅ |
| Sequence / Flow | generator ↔ DB ↔ pd 다단계 상호작용이 글로 설명하기 어려움 | 우선 | ✅ |
| PRD / North Star | 사람 이해관계자(사용자·운영자) 존재 → 필요하나 본 작업에서는 사람이 작성할 영역 | 후순위 | ❌ (사람 작성 대기) |
| Module Map | SRS-F의 `owner_module`이 `MOD-GENERATOR`, `MOD-PD`를 인용 → 곧 필요 | 다음 작업 | ❌ |
| ADR | 마이그레이션 도구, FOR UPDATE 락 전략, pd→writer_contexts 직접 쓰기 정책 등 결정 미정 | 결정 시 | ❌ |
| API Contract | Phase 1에서 서비스 간 HTTP 호출 없음 (상태기계로 통신) → 본 줄기에서는 불필요 | 보류 | ❌ |
| Glossary | 본 명세 내 엔티티명이 Domain Model에서 통제되어 우선 충분 | 보류 | ❌ |
| Constraints / NFR | 성능·보안·가용성 요구는 본 줄기 범위 밖 | 별도 작업 | ❌ |

---

## 추적 무결성 체크 (Master §4)

> 마지막 검증 시점 기준. 위반이 있으면 여기 기록.

| 항목 | 상태 | 비고 |
|---|---|---|
| 고아 SRS 없음 (모든 SRS-F가 PRD 근거를 가짐) | ✅ | SRS-F-001/002 → PRD-US-01, SRS-F-003/004 → PRD-US-02 매핑 완료. |
| 미구현 PRD 없음 (모든 PRD-US가 SRS로 이어짐) | N/A | PRD 미작성. |
| 미할당 SRS-F 없음 (각 SRS-F가 1개 모듈에 할당) | ⚠️ 의도된 보류 | SRS는 `MOD-GENERATOR`, `MOD-PD`를 owner_module로 선언했으나 Module Map은 아직 미작성. Module Map 작성 시 정식 통과. |
| 의존 그래프 DAG (순환 없음) | N/A | Module Map 미작성. |
| 모든 ADR이 Constraint/SRS 인용 | N/A | ADR 미작성. |
| 모든 API Contract가 구현 모듈 보유 | N/A | API Contract 없음(Phase 1). |

마지막 검증: 2026-05-21

---

## 기술 빚 / 미작성 명세 (의도된 보류)

> 본 명세 줄기에서 다루지 않지만, 차후 별도 명세 작업에서 해소해야 하는 항목.

- **Novel 연재 생명주기 명세 미작성** — 현재 `Novel.status`는 `drafting → published → archived` 단순 모델이라 *발행 후에도 연재 지속(published + 작가 active 유지)* 같은 웹소설 연재 구조를 아직 다루지 못한다. Domain Model §4.7의 "active = `Novel.status='drafting'`" 단일 기준도 이 미작성에 의존한다. **회차 줄기 완료 후 Novel 상태기계 별도 명세에서 다룬다.**
- **회차 "완성" 판정 기준 미정** — generator 구현에서 `MIN_CHAPTER_LENGTH=1000`자를 임시 컷오프로 사용 중이나 정식 기준이 없다 (분량·서사 단위·작가 의도 중 무엇으로 판단할지 미결). 결과적으로 `generate-next`가 자주 미달해 추가 호출이 필요. **SRS-F-001 "회차 완성" 정의 보완 작업에서 다룬다.**
- **통합 테스트가 개발용 DB를 직접 TRUNCATE** — 현재 통합 테스트가 개발용 PostgreSQL(5433)에 붙어 `TRUNCATE`를 실행해 개발 데이터가 함께 삭제됨. **테스트용 DB 분리(또는 컨테이너 격리) 필요** — Data Model 환경 절 또는 ADR 후보.
- **approve 전이가 in_review→published 직행** — Domain Model §4.1 상태기계는 `approved` 중간 상태를 거치도록 정의하나 1c 구현은 walking skeleton 압축을 위해 생략하고 곧장 `published`로 전이. **명세-구현 정합성 정리 필요** (Domain 단순화 vs 구현 정상화 중 결정).
- **pd가 `generator.writer_contexts`에 직접 쓰기 (cross-schema write)** — 식별 결과 §38에 ADR 후보로 적힌 "pd→writer_contexts 직접 쓰기 정책"이 구현되었으나 ADR 미작성. **결정 근거·대안(이벤트, generator 호출) 문서화 필요.**
- **viewer / reader / 경제 명세 부재** — 본 줄기는 generator·pd만 다룬다. 발행된 회차의 노출·독자 모델·결제/구독은 walking skeleton 2단계에서 식별·작성.

---

## 변경 이력

- 2026-05-21: walking skeleton 1c 완성 — pd가 `in_review` 회차를 OpenAI로 검수해 `published`/`draft` 전이 (SRS-F-003/004). generator(1b)→pd(1c) 절반 시뮬레이터 자동 작동 확인 (실 OpenAI smoke: "강호의 문을 열다" 회차 approve 88점 → `published`).
- 2026-05-21: 구현 진행 — walking skeleton 1a(DB)·1b(generator)·1c(pd) 모두 구현 완료. "명세 → 코드 재현" 줄기는 회차 생성·검수 한정으로 동작.
- 2026-05-21: LLM 공급자 제약 완화 — Claude 고정 → 교체 가능(기본 OpenAI), 비용 사유.
- 2026-05-21: DB walking skeleton 1a — Data-Model.md → 실제 PostgreSQL 컨테이너 구현 (`docker-compose.yml`, `db/schema.sql`, `db/README.md`). 마이그레이션 도구·GRANT 권한 분리·updated_at/published_at/status 전이 트리거는 모두 `[확인 필요]`로 유지. UUID PK 기본값(DEFAULT)도 명세 외 → 미추가. 본 변경은 docs/ 명세 자체에는 새 항목을 추가하지 않음.
- 2026-05-21: 회차 생성→검수 줄기 명세 4건 신규 작성 — Domain Model, Data Model, SRS (SRS-F-001~004), Sequence/Flow (`FLOW-CHAPTER-LIFECYCLE`). Navigator 인덱스/식별 결과/추적 체크 동시 갱신.
- 2026-05-21: 고도화된 작가 개념 확장 — Domain Model에 `Writer` 엔티티, `AgentIdentity`/`WriterIdentity` 값 객체, §4.7 Writer↔Novel 1:N + 동시 active 1개 불변식, Aggregate "Novel" 외부 참조 항목, WriterContext의 정체성↔누적상태 구분 박스 추가. Data Model에 `generator.writers` 테이블, `public.novels.writer_id`, `novels_one_active_per_writer` 부분 유니크 인덱스, §6 정체성 저장소(파일) 절 추가(기존 §6 마이그레이션은 §7로 이동). ReaderIdentity는 개념만 언급(viewer 줄기 대기). Navigator에 Novel 연재 생명주기 미작성을 기술 빚으로 기록.
