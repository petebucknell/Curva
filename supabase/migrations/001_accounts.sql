-- Curva migration 001: accounts and trip roles (design/accounts-security.md, option A).
--
-- RUN ON STAGING FIRST. Do not run on production until the sign-in front end has shipped
-- (migrate, then ship the front end, then tighten: see "Migration order" in the design).
--
-- What it does:
--   * Adds owners, members and per-user cars. Nothing is dropped.
--   * Trips with no owner are "legacy": every function behaves exactly as before for them.
--   * Trips created by a signed-in user have an owner and follow the new rules.
--   * An anonymous create_trip still makes a legacy trip, so the live pages keep working.
--     A later migration (the cutover) will refuse anonymous creation.
--
-- New statuses the front end must handle before this goes to production:
--   sign_in_required  the caller is not signed in and the trip needs an account
--   forbidden         the caller is signed in but not allowed to do this
--
-- Rollback (only safe while no trip has an owner): restore the function bodies from
-- schema-v2.sql, then drop public.trip_members, public.trip_access, and the
-- trips.owner_id and cars.user_id columns.
--
-- Verify: run supabase/tests/accounts-roles.sql on staging. Every row should say PASS.

alter table public.trips add column if not exists owner_id uuid references auth.users (id);
alter table public.cars add column if not exists user_id uuid references auth.users (id) on delete set null;

create index if not exists trips_owner_idx on public.trips (owner_id);
-- One car per person per trip.
create unique index if not exists cars_trip_user_uniq on public.cars (trip_id, user_id) where user_id is not null;

create table if not exists public.trip_members (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- No row policies: visitors reach these tables only through the functions below.
alter table public.trip_members enable row level security;

-- Who is the caller, relative to this trip?
--   missing    no such trip
--   legacy     the trip has no owner (created before accounts); open by link, as before
--   anon       not signed in
--   owner      signed in and created the trip
--   member     signed in and joined the trip
--   signed_in  signed in, has the trip's id, has not joined
create or replace function public.trip_access(p_trip uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when t.id is null then 'missing'
    when t.owner_id is null then 'legacy'
    when auth.uid() is null then 'anon'
    when t.owner_id = auth.uid() then 'owner'
    when exists (
      select 1 from public.trip_members m where m.trip_id = t.id and m.user_id = auth.uid()
    ) then 'member'
    else 'signed_in'
  end
  from (select 1) as one
  left join public.trips t on t.id = p_trip;
$$;

-- Trip plus its cars, in the order they joined. Returns null for an unknown trip.
-- owner_id and user_id are left out so account ids never reach other people's phones.
create or replace function public.trip_state(p_trip uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'trip', to_jsonb(t) - 'owner_id',
    'cars', coalesce(
      (select jsonb_agg(to_jsonb(c) - 'user_id' order by c.created_at) from public.cars c where c.trip_id = t.id),
      '[]'::jsonb
    )
  )
  from public.trips t
  where t.id = p_trip;
$$;

-- Signed in: the caller owns the trip. Not signed in: a legacy trip, as before.
create or replace function public.create_trip(p_name text, p_stops jsonb, p_master_url text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  clean_name text := btrim(coalesce(p_name, ''));
  clean_master text := nullif(btrim(coalesce(p_master_url, '')), '');
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
  -- A stop is either a name, or an object with a name and optional waze and google links.
  if exists (
    select 1 from jsonb_array_elements(p_stops) as e
    where not (
      (jsonb_typeof(e) = 'string' and char_length(btrim(e #>> '{}')) between 1 and 120)
      or (jsonb_typeof(e) = 'object' and char_length(btrim(coalesce(e ->> 'name', ''))) between 1 and 120)
    )
  ) then
    raise exception 'each stop needs a name of 1 to 120 characters';
  end if;
  if clean_master is not null and (clean_master !~ '^https://' or char_length(clean_master) > 500) then
    raise exception 'master route must be an https link of up to 500 characters';
  end if;

  insert into public.trips (name, stops, master_url, owner_id)
  values (clean_name, p_stops, clean_master, auth.uid())
  returning id into new_id;

  if auth.uid() is not null then
    insert into public.trip_members (trip_id, user_id, role) values (new_id, auth.uid(), 'owner');
  end if;

  return new_id;
end;
$$;

-- Legacy trips: open, as before. Other trips: any signed-in person who has the id may read
-- (the id is the invite). Anonymous callers are refused.
create or replace function public.get_trip(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  access text := public.trip_access(p_id);
begin
  if access = 'missing' then
    return null;
  end if;
  if access = 'anon' then
    return jsonb_build_object('status', 'sign_in_required');
  end if;
  return public.trip_state(p_id);
end;
$$;

-- Legacy trips: a car with a name, as before. Other trips: sign-in required; the caller becomes
-- a member and gets one car. Joining again returns the same car.
create or replace function public.join_car(p_trip uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := btrim(coalesce(p_name, ''));
  new_id uuid;
  access text;
begin
  if char_length(clean_name) not between 1 and 40 then
    raise exception 'car name must be 1 to 40 characters';
  end if;

  access := public.trip_access(p_trip);
  if access = 'missing' then
    return jsonb_build_object('status', 'not_found');
  end if;
  if access = 'anon' then
    return jsonb_build_object('status', 'sign_in_required');
  end if;

  if access = 'legacy' then
    if (select count(*) from public.cars where trip_id = p_trip) >= 20 then
      raise exception 'a trip can have up to 20 cars';
    end if;
    insert into public.cars (trip_id, name)
    values (p_trip, clean_name)
    returning id into new_id;
    return public.trip_state(p_trip) || jsonb_build_object('status', 'ok', 'car_id', new_id);
  end if;

  if access = 'signed_in' then
    insert into public.trip_members (trip_id, user_id, role)
    values (p_trip, auth.uid(), 'member')
    on conflict do nothing;
  end if;

  select id into new_id from public.cars where trip_id = p_trip and user_id = auth.uid();
  if new_id is not null then
    return public.trip_state(p_trip) || jsonb_build_object('status', 'ok', 'car_id', new_id);
  end if;

  if (select count(*) from public.cars where trip_id = p_trip) >= 20 then
    raise exception 'a trip can have up to 20 cars';
  end if;

  insert into public.cars (trip_id, name, user_id)
  values (p_trip, clean_name, auth.uid())
  on conflict (trip_id, user_id) where user_id is not null do nothing
  returning id into new_id;
  if new_id is null then
    select id into new_id from public.cars where trip_id = p_trip and user_id = auth.uid();
  end if;

  return public.trip_state(p_trip) || jsonb_build_object('status', 'ok', 'car_id', new_id);
end;
$$;

-- Moves one car on by one stop. p_expected is the count the phone last showed for that car.
-- Legacy trips: anyone. Other trips: the car's own member, or the trip's owner.
create or replace function public.mark_car(p_car uuid, p_expected integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.cars;
  total integer;
  finished_at timestamptz;
  access text;
begin
  select * into c from public.cars where id = p_car for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  access := public.trip_access(c.trip_id);
  if access = 'anon' then
    return jsonb_build_object('status', 'sign_in_required');
  end if;
  if access = 'signed_in' or (access = 'member' and c.user_id is distinct from auth.uid()) then
    return jsonb_build_object('status', 'forbidden');
  end if;

  select jsonb_array_length(stops), completed_at into total, finished_at
  from public.trips where id = c.trip_id;

  if finished_at is not null then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'completed', 'car_id', c.id);
  end if;
  if c.reached <> p_expected then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'conflict', 'car_id', c.id);
  end if;
  if c.reached >= total then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'finished', 'car_id', c.id);
  end if;

  update public.cars set reached = reached + 1, checked_in_at = now() where id = p_car;

  return public.trip_state(c.trip_id) || jsonb_build_object('status', 'ok', 'car_id', p_car);
end;
$$;

-- Takes back the car's latest check-in. Same rules and expected-count guard as mark_car.
create or replace function public.undo_car(p_car uuid, p_expected integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.cars;
  finished_at timestamptz;
  access text;
begin
  select * into c from public.cars where id = p_car for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  access := public.trip_access(c.trip_id);
  if access = 'anon' then
    return jsonb_build_object('status', 'sign_in_required');
  end if;
  if access = 'signed_in' or (access = 'member' and c.user_id is distinct from auth.uid()) then
    return jsonb_build_object('status', 'forbidden');
  end if;

  select completed_at into finished_at from public.trips where id = c.trip_id;

  if finished_at is not null then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'completed', 'car_id', c.id);
  end if;
  if c.reached <> p_expected then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'conflict', 'car_id', c.id);
  end if;
  if c.reached = 0 then
    return public.trip_state(c.trip_id) || jsonb_build_object('status', 'nothing_to_undo', 'car_id', c.id);
  end if;

  update public.cars set reached = reached - 1, checked_in_at = now() where id = p_car;

  return public.trip_state(c.trip_id) || jsonb_build_object('status', 'ok', 'car_id', p_car);
end;
$$;

-- Legacy trips: anyone, as before. Other trips: the owner only.
create or replace function public.complete_trip(p_trip uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  access text := public.trip_access(p_trip);
begin
  if access = 'missing' then
    return jsonb_build_object('status', 'not_found');
  end if;
  if access = 'anon' then
    return jsonb_build_object('status', 'sign_in_required');
  end if;
  if access in ('member', 'signed_in') then
    return jsonb_build_object('status', 'forbidden');
  end if;

  update public.trips set completed_at = coalesce(completed_at, now()) where id = p_trip;

  return public.trip_state(p_trip) || jsonb_build_object('status', 'ok');
end;
$$;

-- trip_access and trip_state are internal: only the functions above call them.
revoke all on function public.trip_access(uuid) from public, anon, authenticated;
revoke all on function public.trip_state(uuid) from public, anon, authenticated;
