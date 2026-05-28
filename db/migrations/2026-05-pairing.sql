-- ============================================================
--  auto-web-novel — walking skeleton 4단계 (작가-PD 1:1 페어링 골격)
--  Source: docs/Data-Model.md §1 (pd.pd_agents, public.novels.assigned_pd_id),
--          §4.1 (novels_one_active_per_pd), §7.2 (마이그레이션 절차)
--  SRS:    SRS-F-009 (작가-PD 1:1 페어링)
--  Target: 이미 떠있는 5433 컨테이너 (schema.sql 은 init 시 1회만 적용됨)
--  Idempotent: 여러 번 실행해도 안전 (IF NOT EXISTS / ON CONFLICT / pg_constraint 체크)
--  Apply:
--    docker compose exec -T postgres psql -U postgres -d auto_web_novel \
--      < db/migrations/2026-05-pairing.sql
-- ============================================================

-- §1 pd.pd_agents: PD 명부 (id 슬러그 + active). 정체성 파일 부재 — 공통 rubric.
CREATE TABLE IF NOT EXISTS pd.pd_agents (
  id         text        PRIMARY KEY,
  active     boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- §7.2 시드: 백필·NOT NULL 부착 전에 active PD row 1건 이상 필요.
INSERT INTO pd.pd_agents (id) VALUES ('pd-alpha')
  ON CONFLICT (id) DO NOTHING;

-- §1 public.novels.assigned_pd_id: 우선 nullable 추가, 백필 후 NOT NULL 부착.
ALTER TABLE public.novels
  ADD COLUMN IF NOT EXISTS assigned_pd_id text;

-- FK 제약: ADD CONSTRAINT 가 IF NOT EXISTS 미지원 → pg_constraint 존재 체크
-- (2026-05-rewrite.sql 의 chapters_revision_count_check 패턴 답습).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'novels_assigned_pd_id_fkey'
      AND conrelid = 'public.novels'::regclass
  ) THEN
    ALTER TABLE public.novels
      ADD CONSTRAINT novels_assigned_pd_id_fkey
      FOREIGN KEY (assigned_pd_id)
      REFERENCES pd.pd_agents(id)
      ON DELETE RESTRICT;
  END IF;
END$$;

-- §4.1 한 PD 는 동시에 active 소설 1개 (Domain §4.11 — 1:1 페어링 골격).
CREATE UNIQUE INDEX IF NOT EXISTS novels_one_active_per_pd
  ON public.novels (assigned_pd_id)
  WHERE status = 'drafting';

-- §7.2 백필: 기존 novels row 의 assigned_pd_id 를 시드 PD 로 일괄 채움.
-- 실 데이터 없으면 0 rows affected — 무해.
UPDATE public.novels
  SET assigned_pd_id = 'pd-alpha'
  WHERE assigned_pd_id IS NULL;

-- §7.2 NOT NULL 부착: 재실행 안전 — 이미 NOT NULL 이면 PG 가 무시.
ALTER TABLE public.novels
  ALTER COLUMN assigned_pd_id SET NOT NULL;
