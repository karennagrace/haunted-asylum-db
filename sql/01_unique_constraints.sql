-- =============================================================================
-- Unique Constraints for idempotent upserts
-- Run once in DBeaver against your Supabase Postgres instance.
-- Skip any ADD CONSTRAINT line if the constraint already exists.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- sites
-- Natural dedup key: official_site_url
-- -----------------------------------------------------------------------------
ALTER TABLE sites
  ADD CONSTRAINT uq_sites_official_url UNIQUE (official_site_url);

-- -----------------------------------------------------------------------------
-- site_aliases
-- -----------------------------------------------------------------------------
ALTER TABLE site_aliases
  ADD CONSTRAINT uq_site_aliases UNIQUE (site_id, alias);

-- -----------------------------------------------------------------------------
-- documents
-- One record per (site, URL). Same page re-fetched → same document row.
-- -----------------------------------------------------------------------------
ALTER TABLE documents
  ADD CONSTRAINT uq_documents_site_url UNIQUE (site_id, url);

-- -----------------------------------------------------------------------------
-- captures
-- Same document + same SHA-256 hash = same capture. Prevents re-inserting an
-- unchanged snapshot. content_hash must not be NULL for this to fire reliably.
-- -----------------------------------------------------------------------------
ALTER TABLE captures
  ADD CONSTRAINT uq_captures_doc_hash UNIQUE (document_id, content_hash);

-- -----------------------------------------------------------------------------
-- evidence_items
-- Both document_id and capture_id are nullable FKs. Standard UNIQUE constraints
-- treat every NULL as distinct, so we use a functional index with a sentinel
-- UUID (the nil UUID) in place of NULLs. This lets ON CONFLICT work correctly.
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_evidence_natural_key
  ON evidence_items (
    site_id,
    rule,
    evidence_type,
    COALESCE(document_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(capture_id,  '00000000-0000-0000-0000-000000000000'::uuid)
  );

-- -----------------------------------------------------------------------------
-- tv_episodes
-- Natural key: site + show name + season + episode number
-- -----------------------------------------------------------------------------
ALTER TABLE tv_episodes
  ADD CONSTRAINT uq_tv_episodes_natural_key
  UNIQUE (site_id, show_name, season_number, episode_number);

-- -----------------------------------------------------------------------------
-- youtube_videos
-- url should already be UNIQUE per your schema description.
-- Un-comment only if the constraint does not yet exist.
-- -----------------------------------------------------------------------------
-- ALTER TABLE youtube_videos ADD CONSTRAINT uq_youtube_url UNIQUE (url);

-- -----------------------------------------------------------------------------
-- site_review_profiles
-- One profile record per (site, platform, URL triplet)
-- -----------------------------------------------------------------------------
ALTER TABLE site_review_profiles
  ADD CONSTRAINT uq_site_review_profiles
  UNIQUE (site_id, platform_id, profile_url);
