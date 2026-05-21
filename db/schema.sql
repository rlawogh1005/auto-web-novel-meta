-- ============================================================
--  auto-web-novel — 회차 생성·검수 줄기 walking skeleton 1a
--  Source: docs/Data-Model.md (검증 대기, 2026-05-21)
--  Apply:  docker-entrypoint-initdb.d (initial container start only)
--  Re-init: docker compose down -v && docker compose up -d
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 분리 (Data-Model.md §5, WORLD.md §공통 규칙)
-- ------------------------------------------------------------
CREATE SCHEMA generator;
CREATE SCHEMA pd;

-- ------------------------------------------------------------
-- 2. ENUM (Data-Model.md §2)
--    chapter_status.rejected 는 enum에 남기되 현 줄기에서는 미사용.
-- ------------------------------------------------------------
CREATE TYPE chapter_status  AS ENUM ('draft', 'in_review', 'approved', 'published', 'rejected');
CREATE TYPE review_decision AS ENUM ('approve', 'reject', 'needs_revision');

-- ------------------------------------------------------------
-- 3. FK 부모 테이블 먼저
-- ------------------------------------------------------------

-- public.story_specs (novels.created_by_spec 의 FK 대상)
CREATE TABLE public.story_specs (
  id              uuid        PRIMARY KEY,
  genre           text        NOT NULL,
  target_audience text        NOT NULL,
  tone            text        NOT NULL,
  character_list  jsonb       NOT NULL,
  premise         text        NOT NULL,
  length_target   int         NOT NULL,
  frequency       text        NOT NULL,
  active          boolean     NOT NULL DEFAULT false,
  created_by      uuid        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- generator.writers (novels.writer_id 의 FK 대상)
CREATE TABLE generator.writers (
  id            text        PRIMARY KEY,
  identity_path text        NOT NULL,
  active        boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- 4. public.novels + 부분 유니크 인덱스 (§4.1)
-- ------------------------------------------------------------
CREATE TABLE public.novels (
  id              uuid        PRIMARY KEY,
  title           text        NOT NULL,
  genre           text        NOT NULL,
  premise         text        NOT NULL,
  created_by_spec uuid        REFERENCES public.story_specs(id),
  writer_id       text        NOT NULL REFERENCES generator.writers(id) ON DELETE RESTRICT,
  status          text        NOT NULL CHECK (status IN ('drafting', 'published', 'archived')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- §4.1: 한 작가는 동시에 active(=drafting) novel 1개
CREATE UNIQUE INDEX novels_one_active_per_writer
  ON public.novels (writer_id)
  WHERE status = 'drafting';

-- ------------------------------------------------------------
-- 5. public.chapters + 인덱스 3개 (§4.1, §4.2)
-- ------------------------------------------------------------
CREATE TABLE public.chapters (
  id           uuid           PRIMARY KEY,
  novel_id     uuid           NOT NULL REFERENCES public.novels(id) ON DELETE CASCADE,
  number       int            NOT NULL CHECK (number > 0),
  title        text           NOT NULL,
  content      text           NOT NULL,
  status       chapter_status NOT NULL,
  created_at   timestamptz    NOT NULL DEFAULT now(),
  updated_at   timestamptz    NOT NULL DEFAULT now(),
  published_at timestamptz    NULL,
  UNIQUE (novel_id, number)
);

-- §4.1: 한 번에 한 회차 (draft|in_review 중 1개)
CREATE UNIQUE INDEX chapters_one_active_per_novel
  ON public.chapters (novel_id)
  WHERE status IN ('draft', 'in_review');

-- §4.2: pd 폴링 — WHERE status='in_review' ORDER BY updated_at
CREATE INDEX chapters_status_updated_at_idx
  ON public.chapters (status, updated_at);

-- ------------------------------------------------------------
-- 6. generator 자식 테이블
-- ------------------------------------------------------------

-- 1:1 with novels
CREATE TABLE generator.writer_contexts (
  novel_id              uuid        PRIMARY KEY REFERENCES public.novels(id) ON DELETE CASCADE,
  big_story_outline     text        NOT NULL DEFAULT '',
  detailed_story_plan   jsonb       NOT NULL DEFAULT '{}'::jsonb,
  chapter_bodies_index  jsonb       NOT NULL DEFAULT '[]'::jsonb,
  feedback_log          jsonb       NOT NULL DEFAULT '[]'::jsonb,
  version               int         NOT NULL DEFAULT 0,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- 일화 — 복합 PK (novel_id, chapter_number). chapter_number 는 chapters.number 와 의미적 연결만(§3).
CREATE TABLE generator.episodes (
  novel_id       uuid  NOT NULL REFERENCES public.novels(id) ON DELETE CASCADE,
  chapter_number int   NOT NULL,
  summary        text  NOT NULL,
  key_events     jsonb NOT NULL DEFAULT '[]'::jsonb,
  PRIMARY KEY (novel_id, chapter_number)
);

CREATE TABLE generator.foreshadows (
  id                             uuid PRIMARY KEY,
  novel_id                       uuid NOT NULL REFERENCES public.novels(id) ON DELETE CASCADE,
  label                          text NOT NULL,
  planted_in_chapter             int  NOT NULL,
  expected_payoff_around_chapter int  NULL,
  status                         text NOT NULL CHECK (status IN ('open', 'paid_off')),
  notes                          text NOT NULL DEFAULT ''
);

CREATE TABLE generator.draft_runs (
  id                uuid        PRIMARY KEY,
  chapter_id        uuid        NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
  generator_version text        NOT NULL,
  llm_metadata      jsonb       NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- 7. pd 자식 테이블
-- ------------------------------------------------------------
CREATE TABLE pd.reviews (
  id            uuid            PRIMARY KEY,
  chapter_id    uuid            NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
  pd_version    text            NOT NULL,
  decision      review_decision NOT NULL,
  quality_score int             NOT NULL CHECK (quality_score BETWEEN 0 AND 100),
  feedback      text            NOT NULL DEFAULT '',
  created_at    timestamptz     NOT NULL DEFAULT now()
);

-- ============================================================
-- 트리거 / GRANT / 마이그레이션 도구 / 시드는 본 walking skeleton 범위 밖.
-- Data-Model.md §4.1, §5, §7 의 [확인 필요] 항목들 — 다음 단계에서 ADR.
-- ============================================================
