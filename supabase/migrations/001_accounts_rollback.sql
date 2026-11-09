-- Curva rollback for migration 001 (accounts).
--
-- Puts the function bodies back exactly as shipped in schema-v2.sql, so every trip is open
-- by link again. Use it only while no trip has an owner: afterwards an owned trip would be
-- open to anyone with its link. The new columns and the trip_members table stay; they are
-- harmless and dropping them would delete data.
--
-- Tested on staging: run this, then supabase/migrations/001_accounts.sql again to go forward.

-- Trip plus its cars, in the order they joined. Returns null for an unknown trip.
create or replace function public.trip_state(p_trip uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'trip', to_jsonb(t),
    'cars', coalesce(
      (select jsonb_agg(to_jsonb(c) order by c.created_at) from public.cars c where c.trip_id = t.id),
      '[]'::jsonb
    )
  )
  from public.trips t
  where t.id = p_trip;
$$;

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

  insert into public.trips (name, stops, master_url)
  values (clean_name, p_stops, clean_master)
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
  select public.trip_state(p_id);
$$;

create or replace function public.join_car(p_trip uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := btrim(coalesce(p_name, ''));
  new_id uuid;
begin
  if char_length(clean_name) not between 1 and 40 then
    raise exception 'car name must be 1 to 40 characters';
  end if;
  if not exists (select 1 from public.trips where id = p_trip) then
    return jsonb_build_object('status', 'not_found');
  end if;
  if (select count(*) from public.cars where trip_id = p_trip) >= 20 then
    raise exception 'a trip can have up to 20 cars';
  end if;

  insert into public.cars (trip_id, name)
  values (p_trip, clean_name)
  returning id into new_id;

  return public.trip_state(p_trip) || jsonb_build_object('status', 'ok', 'car_id', new_id);
end;
$$;

-- Moves one car on by one stop. p_expected is the count the phone last showed for that car.
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
begin
  select * into c from public.cars where id = p_car for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
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

-- Takes back the car's latest check-in. Same expected-count guard as mark_car.
create or replace function public.undo_car(p_car uuid, p_expected integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.cars;
  finished_at timestamptz;
begin
  select * into c from public.cars where id = p_car for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
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

create or replace function public.complete_trip(p_trip uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.trips where id = p_trip) then
    return jsonb_build_object('status', 'not_found');
  end if;

  update public.trips set completed_at = coalesce(completed_at, now()) where id = p_trip;

  return public.trip_state(p_trip) || jsonb_build_object('status', 'ok');
end;
$$;

revoke all on function public.trip_state(uuid) from public, anon, authenticated;
revoke all on function public.create_trip(text, jsonb, text) from public;
revoke all on function public.get_trip(uuid) from public;
revoke all on function public.join_car(uuid, text) from public;
revoke all on function public.mark_car(uuid, integer) from public;
revoke all on function public.undo_car(uuid, integer) from public;
revoke all on function public.complete_trip(uuid) from public;

grant execute on function public.create_trip(text, jsonb, text) to anon, authenticated;
grant execute on function public.get_trip(uuid) to anon, authenticated;
grant execute on function public.join_car(uuid, text) to anon, authenticated;
grant execute on function public.mark_car(uuid, integer) to anon, authenticated;
grant execute on function public.undo_car(uuid, integer) to anon, authenticated;
grant execute on function public.complete_trip(uuid) to anon, authenticated;
