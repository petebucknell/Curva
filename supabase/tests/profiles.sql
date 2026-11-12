-- Tests for supabase/migrations/002_profiles.sql.
--
-- RUN ON STAGING ONLY. Paste into the SQL Editor of the curva-staging project and click Run.
-- It makes temporary test users and trips, checks profiles and the invitation card, then
-- deletes them. The last result is a table: every row should say PASS.
-- Then run supabase/tests/accounts-roles.sql: its rows should still all say PASS.
-- People: A = trip owner with a profile, B = friend who makes a profile during the test,
-- C = signed in with no profile, anon = not signed in.

delete from public.trips where name like 'ZZ-TEST%';
delete from auth.users where email like 'zz-test-%@example.invalid';

drop table if exists t_results;
create temp table t_results (n serial, result text, rule text, detail text);

do $$
declare
  ua uuid := gen_random_uuid();
  ub uuid := gen_random_uuid();
  uc uuid := gen_random_uuid();
  legacy uuid; t uuid; t2 uuid;
  r jsonb; r2 jsonb; r3 jsonb;
  n integer; keys text; car_a jsonb; car_b jsonb;
  claims_anon text := '{"role":"anon"}';
  claims_a text; claims_b text; claims_c text;
begin
  claims_a := format('{"sub":"%s","role":"authenticated"}', ua);
  claims_b := format('{"sub":"%s","role":"authenticated"}', ub);
  claims_c := format('{"sub":"%s","role":"authenticated"}', uc);

  insert into auth.users (id, aud, role, email) values
    (ua, 'authenticated', 'authenticated', 'zz-test-pa@example.invalid'),
    (ub, 'authenticated', 'authenticated', 'zz-test-pb@example.invalid'),
    (uc, 'authenticated', 'authenticated', 'zz-test-pc@example.invalid');

  -- 1. A makes a profile (trimmed, no account id returned) and an owned trip, and joins it.
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r := public.save_profile('  Ann  ', 'E30 M3', 'red', 'coupe');
  t := public.create_trip('ZZ-TEST owned', '["Stuttgart","Black Forest","Freiburg"]'::jsonb, 'https://example.com/route');
  r2 := public.join_car(t, 'A car');
  reset role;
  update public.trips set starts_on = '2027-05-01', ends_on = '2027-05-03' where id = t;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'ok' and r -> 'profile' ->> 'display_name' = 'Ann'
      and not (r -> 'profile') ? 'user_id' and r2 ->> 'status' = 'ok' then 'PASS' else 'FAIL' end,
    'save_profile: trims the name, hides user_id; owner with a profile can join',
    format('status=%s name=%s join=%s', r ->> 'status', r -> 'profile' ->> 'display_name', r2 ->> 'status'));

  -- 2. The invitation card, signed out: only the allowed fields, nothing that identifies or routes.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r := public.trip_invitation(t);
  reset role;
  select string_agg(k, ',' order by k) into keys from jsonb_object_keys(r) as k;
  insert into t_results (result, rule, detail) values (
    case when keys = 'car_count,ends_on,invited_by,starts_on,status,trip_name'
      and r ->> 'status' = 'ok' and r ->> 'trip_name' = 'ZZ-TEST owned' and r ->> 'invited_by' = 'Ann'
      and r ->> 'starts_on' = '2027-05-01' and r ->> 'ends_on' = '2027-05-03' and (r ->> 'car_count')::int = 1
      and r::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-' and position('Black Forest' in r::text) = 0
      and position('example.com' in r::text) = 0 and position('@' in r::text) = 0 then 'PASS' else 'FAIL' end,
    'trip_invitation (anon): only name, inviter, dates, car count; no ids, stops, link or email',
    format('keys=%s', keys));

  -- 3. Unknown trip, and an owner with no profile.
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  t2 := public.create_trip('ZZ-TEST no profile owner', '["A","B"]'::jsonb);
  reset role;
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r := public.trip_invitation(gen_random_uuid());
  r2 := public.trip_invitation(t2);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r = '{"status":"not_found"}'::jsonb and r2 ->> 'invited_by' = 'the planner'
      and r2 ->> 'starts_on' is null then 'PASS' else 'FAIL' end,
    'trip_invitation: unknown trip is not_found; owner without profile is "the planner"',
    format('unknown=%s inviter=%s', r, r2 ->> 'invited_by'));

  -- 4. B is signed in with no profile: no trip data, and not added as a member.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.get_trip(t);
  r2 := public.join_car(t, 'B car');
  reset role;
  select count(*) into n from public.trip_members where trip_id = t and user_id = ub;
  select n + count(*) into n from public.cars where trip_id = t and user_id = ub;
  insert into t_results (result, rule, detail) values (
    case when r = '{"status":"profile_required"}'::jsonb and r2 = '{"status":"profile_required"}'::jsonb
      and n = 0 then 'PASS' else 'FAIL' end,
    'no profile: get_trip and join_car return only profile_required, nothing joined',
    format('get=%s join=%s rows=%s', r, r2, n));

  -- 5. save_profile refuses bad input and stores nothing.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  n := 0;
  begin perform public.save_profile('   ', null, null, null);
  exception when raise_exception then n := n + 1; end;
  begin perform public.save_profile(repeat('x', 41), null, null, null);
  exception when raise_exception then n := n + 1; end;
  begin perform public.save_profile('B', repeat('x', 61), null, null);
  exception when raise_exception then n := n + 1; end;
  begin perform public.save_profile('B', null, 'Red', null);
  exception when raise_exception then n := n + 1; end;
  begin perform public.save_profile('B', null, null, 'hatch back');
  exception when raise_exception then n := n + 1; end;
  reset role;
  insert into t_results (result, rule, detail) values (
    case when n = 5 and not exists (select 1 from public.profiles where user_id = ub) then 'PASS' else 'FAIL' end,
    'save_profile: refuses empty name, 41 chars, 61-char car, bad avatar keys',
    format('refused=%s of 5', n));

  -- 6. Signed out, the profile functions cannot be called at all.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  n := 0;
  begin perform public.save_profile('Anon', null, null, null);
  exception when insufficient_privilege then n := n + 1; end;
  begin perform public.get_my_profile();
  exception when insufficient_privilege then n := n + 1; end;
  reset role;
  insert into t_results (result, rule, detail) values (
    case when n = 2 and not exists (select 1 from public.profiles where display_name = 'Anon') then 'PASS' else 'FAIL' end,
    'anon: save_profile and get_my_profile refused',
    format('refused=%s of 2', n));

  -- 7. Markup in a name is stored as plain text, and only the caller's own profile comes back.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.save_profile('<b>x</b>', '', 'blue', 'hatch');
  r2 := public.get_my_profile();
  reset role;
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r3 := public.get_my_profile();
  reset role;
  insert into t_results (result, rule, detail) values (
    case when (select display_name from public.profiles where user_id = ub) = '<b>x</b>'
      and r2 ->> 'display_name' = '<b>x</b>' and r2 ->> 'car_text' is null and not r2 ? 'user_id'
      and r3 is null then 'PASS' else 'FAIL' end,
    'profile: <b>x</b> stored as typed; get_my_profile is own only (C, with none, gets null)',
    format('b_name=%s c_profile=%s', r2 ->> 'display_name', coalesce(r3::text, 'null')));

  -- 8. With a profile, B can read and join.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.get_trip(t);
  r2 := public.join_car(t, 'B car');
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r -> 'trip' ->> 'name' = 'ZZ-TEST owned' and r2 ->> 'status' = 'ok' and r2 ->> 'car_id' is not null
      then 'PASS' else 'FAIL' end,
    'with a profile: get_trip and join_car work',
    format('get=%s join=%s', r -> 'trip' ->> 'name', r2 ->> 'status'));

  -- 9. Each car carries its person, and no account id or email anywhere.
  select e.v into car_a from jsonb_array_elements(r2 -> 'cars') as e(v) where e.v ->> 'name' = 'A car';
  select e.v into car_b from jsonb_array_elements(r2 -> 'cars') as e(v) where e.v ->> 'name' = 'B car';
  insert into t_results (result, rule, detail) values (
    case when car_a -> 'person' = '{"name":"Ann","avatar_colour":"red","avatar_shape":"coupe"}'::jsonb
      and car_b -> 'person' ->> 'name' = '<b>x</b>'
      and position(ua::text in r2::text) = 0 and position(ub::text in r2::text) = 0
      and position('"user_id"' in r2::text) = 0 and position('"owner_id"' in r2::text) = 0
      and position('"email"' in r2::text) = 0 and position('@' in r2::text) = 0 then 'PASS' else 'FAIL' end,
    'trip_state: person name and avatar on each car; no user_id, owner_id or email',
    format('a_person=%s', car_a -> 'person'));

  -- 10. Legacy trips: unchanged, even for a signed-in person with no profile; legacy cars have no person.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  legacy := public.create_trip('ZZ-TEST legacy', '["A","B","C"]'::jsonb);
  r := public.join_car(legacy, 'Legacy car');
  reset role;
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r2 := public.get_trip(legacy);
  r3 := public.join_car(legacy, 'C car');
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'ok' and r -> 'cars' -> 0 -> 'person' = 'null'::jsonb
      and r2 -> 'trip' ->> 'name' = 'ZZ-TEST legacy' and r3 ->> 'status' = 'ok' then 'PASS' else 'FAIL' end,
    'legacy: anon and no-profile callers read and join as before; person is null',
    format('anon_join=%s c_get=%s c_join=%s', r ->> 'status', r2 -> 'trip' ->> 'name', r3 ->> 'status'));

  -- 11. Signed out on an owned trip: unchanged.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r := public.get_trip(t);
  r2 := public.join_car(t, 'Sneaky');
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'sign_in_required' and r2 ->> 'status' = 'sign_in_required' then 'PASS' else 'FAIL' end,
    'anon on an owned trip: still sign_in_required',
    format('get=%s join=%s', r ->> 'status', r2 ->> 'status'));

  -- 12. Trip dates must be in order.
  begin
    update public.trips set starts_on = '2027-05-03', ends_on = '2027-05-01' where id = t;
    n := 1;
  exception when check_violation then
    n := 0;
  end;
  insert into t_results (result, rule, detail) values (
    case when n = 0 then 'PASS' else 'FAIL' end,
    'trips: ends_on before starts_on is refused',
    format('accepted=%s', n = 1));

  -- 13. Nobody reads profiles directly.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  begin
    select count(*) into n from public.profiles;
  exception when insufficient_privilege then
    n := 0;
  end;
  reset role;
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  begin
    select n + count(*) into n from public.profiles;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  insert into t_results (result, rule, detail) values (
    case when n = 0 then 'PASS' else 'FAIL' end,
    'anon and authenticated cannot read profiles directly',
    format('rows_visible=%s', n));
end;
$$;

delete from public.trips where name like 'ZZ-TEST%';
delete from auth.users where email like 'zz-test-%@example.invalid';

select result, rule, detail from t_results order by n;
