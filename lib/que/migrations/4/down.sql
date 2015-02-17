DO $$
  BEGIN
    ALTER TABLE que_jobs ALTER COLUMN args DROP DEFAULT;
    ALTER TABLE que_jobs ALTER COLUMN args TYPE json USING args::json;
    ALTER TABLE que_jobs ALTER COLUMN args SET DEFAULT '[]'::json;
  END;
$$;