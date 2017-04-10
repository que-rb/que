DO $$
  BEGIN
    IF 90400 >= (SELECT setting::integer FROM pg_settings WHERE name = 'server_version_num') THEN
      ALTER TABLE que_jobs ALTER COLUMN args DROP DEFAULT;
      ALTER TABLE que_jobs ALTER COLUMN args TYPE jsonb USING args::jsonb;
      ALTER TABLE que_jobs ALTER COLUMN args SET DEFAULT '[]'::jsonb;
    ELSE
      RAISE NOTICE 'Using `json` datatype as your version of PG is < 9.4';
    END IF;
  END;
$$;