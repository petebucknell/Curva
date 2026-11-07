-- Curva: shared trip progress.
-- Run once in the Supabase dashboard: SQL Editor > New query > paste > Run.

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  stops jsonb not null,
  reached integer not null default 0 check (reached >= 0),
  reached_by text not null default '',
  reached_at timestamptz,
  created_at timestamptz not null default now()
);

-- No row policies: anonymous visitors cannot read or write the table directly.
-- Everything goes through the three functions below.
alter table public.trips enable row level security;

create or replace function public.create_trip(p_name text, p_stops jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  clean_name text := btrim(coalesce(p_name, ''));
begin
  if char_length(clean_name) not between 1 and 80 then
    raise exception 'trip name must be 1 to 80 characters';
  end if;
  if jsonb_typeof(p_stops) is distinct from 'array' then
    raise exception 'stops must be a list';
  end if;
  if jsonb_array_length(p_stops) not between 1 and 50 then
    raise exception 'a trip needs 1 to 50 stops';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_stops) as e
    where jsonb_typeof(e) <> 'string' or char_length(btrim(e #>> '{}')) not between 1 and 120
  ) then
    raise exception 'each stop must be 1 to 120 characters';
  end if;

  insert into public.trips (name, stops)
  values (clean_name, p_stops)
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.get_trip(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(t) from public.trips t where t.id = p_id;
$$;

-- Marks the next stop as reached. p_expected is the count the caller saw.
-- If someone else already moved the trip on, the call returns 'conflict'
-- with the current trip, so two phones cannot skip a stop by accident.
create or replace function public.mark_reached(p_id uuid, p_expected integer, p_who text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.trips;
begin
  select * into t from public.trips where id = p_id for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if t.reached <> p_expected then
    return jsonb_build_object('status', 'conflict', 'trip', to_jsonb(t));
  end if;
  if t.reached >= jsonb_array_length(t.stops) then
    return jsonb_build_object('status', 'finished', 'trip', to_jsonb(t));
  end if;

  update public.trips
  set reached = reached + 1,
      reached_by = left(coalesce(nullif(btrim(p_who), ''), 'Someone'), 40),
      reached_at = now()
  where id = p_id
  returning * into t;

  return jsonb_build_object('status', 'ok', 'trip', to_jsonb(t));
end;
$$;

revoke all on function public.create_trip(text, jsonb) from public;
revoke all on function public.get_trip(uuid) from public;
revoke all on function public.mark_reached(uuid, integer, text) from public;

grant execute on function public.create_trip(text, jsonb) to anon, authenticated;
grant execute on function public.get_trip(uuid) to anon, authenticated;
grant execute on function public.mark_reached(uuid, integer, text) to anon, authenticated;
