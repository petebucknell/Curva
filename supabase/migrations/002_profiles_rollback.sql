-- Curva rollback for migration 002 (profiles).
--
-- Puts get_trip, join_car and trip_state back exactly as shipped in 001_accounts.sql, and
-- drops the profile and invitation functions. The profiles table and trips.starts_on and
-- trips.ends_on stay; they are harmless and dropping them would delete data.
--
-- Run 002_profiles.sql again to go forward.

drop function if exists public.get_my_profile();
drop function if exists public.save_profile(text, text, text, text);
drop function if exists public.trip_invitation(uuid);

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

revoke all on function public.trip_state(uuid) from public, anon, authenticated;
