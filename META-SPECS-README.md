# 하네스 적용 가이드 (README)

> meta-specs 기반 명세 하네스를 6개 repo에 적용하는 방법.
> 이 구조는 신규 프로젝트와 진행 중 프로젝트 양쪽에 삽입 가능하다.

---

## 전체 구조

```
auto-web-novel/                         ← 부모 (모든 repo가 ../로 참조)
│
├── meta-specs/                         ← 표준: "명세를 어떻게 만드는가" (수정 안 함)
│   ├── Master-Meta-Spec-Info.md            진입점 + 식별 절차 + ID/관계 규칙
│   ├── Product-Requirements-Meta-Spec-Info.md
│   ├── Architecture-Design-Meta-Spec-Info.md
│   ├── Constraints-Operation-Meta-Spec-Info.md
│   └── Domain-Meta-Spec-Info.md
│
├── docs/                               ← 실제 명세 (비어서 시작, 에이전트가 채움)
│   └── Navigator.md                        라이브 현황판/인덱스
│
├── WORLD.md                            ← 세계관·서비스 맵 (기존)
├── AGENTS.md                           ← 라우터 진입점 (부모 레벨 공통본)
│
├── auto-web-novel-generator/
│   ├── CLAUDE.md   → @AGENTS.md 라우팅 (얇음)
│   └── AGENTS.md   → 이 서비스용 (역할/스택 채움)
├── ... (6개 repo 동일)
```

---

## 작동 원리 (하네스)

에이전트가 어느 repo에서 시작하든 항상 같은 경로를 탄다:

```
CLAUDE.md (@AGENTS.md)
  → AGENTS.md (읽는 순서 §0)
    → ../meta-specs/Master (명세 만드는 법)
    → ../docs/Navigator.md (지금 현황)
    → ../WORLD.md (세계관)
  → 작업
```

명세 작업 시:
```
meta-specs 읽음 → 이 프로젝트에 필요한 명세 "식별" → docs/에 작성 → Navigator 갱신
```

docs/가 비어 있어도, 일부만 있어도 동일하게 작동한다. 그래서 신규/진행중 모두 삽입 가능하다.

---

## 6개 repo 적용 절차

각 repo(generator/viewer/pd/admin/web-app/mobile-app)에서:

### 1. 기존 CLAUDE.md 내용을 AGENTS.md로 이전
- 현재 CLAUDE.md의 서비스 역할·스택·규칙을 새 `AGENTS.md`로 옮긴다.
- 부모의 `AGENTS.md`(공통본)를 베이스로, 이 서비스의 §1 역할·§2 스택을 채운다.

### 2. CLAUDE.md를 얇은 라우터로 교체
- `CLAUDE.md.template` 내용으로 CLAUDE.md를 덮어쓴다 (`@AGENTS.md`만 가리킴).

### 3. 참조 경로 확인
- AGENTS.md가 `../meta-specs/`, `../docs/`, `../WORLD.md`를 참조 — 부모 폴더에 실제로 존재하는지 확인.

### 4. 커밋
- `chore: route via AGENTS.md + adopt meta-specs harness` 식으로 PR.

> meta-specs/docs/WORLD.md는 부모 폴더에 있고 git 추적되지 않는다 (WORLD.md와 동일 방식). 에이전트가 `../`로 읽는다.

---

## 다음 단계

하네스 적용 후, 실제 명세 작성은 에이전트에게:
```
@AGENTS.md 읽고, Master 절차대로 이 프로젝트에 필요한 명세를 식별해줘.
docs/는 비어있으니 신규 식별. 식별 결과를 먼저 보고하고 승인받은 뒤 작성.
```
