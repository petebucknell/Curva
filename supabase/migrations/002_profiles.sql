-- Curva migration 002: profiles and the invitation card (core flows D7 to D9).
--
-- RUN ON STAGING FIRST. Needs 001_accounts.sql. Do not run on production until the front end
-- handles the new status below, or signed-in people without a profile lose their owned trips.
--
-- What it does:
--   * Adds public.profiles: one per account, a display name (required), an optional car and
--     an optional preset avatar (a colour key and a shape key). The preset list lives in the
--     front end, so presets can change without a migration.
--   * Adds optional trips.starts_on and trips.ends_on, shown on the invitation card.
--   * trip_invitation: what a signed-out friend sees before signing up. No route, no stops.
--   * get_trip and join_car: on an owned trip, a signed-in caller with no profile is asked to
--     make one first. Legacy trips and signed-out callers behave as before.
--   * trip_state: each car carries the person behind it (name and avatar), never their id.
--
-- New status the front end must handle before this goes to production:
--   profile_required  the caller is signed in but has not made a profile yet
--
-- Rollback: run supabase/migrations/002_profiles_rollback.sql. It restores the 001 bodies and
-- drops the new functions. The profiles table and the date columns stay; they are harmless.
--
-- Verify: run supabase/tests/profiles.sql, then supabase/tests/accounts-roles.sql, on staging.
-- Every row should say PASS.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  car_text text check (char_length(car_text) between 1 and 60),
  avatar_colour text check (avatar_colour ~ '^[a-z0-9_-]{1,24}$'),
  avatar_shape text check (avatar_shape ~ '^[a-z0-9_-]{1,24}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- No row policies: visitors reach profiles only through the functions below.
alter table public.profiles enable row level security;

alter table public.trips add column if not exists starts_on date;
alter table public.trips add column if not exists ends_on date;
alter table public.trips drop constraint if exists trips_dates_order;
alter table public.trips add constraint trips_dates_order
  check (starts_on is null or ends_on is null or ends_on >= starts_on);

-- Trip plus its cars, in the order they joined. Returns null for an unknown trip.
-- owner_id and user_id are left out so account ids never reach other people's phones.
-- person is the car's profile (name and avatar), or null for a legacy car or no profile.
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
      (select jsonb_agg(
         (to_jsonb(c) - 'user_id') || jsonb_build_object('person',
           case when p.user_id is null then null else jsonb_build_object(
             'name', p.display_name,
             'avatar_colour', p.avatar_colour,
             'avatar_shape', p.avatar_shape
           ) end)
         order by c.created_at)
       from public.cars c
       left join public.profiles p on p.user_id = c.user_id
       where c.trip_id = t.id),
      '[]'::jsonb
    )
  )
  from public.trips t
  where t.id = p_trip;
$$;

-- The caller's own profile, without their account id. Null if they have not made one.
create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(p) - 'user_id' from public.profiles p where p.user_id = auth.uid();
$$;

-- Makes or updates the caller's profile. Empty car and avatar values are stored as null.
-- The name is stored as typed (trimmed); pages must show it as text, never as markup.
create or replace function public.save_profile(p_name text, p_car text, p_avatar_colour text, p_avatar_shape text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := btrim(coalesce(p_name, ''));
  clean_car text := nullif(btrim(coalesce(p_car, '')), '');
  clean_colour text := nullif(btrim(coalesce(p_avatar_colour, '')), '');
  clean_shape text := nullif(btrim(coalesce(p_avatar_shape, '')), '');
  saved public.profiles;
begin
  if auth.uid() is null then
    return jsonb_build_object('status', 'sign_in_required');
  end if;
  if char_length(clean_name) not between 1 and 40 then
    raise exception 'name must be 1 to 40 characters';
  end if;
  if char_length(clean_car) > 60 then
    raise exception 'car must be up to 60 characters';
  end if;
  if clean_colour !~ '^[a-z0-9_-]{1,24}$' or clean_shape !~ '^[a-z0-9_-]{1,24}$' then
    raise exception 'avatar must be one of the presets';
  end if;

  insert into public.profiles (user_id, display_name, car_text, avatar_colour, avatar_shape)
  values (auth.uid(), clean_name, clean_car, clean_colour, clean_shape)
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    car_text = excluded.car_text,
    avatar_colour = excluded.avatar_colour,
    avatar_shape = excluded.avatar_shape,
    updated_at = now()
  returning * into saved;

  return jsonb_build_object('status', 'ok', 'profile', to_jsonb(saved) - 'user_id');
end;
$$;

-- The invitation card a friend sees before signing up. Anyone with the trip's id may call it.
-- Only these fields, never the stops, route, master link, cars, account ids or emails.
create or replace function public.trip_invitation(p_trip uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object(
       'status', 'ok',
       'trip_name', t.name,
       'invited_by', coalesce(p.display_name, 'the planner'),
       'starts_on', t.starts_on,
       'ends_on', t.ends_on,
       'car_count', (select count(*) from public.cars c where c.trip_id = t.id)
     )
     from public.trips t
     left join public.profiles p on p.user_id = t.owner_id
     where t.id = p_trip),
    jsonb_build_object('status', 'not_found')
  );
$$;

-- Legacy trips: open, as before. Other trips: any signed-in person with a profile who has the
-- id may read (the id is the invite). Anonymous callers are refused.
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
  if access <> 'legacy' and not exists (select 1 from public.profiles where user_id = auth.uid()) then
    return jsonb_build_object('status', 'profile_required');
  end if;
  return public.trip_state(p_id);
end;
$$;

-- Legacy trips: a car with a name, as before. Other trips: sign-in and a profile required; the
-- caller becomes a member and gets one car. Joining again returns the same car.
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

  if not exists (select 1 from public.profiles where user_id = auth.uid()) then
    return jsonb_build_object('status', 'profile_required');
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

-- trip_state stays internal. Profiles are for signed-in people; the invitation is for anyone.
revoke all on function public.trip_state(uuid) from public, anon, authenticated;
revoke all on function public.get_my_profile() from public, anon, authenticated;
revoke all on function public.save_profile(text, text, text, text) from public, anon, authenticated;
revoke all on function public.trip_invitation(uuid) from public, anon, authenticated;

grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.save_profile(text, text, text, text) to authenticated;
grant execute on function public.trip_invitation(uuid) to anon, authenticated;
