-- Copparì Live · backend persistente Supabase
-- Eseguire una sola volta nel SQL Editor del progetto Supabase.

create extension if not exists pgcrypto;

create table if not exists public.coppari_live_tournaments (
  room_id text primary key,
  state jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  manager_secret_hash bytea not null,
  referee_secret_hash bytea not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coppari_live_room_id_format
    check (room_id ~ '^coppari-[A-Za-z0-9_-]{20,80}$'),
  constraint coppari_live_state_object
    check (jsonb_typeof(state) = 'object')
);

alter table public.coppari_live_tournaments enable row level security;
revoke all on table public.coppari_live_tournaments from public, anon, authenticated;

create or replace function public.coppari_live_create(
  p_room_id text,
  p_manager_secret text,
  p_referee_secret text,
  p_state jsonb
)
returns table (
  accepted boolean,
  revision bigint,
  state jsonb,
  active boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_row public.coppari_live_tournaments%rowtype;
begin
  if p_room_id !~ '^coppari-[A-Za-z0-9_-]{20,80}$' then
    raise exception 'LIVE_ROOM_INVALID';
  end if;
  if p_manager_secret !~ '^[A-Za-z0-9_-]{20,120}$'
     or p_referee_secret !~ '^[A-Za-z0-9_-]{20,120}$' then
    raise exception 'LIVE_SECRET_INVALID';
  end if;
  if jsonb_typeof(p_state) <> 'object' or octet_length(p_state::text) > 2000000 then
    raise exception 'LIVE_STATE_INVALID';
  end if;

  insert into public.coppari_live_tournaments (
    room_id,
    state,
    manager_secret_hash,
    referee_secret_hash
  ) values (
    p_room_id,
    p_state,
    digest(p_manager_secret, 'sha256'),
    digest(p_referee_secret, 'sha256')
  )
  on conflict (room_id) do nothing;

  select * into v_row
  from public.coppari_live_tournaments as tournament
  where tournament.room_id = p_room_id;

  if v_row.manager_secret_hash <> digest(p_manager_secret, 'sha256') then
    raise exception 'LIVE_ROOM_TAKEN';
  end if;

  return query
  select true, v_row.revision, v_row.state, v_row.active, v_row.updated_at;
end;
$$;

create or replace function public.coppari_live_read(p_room_id text)
returns table (
  revision bigint,
  state jsonb,
  active boolean,
  updated_at timestamptz
)
language plpgsql
security definer
stable
set search_path = pg_catalog, public, extensions
as $$
begin
  if p_room_id !~ '^coppari-[A-Za-z0-9_-]{20,80}$' then
    return;
  end if;

  return query
  select tournament.revision, tournament.state, tournament.active, tournament.updated_at
  from public.coppari_live_tournaments as tournament
  where tournament.room_id = p_room_id;
end;
$$;

create or replace function public.coppari_live_update(
  p_room_id text,
  p_manager_secret text,
  p_base_revision bigint,
  p_state jsonb
)
returns table (
  accepted boolean,
  revision bigint,
  state jsonb,
  active boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_row public.coppari_live_tournaments%rowtype;
begin
  if jsonb_typeof(p_state) <> 'object' or octet_length(p_state::text) > 2000000 then
    raise exception 'LIVE_STATE_INVALID';
  end if;

  select * into v_row
  from public.coppari_live_tournaments as tournament
  where tournament.room_id = p_room_id
  for update;

  if not found then
    raise exception 'LIVE_ROOM_NOT_FOUND';
  end if;
  if v_row.manager_secret_hash <> digest(coalesce(p_manager_secret, ''), 'sha256') then
    raise exception 'LIVE_ACCESS_DENIED';
  end if;
  if not v_row.active then
    raise exception 'LIVE_ENDED';
  end if;
  if v_row.revision <> p_base_revision then
    return query
    select false, v_row.revision, v_row.state, v_row.active, v_row.updated_at;
    return;
  end if;

  update public.coppari_live_tournaments as tournament
  set state = p_state,
      revision = tournament.revision + 1,
      updated_at = now()
  where tournament.room_id = p_room_id
  returning tournament.* into v_row;

  return query
  select true, v_row.revision, v_row.state, v_row.active, v_row.updated_at;
end;
$$;

create or replace function public.coppari_live_update_referee(
  p_room_id text,
  p_referee_secret text,
  p_base_revision bigint,
  p_match jsonb
)
returns table (
  accepted boolean,
  revision bigint,
  state jsonb,
  active boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_row public.coppari_live_tournaments%rowtype;
  v_old_match jsonb;
  v_safe_match jsonb;
  v_matches jsonb;
  v_match_id text := p_match ->> 'id';
  v_status text := p_match ->> 'status';
begin
  if jsonb_typeof(p_match) <> 'object' or octet_length(p_match::text) > 600000 then
    raise exception 'LIVE_MATCH_INVALID';
  end if;
  if v_match_id is null or v_status not in ('scheduled', 'live', 'played') then
    raise exception 'LIVE_MATCH_INVALID';
  end if;
  if jsonb_typeof(coalesce(p_match -> 'events', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_match -> 'stats', '[]'::jsonb)) <> 'array' then
    raise exception 'LIVE_MATCH_INVALID';
  end if;

  select * into v_row
  from public.coppari_live_tournaments as tournament
  where tournament.room_id = p_room_id
  for update;

  if not found then
    raise exception 'LIVE_ROOM_NOT_FOUND';
  end if;
  if v_row.referee_secret_hash <> digest(coalesce(p_referee_secret, ''), 'sha256') then
    raise exception 'LIVE_ACCESS_DENIED';
  end if;
  if not v_row.active then
    raise exception 'LIVE_ENDED';
  end if;
  if v_row.revision <> p_base_revision then
    return query
    select false, v_row.revision, v_row.state, v_row.active, v_row.updated_at;
    return;
  end if;

  select match_item into v_old_match
  from jsonb_array_elements(coalesce(v_row.state -> 'matches', '[]'::jsonb)) as match_item
  where match_item ->> 'id' = v_match_id
  limit 1;

  if v_old_match is null then
    raise exception 'LIVE_MATCH_NOT_FOUND';
  end if;

  v_safe_match := v_old_match || jsonb_build_object(
    'status', p_match -> 'status',
    'homeScore', p_match -> 'homeScore',
    'awayScore', p_match -> 'awayScore',
    'penHome', p_match -> 'penHome',
    'penAway', p_match -> 'penAway',
    'date', p_match -> 'date',
    'events', coalesce(p_match -> 'events', '[]'::jsonb),
    'stats', coalesce(p_match -> 'stats', '[]'::jsonb),
    'referee', p_match -> 'referee',
    'mvpPlayerId', p_match -> 'mvpPlayerId',
    'ratings', case when v_status = 'scheduled' then '[]'::jsonb else coalesce(v_old_match -> 'ratings', '[]'::jsonb) end,
    'ratingsPublished', case when v_status = 'scheduled' then false else coalesce((v_old_match ->> 'ratingsPublished')::boolean, false) end
  );

  select jsonb_agg(
    case when match_item ->> 'id' = v_match_id then v_safe_match else match_item end
    order by ordinal
  ) into v_matches
  from jsonb_array_elements(coalesce(v_row.state -> 'matches', '[]'::jsonb))
       with ordinality as matches(match_item, ordinal);

  if v_status = 'live' and (
    select count(*)
    from jsonb_array_elements(coalesce(v_matches, '[]'::jsonb)) as match_item
    where match_item ->> 'status' = 'live'
  ) > 1 then
    raise exception 'LIVE_ANOTHER_MATCH_ACTIVE';
  end if;

  update public.coppari_live_tournaments as tournament
  set state = jsonb_set(v_row.state, '{matches}', coalesce(v_matches, '[]'::jsonb), true),
      revision = tournament.revision + 1,
      updated_at = now()
  where tournament.room_id = p_room_id
  returning tournament.* into v_row;

  return query
  select true, v_row.revision, v_row.state, v_row.active, v_row.updated_at;
end;
$$;

create or replace function public.coppari_live_stop(
  p_room_id text,
  p_manager_secret text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_hash bytea;
begin
  select tournament.manager_secret_hash into v_hash
  from public.coppari_live_tournaments as tournament
  where tournament.room_id = p_room_id
  for update;

  if not found then
    return false;
  end if;
  if v_hash <> digest(coalesce(p_manager_secret, ''), 'sha256') then
    raise exception 'LIVE_ACCESS_DENIED';
  end if;

  update public.coppari_live_tournaments as tournament
  set active = false,
      revision = tournament.revision + 1,
      updated_at = now()
  where tournament.room_id = p_room_id;
  return true;
end;
$$;

revoke all on function public.coppari_live_create(text, text, text, jsonb) from public;
revoke all on function public.coppari_live_read(text) from public;
revoke all on function public.coppari_live_update(text, text, bigint, jsonb) from public;
revoke all on function public.coppari_live_update_referee(text, text, bigint, jsonb) from public;
revoke all on function public.coppari_live_stop(text, text) from public;

grant execute on function public.coppari_live_create(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.coppari_live_read(text) to anon, authenticated;
grant execute on function public.coppari_live_update(text, text, bigint, jsonb) to anon, authenticated;
grant execute on function public.coppari_live_update_referee(text, text, bigint, jsonb) to anon, authenticated;
grant execute on function public.coppari_live_stop(text, text) to anon, authenticated;

comment on table public.coppari_live_tournaments is
  'Stato persistente delle dirette Copparì. Accesso consentito soltanto tramite RPC protette.';
