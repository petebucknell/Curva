# Curva

A road-trip planner and on-trip companion for car enthusiasts. The current build is a static site in `docs/` backed by Supabase. It lets a planner create a trip with a shared stop list, and lets each car follow it with its own progress.

## Run it locally

1. **Clone the repo.**
   ```
   git clone https://github.com/petebucknell/Curva.git
   cd Curva
   ```
2. **Set up a Supabase project for development.** Use a new project, not the production one. In the Supabase dashboard, open the SQL editor and run `supabase/schema.sql`, then `supabase/schema-v2.sql`. Note that `schema-v2.sql` drops and recreates some functions and columns, so only run it on a fresh project.
3. **Point the site at your project.** Open `docs/config.js` and set `url` and `anonKey` from Project Settings > API. The anon key is safe to be public. Do not put any other key under `docs/`.
4. **Serve the `docs/` folder.**
   ```
   python3 -m http.server 8080 --directory docs
   ```
5. **Open the site.** Go to http://localhost:8080, create a trip, and open its link. The trip page is `trip.html`.

**Sign-in.** `requireSignIn` in `docs/config.js` switches on email sign-in. It stays `false` on the live site until the accounts migration (`supabase/migrations/001_accounts.sql`) is on that project. On a staging project with the migration applied, set it to `true` in a local copy of `config.js`. Sign-in accepts a code or the sign-in link from the email; the code needs the email templates edited to include `{{ .Token }}`, which needs custom SMTP.

If `docs/config.js` is still set to placeholder values, the site shows an error that names the operation and the file to fix, with the code `CURVA_CONFIG_MISSING`.

## Layout

- `docs/` is the site: `index.html` and `app.js` create trips, `trip.html` and `trip.js` run the shared trip page, `auth.js` handles sign-in, `api.js` calls the database, `config.js` holds the project settings, and `style.css` holds the styles.
- `supabase/` holds the database: `schema.sql` (tables and row-level security) and `schema-v2.sql` (the functions the site calls).
- `TODOS.md` lists deferred work from the planning reviews.
- `.gstack/` is local tooling output and is git-ignored.

## Glossary

- **Stop:** a place the planner chooses.
- **Waypoint:** one Waze destination. Stops plus any points added to keep drivers on the chosen road.
- **Segment:** the road between two consecutive waypoints.
- **Road section:** one named road in a route. It may hold several segments.

## Secrets

Only the Supabase publishable (anon) key goes in `docs/`. Keys for LLM, routing, payment and email providers belong in Supabase function secrets, never in the repo.

## Verify a change

There are no automated tests yet. After a change:

1. Serve `docs/` and create a trip. Check it appears on the trip page with working Waze and Google links.
2. On the trip page, mark a car, undo it, and complete the trip. Check the progress updates.
3. For SQL changes, run them on the dev project first and check the function still returns the expected `status`.
