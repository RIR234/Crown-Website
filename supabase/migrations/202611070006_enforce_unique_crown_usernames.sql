-- Enforce globally unique, normalized Crown usernames.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
  ON public.profiles (lower(btrim(username)))
  WHERE username IS NOT NULL AND btrim(username) <> '';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND conname = 'profiles_username_format_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_username_format_check
      CHECK (username IS NULL OR username ~ '^[a-z0-9_]{3,24}$') NOT VALID;
  END IF;
END $$;

ALTER TABLE public.profiles
  VALIDATE CONSTRAINT profiles_username_format_check;
