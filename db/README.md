# DB — walking skeleton 1a

`docs/Data-Model.md`(검증 대기, 2026-05-21)의 회차 생성·검수 줄기 스키마를 raw SQL로 옮긴 초기 데이터베이스. **이 단계의 목표는 "스키마가 실제로 생성되는가" 검증뿐.** 마이그레이션 도구·GRANT 기반 권한 분리·시드 데이터·앱 연결은 다음 단계 (Data-Model.md §7 + `docs/Navigator.md`).

생성 범위:
- 스키마 3개 — `public`, `generator`, `pd`
- 테이블 9개 — `public.{novels, chapters, story_specs}`, `generator.{writers, writer_contexts, episodes, foreshadows, draft_runs}`, `pd.{reviews}`
- ENUM 2개 — `chapter_status`, `review_decision`
- 인덱스 (PK/유니크 제외) 3개 — `novels_one_active_per_writer`, `chapters_one_active_per_novel`, `chapters_status_updated_at_idx`

---

## 띄우기

```powershell
docker compose up -d
docker compose ps          # postgres 컨테이너가 (healthy) 인지 확인
```

`docker-entrypoint-initdb.d` 메커니즘으로 `db/schema.sql`이 **최초 부팅 시 1회** 자동 적용된다 (`docker-compose.yml` 의 마운트 참조).

호스트에서 직접 접속하려면 **포트 5433** (컨테이너 내부는 5432, `docker-compose.yml`의 `ports: "5433:5432"`):

```powershell
psql -h localhost -p 5433 -U postgres -d auto_web_novel    # 비번: postgres
```

> 5432가 아닌 5433을 쓰는 이유: 로컬에 이미 다른 Postgres가 5432를 점유하는 환경 대응. 충돌이 없는 환경에서는 `docker-compose.yml` 의 ports 한 줄만 `5432:5432`로 바꿔도 됨.

---

## 스키마 생성 확인

다음 6개 명령을 차례로 실행해 출력이 기대치와 일치하는지 본다.

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "\dn"
```
→ `generator`, `pd`, `public` 모두 출력

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "\dt public.*"
```
→ `chapters`, `novels`, `story_specs` 3행

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "\dt generator.*"
```
→ `draft_runs`, `episodes`, `foreshadows`, `writer_contexts`, `writers` 5행

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "\dt pd.*"
```
→ `reviews` 1행

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "SELECT typname FROM pg_type WHERE typname IN ('chapter_status','review_decision') ORDER BY typname"
```
→ `chapter_status`, `review_decision` 2행

```powershell
docker compose exec postgres psql -U postgres -d auto_web_novel -c "SELECT indexname FROM pg_indexes WHERE schemaname='public' AND tablename IN ('novels','chapters') ORDER BY indexname"
```
→ 최소 다음 5개 포함:
- `chapters_novel_id_number_key` (UNIQUE on (novel_id, number))
- `chapters_one_active_per_novel` (부분 UNIQUE — §4.1)
- `chapters_pkey`
- `chapters_status_updated_at_idx` (pd 폴링 인덱스 — §4.2)
- `novels_one_active_per_writer` (부분 UNIQUE — §4.1)
- `novels_pkey`

---

## 재초기화

`docker-entrypoint-initdb.d/*.sql` 은 **빈 데이터 디렉토리에만** 실행된다. 즉 `schema.sql` 을 수정해도 기존 볼륨이 살아 있으면 반영되지 **않는다.** 스키마를 다시 적용하려면 볼륨까지 지우고 새로 띄운다.

```powershell
docker compose down -v   # 컨테이너 + 볼륨(pgdata) 삭제 — 데이터 손실 주의
docker compose up -d     # 빈 볼륨에서 schema.sql 다시 init
```

---

## 마이그레이션 (떠있는 DB에 변경 적용)

기존 볼륨을 유지한 채 스키마 변경을 반영. `db/migrations/*.sql` 은 모두 idempotent (`IF NOT EXISTS`) 라 여러 번 실행해도 안전.

```powershell
docker compose exec -T postgres psql -U postgres -d auto_web_novel -f - < db/migrations/2026-05-rewrite.sql
```

> walking skeleton 3단계 (rewrite 루프). 추가 항목: `chapter_status='abandoned'`, `chapters.revision_count`, `chapters.abandoned_at` (Data-Model §1, §2, §7.1).

---

## 종료

```powershell
docker compose down        # 컨테이너만 정지 (볼륨 유지 → 다음 up 시 데이터 보존)
docker compose down -v     # 컨테이너 + 볼륨 삭제 (완전 초기화)
```

---

## 다음 단계 (본 README 범위 밖)

- 마이그레이션 도구 ADR (Alembic / Atlas / golang-migrate)
- GRANT 기반 스키마 권한 분리 (Data-Model.md §5 `[확인 필요]`)
- 시드 데이터 SQL — `writers` 1, `novels` 1 (drafting), `writer_contexts` 1. 부분 유니크 위반·CASCADE 동작도 같이 검증.
- `updated_at` / `published_at` / status 전이 검증 트리거 (§4.1 `[확인 필요]`)
- generator(Python) → DB 연결 → 첫 회차 생성 → pd 폴링 → review 1바퀴 (`docs/Flow-Chapter-Lifecycle.md`)
