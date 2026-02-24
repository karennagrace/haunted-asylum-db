-- =============================================================================
-- RPC: ingest_site(payload jsonb)
--
-- Idempotent ingestion for one site and its full corpus.
-- Re-running with the same payload is safe: all writes use ON CONFLICT upserts.
--
-- Call from DBeaver:
--   SELECT ingest_site($${ ... }$$::jsonb);
--
-- Call from Edge Function / client:
--   supabase.rpc('ingest_site', { payload: { ... } })
-- =============================================================================

CREATE OR REPLACE FUNCTION ingest_site(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_researcher_id uuid;
  v_site_id       uuid;
  v_doc_id        uuid;
  v_cap_id        uuid;
  d_idx           int;
  c_idx           int;
  e_idx           int;
BEGIN

  v_researcher_id := (payload->>'researcher_id')::uuid;

  -- ===========================================================================
  -- 1. SITE
  -- ===========================================================================
  INSERT INTO sites (
    site_id, site_name, official_site_url,
    country, region, city, address, notes,
    created_at, updated_at
  )
  VALUES (
    gen_random_uuid(),
    payload->'site'->>'site_name',
    payload->'site'->>'official_site_url',
    payload->'site'->>'country',
    payload->'site'->>'region',
    payload->'site'->>'city',
    payload->'site'->>'address',
    payload->'site'->>'notes',
    now(), now()
  )
  ON CONFLICT (official_site_url) DO UPDATE
    SET site_name  = EXCLUDED.site_name,
        country    = EXCLUDED.country,
        region     = EXCLUDED.region,
        city       = EXCLUDED.city,
        address    = EXCLUDED.address,
        notes      = EXCLUDED.notes,
        updated_at = now()
  RETURNING site_id INTO v_site_id;

  -- ===========================================================================
  -- 2. ALIASES
  -- Assumption: text column is alias. Adjust to match your schema.
  -- ===========================================================================
  FOR d_idx IN 0 .. COALESCE(jsonb_array_length(payload->'aliases'), 0) - 1
  LOOP
    INSERT INTO site_aliases (site_id, alias)
    VALUES (v_site_id, payload->'aliases'->>d_idx)
    ON CONFLICT (site_id, alias) DO NOTHING;
  END LOOP;

  -- ===========================================================================
  -- 3. OFFICIAL DOCUMENTS  →  CAPTURES  →  EVIDENCE
  --
  -- Payload shape per document:
  --   { source, url, title, publisher, published_date, official_category,
  --     captures: [ { capture_ts, kind, http_status, file_path, content_hash,
  --                   text_excerpt, notes,
  --                   evidence: [ { rule, evidence_type, evidence_date,
  --                                 access_date, description } ] } ],
  --     evidence: [ ... ]   ← document-level evidence (no specific capture) }
  -- ===========================================================================
  FOR d_idx IN 0 .. COALESCE(jsonb_array_length(payload->'documents'), 0) - 1
  LOOP
    DECLARE doc jsonb := payload->'documents'->d_idx; BEGIN

    -- Upsert document --------------------------------------------------------
    INSERT INTO documents (
      document_id, site_id, source, url, title,
      publisher, published_date, official_category
    )
    VALUES (
      gen_random_uuid(),
      v_site_id,
      (doc->>'source')::doc_source,
      doc->>'url',
      doc->>'title',
      doc->>'publisher',
      (doc->>'published_date')::date,
      (doc->>'official_category')::official_page_category
    )
    ON CONFLICT (site_id, url) DO UPDATE
      SET title             = EXCLUDED.title,
          publisher         = EXCLUDED.publisher,
          published_date    = EXCLUDED.published_date,
          official_category = EXCLUDED.official_category
    RETURNING document_id INTO v_doc_id;

    -- Upsert captures --------------------------------------------------------
    FOR c_idx IN 0 .. COALESCE(jsonb_array_length(doc->'captures'), 0) - 1
    LOOP
      DECLARE cap jsonb := doc->'captures'->c_idx; BEGIN

      INSERT INTO captures (
        capture_id, document_id, captured_by, capture_ts,
        kind, http_status, file_path, content_hash, text_excerpt, notes
      )
      VALUES (
        gen_random_uuid(),
        v_doc_id,
        v_researcher_id,
        (cap->>'capture_ts')::timestamptz,
        (cap->>'kind')::capture_kind,
        (cap->>'http_status')::int,
        cap->>'file_path',
        cap->>'content_hash',
        cap->>'text_excerpt',
        cap->>'notes'
      )
      ON CONFLICT (document_id, content_hash) DO UPDATE
        SET file_path    = EXCLUDED.file_path,
            capture_ts   = EXCLUDED.capture_ts,
            text_excerpt = EXCLUDED.text_excerpt,
            notes        = EXCLUDED.notes
      RETURNING capture_id INTO v_cap_id;

      -- Evidence tied to this specific capture --------------------------------
      FOR e_idx IN 0 .. COALESCE(jsonb_array_length(cap->'evidence'), 0) - 1
      LOOP
        DECLARE ev jsonb := cap->'evidence'->e_idx; BEGIN

        INSERT INTO evidence_items (
          evidence_id, site_id, rule, evidence_type,
          document_id, capture_id,
          evidence_date, access_date, description
        )
        VALUES (
          gen_random_uuid(),
          v_site_id,
          (ev->>'rule')::rule_code,
          (ev->>'evidence_type')::evidence_kind,
          v_doc_id,
          v_cap_id,
          (ev->>'evidence_date')::date,
          (ev->>'access_date')::date,
          ev->>'description'
        )
        ON CONFLICT (
          site_id, rule, evidence_type,
          COALESCE(document_id, '00000000-0000-0000-0000-000000000000'::uuid),
          COALESCE(capture_id,  '00000000-0000-0000-0000-000000000000'::uuid)
        ) DO UPDATE
          SET evidence_date = EXCLUDED.evidence_date,
              access_date   = EXCLUDED.access_date,
              description   = EXCLUDED.description;

        END;
      END LOOP; -- capture-level evidence

      END;
    END LOOP; -- captures

    -- Evidence tied to the document (no specific capture) --------------------
    FOR e_idx IN 0 .. COALESCE(jsonb_array_length(doc->'evidence'), 0) - 1
    LOOP
      DECLARE ev jsonb := doc->'evidence'->e_idx; BEGIN

      INSERT INTO evidence_items (
        evidence_id, site_id, rule, evidence_type,
        document_id, capture_id,
        evidence_date, access_date, description
      )
      VALUES (
        gen_random_uuid(),
        v_site_id,
        (ev->>'rule')::rule_code,
        (ev->>'evidence_type')::evidence_kind,
        v_doc_id,
        NULL,
        (ev->>'evidence_date')::date,
        (ev->>'access_date')::date,
        ev->>'description'
      )
      ON CONFLICT (
        site_id, rule, evidence_type,
        COALESCE(document_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(capture_id,  '00000000-0000-0000-0000-000000000000'::uuid)
      ) DO UPDATE
        SET evidence_date = EXCLUDED.evidence_date,
            access_date   = EXCLUDED.access_date,
            description   = EXCLUDED.description;

      END;
    END LOOP; -- document-level evidence

    END;
  END LOOP; -- documents

  -- ===========================================================================
  -- 4. TV EPISODES
  -- ===========================================================================
  FOR d_idx IN 0 .. COALESCE(jsonb_array_length(payload->'tv_episodes'), 0) - 1
  LOOP
    DECLARE ep jsonb := payload->'tv_episodes'->d_idx; BEGIN

    INSERT INTO tv_episodes (
      tv_episode_id, site_id,
      show_name, season_number, episode_number, episode_title,
      air_date, synopsis, channel,
      viewers, imdb_rating, imdb_quantity
    )
    VALUES (
      gen_random_uuid(),
      v_site_id,
      ep->>'show_name',
      (ep->>'season_number')::int,
      (ep->>'episode_number')::int,
      ep->>'episode_title',
      (ep->>'air_date')::date,
      ep->>'synopsis',
      ep->>'channel',
      (ep->>'viewers')::bigint,
      (ep->>'imdb_rating')::numeric(4,1),
      (ep->>'imdb_quantity')::int
    )
    ON CONFLICT (site_id, show_name, season_number, episode_number) DO UPDATE
      SET episode_title = EXCLUDED.episode_title,
          air_date      = EXCLUDED.air_date,
          synopsis      = EXCLUDED.synopsis,
          channel       = EXCLUDED.channel,
          viewers       = EXCLUDED.viewers,
          imdb_rating   = EXCLUDED.imdb_rating,
          imdb_quantity = EXCLUDED.imdb_quantity;

    END;
  END LOOP;

  -- ===========================================================================
  -- 5. YOUTUBE VIDEOS
  -- ===========================================================================
  FOR d_idx IN 0 .. COALESCE(jsonb_array_length(payload->'youtube_videos'), 0) - 1
  LOOP
    DECLARE yt jsonb := payload->'youtube_videos'->d_idx; BEGIN

    INSERT INTO youtube_videos (
      youtube_video_id, site_id, url,
      video_title, channel_name, upload_date,
      view_count, like_count, comment_count,
      description_text, duration, category, channel_subscribers
    )
    VALUES (
      gen_random_uuid(),
      v_site_id,
      yt->>'url',
      yt->>'video_title',
      yt->>'channel_name',
      (yt->>'upload_date')::date,
      (yt->>'view_count')::bigint,
      (yt->>'like_count')::bigint,
      (yt->>'comment_count')::bigint,
      yt->>'description_text',
      yt->>'duration',
      yt->>'category',
      (yt->>'channel_subscribers')::bigint
    )
    ON CONFLICT (url) DO UPDATE
      SET video_title         = EXCLUDED.video_title,
          channel_name        = EXCLUDED.channel_name,
          view_count          = EXCLUDED.view_count,
          like_count          = EXCLUDED.like_count,
          comment_count       = EXCLUDED.comment_count,
          description_text    = EXCLUDED.description_text,
          channel_subscribers = EXCLUDED.channel_subscribers;

    END;
  END LOOP;

  -- ===========================================================================
  -- 6. REVIEW PROFILES  (optional)
  --
  -- Payload shape per profile:
  --   { platform_id, profile_url,
  --     documents: [ { source, url, title, publisher, published_date,
  --                    captures: [ { ... evidence: [...] } ] } ] }
  -- ===========================================================================
  FOR d_idx IN 0 .. COALESCE(jsonb_array_length(payload->'review_profiles'), 0) - 1
  LOOP
    DECLARE rp jsonb := payload->'review_profiles'->d_idx; BEGIN

    INSERT INTO site_review_profiles (
      site_review_profile_id, site_id, platform_id, profile_url
    )
    VALUES (
      gen_random_uuid(),
      v_site_id,
      (rp->>'platform_id')::uuid,
      rp->>'profile_url'
    )
    ON CONFLICT (site_id, platform_id, profile_url) DO NOTHING;

    -- Review documents -------------------------------------------------------
    FOR c_idx IN 0 .. COALESCE(jsonb_array_length(rp->'documents'), 0) - 1
    LOOP
      DECLARE doc jsonb := rp->'documents'->c_idx; BEGIN

      INSERT INTO documents (
        document_id, site_id, source, url, title,
        publisher, published_date, official_category
      )
      VALUES (
        gen_random_uuid(),
        v_site_id,
        (doc->>'source')::doc_source,
        doc->>'url',
        doc->>'title',
        doc->>'publisher',
        (doc->>'published_date')::date,
        NULL  -- review documents carry no official_category
      )
      ON CONFLICT (site_id, url) DO UPDATE
        SET title          = EXCLUDED.title,
            publisher      = EXCLUDED.publisher,
            published_date = EXCLUDED.published_date
      RETURNING document_id INTO v_doc_id;

      -- Review captures ------------------------------------------------------
      FOR e_idx IN 0 .. COALESCE(jsonb_array_length(doc->'captures'), 0) - 1
      LOOP
        DECLARE cap jsonb := doc->'captures'->e_idx; BEGIN

        INSERT INTO captures (
          capture_id, document_id, captured_by, capture_ts,
          kind, http_status, file_path, content_hash, text_excerpt, notes
        )
        VALUES (
          gen_random_uuid(),
          v_doc_id,
          v_researcher_id,
          (cap->>'capture_ts')::timestamptz,
          (cap->>'kind')::capture_kind,
          (cap->>'http_status')::int,
          cap->>'file_path',
          cap->>'content_hash',
          cap->>'text_excerpt',
          cap->>'notes'
        )
        ON CONFLICT (document_id, content_hash) DO UPDATE
          SET file_path    = EXCLUDED.file_path,
              capture_ts   = EXCLUDED.capture_ts,
              text_excerpt = EXCLUDED.text_excerpt,
              notes        = EXCLUDED.notes
        RETURNING capture_id INTO v_cap_id;

        -- Evidence on review captures ----------------------------------------
        DECLARE ev_inner jsonb; BEGIN
        FOR ev_inner IN
          SELECT value FROM jsonb_array_elements(cap->'evidence') AS t(value)
        LOOP
          INSERT INTO evidence_items (
            evidence_id, site_id, rule, evidence_type,
            document_id, capture_id,
            evidence_date, access_date, description
          )
          VALUES (
            gen_random_uuid(),
            v_site_id,
            (ev_inner->>'rule')::rule_code,
            (ev_inner->>'evidence_type')::evidence_kind,
            v_doc_id,
            v_cap_id,
            (ev_inner->>'evidence_date')::date,
            (ev_inner->>'access_date')::date,
            ev_inner->>'description'
          )
          ON CONFLICT (
            site_id, rule, evidence_type,
            COALESCE(document_id, '00000000-0000-0000-0000-000000000000'::uuid),
            COALESCE(capture_id,  '00000000-0000-0000-0000-000000000000'::uuid)
          ) DO UPDATE
            SET evidence_date = EXCLUDED.evidence_date,
                access_date   = EXCLUDED.access_date,
                description   = EXCLUDED.description;
        END LOOP;
        END; -- evidence sub-block

        END;
      END LOOP; -- review captures

      END;
    END LOOP; -- review documents

    END;
  END LOOP; -- review profiles

  -- ===========================================================================
  -- Return
  -- ===========================================================================
  RETURN jsonb_build_object(
    'ok',      true,
    'site_id', v_site_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'ok',       false,
    'error',    SQLERRM,
    'sqlstate', SQLSTATE
  );

END;
$$;

-- Grant execute to authenticated role so the Edge Function can call it
GRANT EXECUTE ON FUNCTION ingest_site(jsonb) TO authenticated;
