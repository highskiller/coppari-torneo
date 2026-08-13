-- Copparì Live · correzione pgcrypto per installazioni Supabase già configurate
-- Eseguire una sola volta nel SQL Editor del progetto Supabase.

alter function public.coppari_live_create(text, text, text, jsonb)
  set search_path = pg_catalog, public, extensions;

alter function public.coppari_live_read(text)
  set search_path = pg_catalog, public, extensions;

alter function public.coppari_live_update(text, text, bigint, jsonb)
  set search_path = pg_catalog, public, extensions;

alter function public.coppari_live_update_referee(text, text, bigint, jsonb)
  set search_path = pg_catalog, public, extensions;

alter function public.coppari_live_stop(text, text)
  set search_path = pg_catalog, public, extensions;
