-- Role tests for supabase/migrations/001_accounts.sql.
--
-- RUN ON STAGING ONLY. Paste into the SQL Editor of the curva-staging project and click Run.
-- It makes temporary test users and trips, checks every role, then deletes them.
-- The last result is a table: every row should say PASS. Any FAIL names the rule that broke.
-- Roles: A = trip owner, B = member, C = signed in but not a member, anon = not signed in.

delete from public.trips where name like 'ZZ-TEST%';
delete from auth.users where email like 'zz-test-%@example.invalid';

drop table if exists t_results;
create temp table t_results (n serial, result text, rule text, detail text);

do $$
declare
  ua uuid := gen_random_uuid();
  ub uuid := gen_random_uuid();
  uc uuid := gen_random_uuid();
  legacy uuid; legacy_car uuid;
  t uuid; car_a uuid; car_b uuid; car_b_again uuid;
  r jsonb; r2 jsonb; r3 jsonb;
  n integer; owner_val uuid; role_val text;
  claims_anon text := '{"role":"anon"}';
  claims_a text; claims_b text; claims_c text;
begin
  claims_a := format('{"sub":"%s","role":"authenticated"}', ua);
  claims_b := format('{"sub":"%s","role":"authenticated"}', ub);
  claims_c := format('{"sub":"%s","role":"authenticated"}', uc);

  insert into auth.users (id, aud, role, email) values
    (ua, 'authenticated', 'authenticated', 'zz-test-a@example.invalid'),
    (ub, 'authenticated', 'authenticated', 'zz-test-b@example.invalid'),
    (uc, 'authenticated', 'authenticated', 'zz-test-c@example.invalid');

  -- 1. Legacy trips keep working with no sign-in.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  legacy := public.create_trip('ZZ-TEST legacy', '["A","B","C"]'::jsonb);
  r := public.join_car(legacy, 'Legacy car');
  legacy_car := (r ->> 'car_id')::uuid;
  r2 := public.mark_car(legacy_car, 0);
  r3 := public.complete_trip(legacy);
  reset role;
  select owner_id into owner_val from public.trips where id = legacy;
  insert into t_results (result, rule, detail) values (
    case when owner_val is null and r ->> 'status' = 'ok' and r2 ->> 'status' = 'ok' and r3 ->> 'status' = 'ok' then 'PASS' else 'FAIL' end,
    'legacy: anon can create, join, mark and complete as before',
    format('owner=%s join=%s mark=%s complete=%s', owner_val, r ->> 'status', r2 ->> 'status', r3 ->> 'status'));

  -- 2. A signed-in create makes an owned trip with an owner membership.
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  t := public.create_trip('ZZ-TEST owned', '["Stuttgart","Black Forest","Freiburg"]'::jsonb);
  reset role;
  select owner_id into owner_val from public.trips where id = t;
  select role into role_val from public.trip_members where trip_id = t and user_id = ua;
  insert into t_results (result, rule, detail) values (
    case when owner_val = ua and role_val = 'owner' then 'PASS' else 'FAIL' end,
    'signed-in create: caller becomes owner',
    format('owner_ok=%s role=%s', owner_val = ua, role_val));

  -- 3. Anonymous callers are refused on an owned trip.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r := public.get_trip(t);
  r2 := public.join_car(t, 'Sneaky');
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'sign_in_required' and r2 ->> 'status' = 'sign_in_required' then 'PASS' else 'FAIL' end,
    'anon: get_trip and join_car refused on an owned trip',
    format('get=%s join=%s', r ->> 'status', r2 ->> 'status'));

  -- 4. A signed-in non-member can read the trip, and account ids are not exposed.
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r := public.get_trip(t);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r -> 'trip' ->> 'name' = 'ZZ-TEST owned' and not (r -> 'trip') ? 'owner_id' then 'PASS' else 'FAIL' end,
    'signed-in reader sees the trip, owner_id hidden',
    format('has_owner_id=%s', (r -> 'trip') ? 'owner_id'));

  -- 5. Joining: B becomes a member with one car; joining again returns the same car.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.join_car(t, 'B car');
  car_b := (r ->> 'car_id')::uuid;
  r2 := public.join_car(t, 'B car again');
  car_b_again := (r2 ->> 'car_id')::uuid;
  reset role;
  select count(*) into n from public.cars where trip_id = t and user_id = ub;
  select role into role_val from public.trip_members where trip_id = t and user_id = ub;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'ok' and car_b = car_b_again and n = 1 and role_val = 'member'
      and not exists (select 1 from jsonb_array_elements(r -> 'cars') as e(v) where e.v ? 'user_id') then 'PASS' else 'FAIL' end,
    'member join: one car per person, repeat join returns it, user_id hidden',
    format('status=%s same_car=%s cars=%s role=%s', r ->> 'status', car_b = car_b_again, n, role_val));

  -- 6. Who may mark a car.
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r := public.mark_car(car_b, 0);
  reset role;
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r2 := public.mark_car(car_b, 0);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'forbidden' and r2 ->> 'status' = 'sign_in_required' then 'PASS' else 'FAIL' end,
    'mark_car: non-member forbidden, anon needs sign-in',
    format('non-member=%s anon=%s', r ->> 'status', r2 ->> 'status'));

  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.mark_car(car_b, 0);
  reset role;
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r2 := public.mark_car(car_b, 1);
  reset role;
  select reached into n from public.cars where id = car_b;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'ok' and r2 ->> 'status' = 'ok' and n = 2 then 'PASS' else 'FAIL' end,
    'mark_car: member moves own car, owner can move any car',
    format('member=%s owner=%s reached=%s', r ->> 'status', r2 ->> 'status', n));

  -- 7. A member cannot touch another member's car (here, the owner's).
  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r := public.join_car(t, 'A car');
  car_a := (r ->> 'car_id')::uuid;
  reset role;
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r2 := public.mark_car(car_a, 0);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r2 ->> 'status' = 'forbidden' then 'PASS' else 'FAIL' end,
    'mark_car: member cannot move someone else''s car',
    format('status=%s', r2 ->> 'status'));

  -- 8. Undo follows the same rules.
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r := public.undo_car(car_b, 2);
  reset role;
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r2 := public.undo_car(car_b, 2);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'forbidden' and r2 ->> 'status' = 'ok' then 'PASS' else 'FAIL' end,
    'undo_car: non-member forbidden, member can undo own car',
    format('non-member=%s member=%s', r ->> 'status', r2 ->> 'status'));

  -- 9. Only the owner completes an owned trip.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.complete_trip(t);
  reset role;
  perform set_config('request.jwt.claims', claims_c, true);
  set local role authenticated;
  r2 := public.complete_trip(t);
  reset role;
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  r3 := public.complete_trip(t);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'forbidden' and r2 ->> 'status' = 'forbidden' and r3 ->> 'status' = 'sign_in_required' then 'PASS' else 'FAIL' end,
    'complete_trip: member and non-member forbidden, anon needs sign-in',
    format('member=%s non-member=%s anon=%s', r ->> 'status', r2 ->> 'status', r3 ->> 'status'));

  perform set_config('request.jwt.claims', claims_a, true);
  set local role authenticated;
  r := public.complete_trip(t);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'ok' and r -> 'trip' ->> 'completed_at' is not null then 'PASS' else 'FAIL' end,
    'complete_trip: owner can complete',
    format('status=%s', r ->> 'status'));

  -- 10. A finished trip still refuses further marks, as before.
  perform set_config('request.jwt.claims', claims_b, true);
  set local role authenticated;
  r := public.mark_car(car_b, 1);
  reset role;
  insert into t_results (result, rule, detail) values (
    case when r ->> 'status' = 'completed' then 'PASS' else 'FAIL' end,
    'completed trip: mark_car returns completed',
    format('status=%s', r ->> 'status'));

  -- 11. The internal helpers and the raw tables are closed to the public roles.
  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  begin
    perform public.trip_access(t);
    n := 1;
  exception when insufficient_privilege then
    n := 0;
  end;
  begin
    perform public.trip_state(t);
    r := '{"open":true}'::jsonb;
  exception when insufficient_privilege then
    r := '{"open":false}'::jsonb;
  end;
  reset role;
  insert into t_results (result, rule, detail) values (
    case when n = 0 and r ->> 'open' = 'false' then 'PASS' else 'FAIL' end,
    'anon cannot call trip_access or trip_state directly',
    format('trip_access_open=%s trip_state_open=%s', n = 1, r ->> 'open'));

  perform set_config('request.jwt.claims', claims_anon, true);
  set local role anon;
  begin
    select count(*) into n from public.trips;
    select n + count(*) into n from public.cars;
    select n + count(*) into n from public.trip_members;
  exception when insufficient_privilege then
    n := 0;
  end;
  reset role;
  insert into t_results (result, rule, detail) values (
    case when n = 0 then 'PASS' else 'FAIL' end,
    'anon cannot read trips, cars or trip_members directly',
    format('rows_visible=%s', n));
end;
$$;

delete from public.trips where name like 'ZZ-TEST%';
delete from auth.users where email like 'zz-test-%@example.invalid';

select result, rule, detail from t_results order by n;
