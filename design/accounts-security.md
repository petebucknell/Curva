# Accounts and security model (v3)

Status: draft for review. No code yet. Covers ENG-1 and ENG-2 in the plan.

## Why this comes first

Today every function in `supabase/schema-v2.sql` is granted to `anon`, and none of them check who is calling. Knowing a trip ID is the only access control. That is fine for a link you share with friends, but it means adding accounts alone protects nothing: anyone with the link can complete the trip or move cars.

## Decision: option A (decided by the founder)

Everyone who joins signs in with a one-time code. Option B is kept below for reference only.

Two options were considered. Both need the same database changes; they differ in who has to sign in.

- **A (the founder's direction, recommended in the plan):** everyone who joins signs in with a one-time code typed into the app. Code, not a link, because links opened from WhatsApp or Facebook open in a different browser and sign-in fails there.
- **B:** friends join by link as they do now. Only the planner signs in. Accounts are optional for friends.

The rest of this document works for either. Where they differ, it says so.

## Roles

| Role | Who | How they are identified |
|---|---|---|
| Owner | the planner who created the trip | `trips.owner_id = auth.uid()` |
| Member | someone who joined a trip (option A) | `trip_members` row with `user_id = auth.uid()` |
| Guest | someone who joined by link (option B) | the car's `guest_key` stored in their own browser |
| Legacy | trips created before this change | `trips.owner_id is null`; no owner, open by link |

## Schema changes (additive)

- `trips.owner_id uuid references auth.users` (nullable: null means legacy).
- `trip_members (trip_id uuid, user_id uuid, role text check (role in ('owner','member')), primary key (trip_id, user_id))`.
- `cars.user_id uuid references auth.users` (nullable: guest cars have none).
- `cars.guest_key uuid` (nullable, option B only): a random key the browser keeps, so a guest's own car can be recognised later.
- Row-level security stays on and gets no policies. Reads and writes still go through functions, so the rules live in one place.

## Per-function rules

Each function checks `auth.uid()` and the role above before doing anything. A failed check returns a status, never a partial change, matching the current `status` convention on the trip page.

| Function | Owner | Member (A) | Guest (B) | Anon, non-member | Legacy trip |
|---|---|---|---|---|---|
| `create_trip` | requires sign-in | requires sign-in | n/a | refused | n/a |
| `get_trip` / `trip_state` | yes | yes | yes, by trip ID | anon refused; signed-in non-member may read (the trip ID is the invite) | yes, as today |
| `join_car` | n/a | requires sign-in, adds `trip_members` | no sign-in, returns `guest_key` | refused (non-legacy) | as today |
| `mark_car` / `undo_car` | any car | own car only | own car (by `guest_key`) | refused | as today |
| `complete_trip` | yes | refused | refused | refused | as today |

Owners can act on any car on their trip, so a planner can fix a friend's count. Members can only change their own car.

## Grants

- New functions are granted to `authenticated` only, and `anon` is revoked from them.
- The legacy path keeps `anon` working for trips where `owner_id is null` until a cutover date. After cutover, legacy trips become read-only or are deleted. Cutover date is an open decision (see below).

## Client changes

- The trip page reads "my car" from the signed-in user (`cars.user_id`) when signed in, and from `localStorage` (today's `carKey`) for guests. The current `docs/trip.js` flow stays for legacy trips.
- Sign-in uses a typed one-time code in the app (option A). The `docs/api.js` helper needs to send the user's session token when there is one, not only the anon key. This is a rewrite of that helper, not a small change.

## Migration order (ENG-13)

1. Take a baseline dump of the production schema. Don't run anything else before this.
2. Apply one additive migration: new columns and tables, no grants removed, no functions dropped. Existing pages keep working.
3. Ship the new front end. It can read both legacy and new trips.
4. Only then revoke `anon` from the new rules and set the legacy cutover.

Never re-run `schema-v2.sql` on production: it drops and recreates functions.

## Tests (run on a staging project, not production)

For every function above, check each role (owner, member, guest, anon, non-member, legacy) and assert the returned `status`. Also check that:

- a member cannot complete a trip;
- a member cannot change another member's car;
- a guest's key cannot change a car it did not join;
- an anon call on a non-legacy trip is refused.

These are SQL checks run against staging. Automating them is part of the minimal CI in TODOS.md.

## Open decisions

1. Legacy cutover date, and what happens to legacy trips after it.
2. Option A is decided, so the guest questions below no longer apply. Guest keys (`cars.guest_key`) and guest rules are dropped from the build.

## Not in this document

Rate limits and abuse controls (ENG-5), payment records (ENG-8) and deletion (ENG-9) each need their own design.
