-- ============================================================
--  auto-web-novel — walking skeleton 3단계 (rewrite 루프 + abandoned 종착)
--  Source: docs/Data-Model.md §1 (public.chapters), §2 (chapter_status), §7.1
--  Target: 이미 떠있는 5433 컨테이너 (schema.sql 은 init 시 1회만 적용됨)
--  Idempotent: 여러 번 실행해도 안전 (IF NOT EXISTS / ADD VALUE IF NOT EXISTS)
--  Apply:
--    docker compose exec -T postgres psql -U postgres -d auto_web_novel \
--      < db/migrations/2026-05-rewrite.sql
-- ============================================================

-- §2: chapter_status enum 에 'abandoned' 추가 (재시도 상한 종착, Domain §4.10).
-- ADD VALUE IF NOT EXISTS 는 PG 9.6+ 에서 지원. 트랜잭션 블록 밖에서 실행해야 하므로
-- 본 파일은 psql 의 기본 autocommit 모드에서 실행한다 (BEGIN/COMMIT 감싸지 않음).
ALTER TYPE chapter_status ADD VALUE IF NOT EXISTS 'abandoned';

-- §1 public.chapters: revision_count (reject/needs_revision 시 +1, SRS-F-004),
-- abandoned_at (abandoned 전이 시점, published_at 패턴 대칭).
ALTER TABLE public.chapters
  ADD COLUMN IF NOT EXISTS revision_count int NOT NULL DEFAULT 0;

-- CHECK 제약은 ADD COLUMN 자체에 인라인으로 못 붙이고 (재실행 시 중복 에러),
-- 별도 ADD CONSTRAINT 도 IF NOT EXISTS 미지원 → DO 블록으로 존재 여부 확인 후 추가.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chapters_revision_count_check'
      AND conrelid = 'public.chapters'::regclass
  ) THEN
    ALTER TABLE public.chapters
      ADD CONSTRAINT chapters_revision_count_check CHECK (revision_count >= 0);
  END IF;
END$$;

ALTER TABLE public.chapters
  ADD COLUMN IF NOT EXISTS abandoned_at timestamptz NULL;
