# CLAUDE.md

Guidance for agents working in this repo. Read `README.md` for setup and the glossary.

## Layout

- `docs/`: static site served by GitHub Pages. No build step. Plain HTML, CSS and vanilla JS.
- `supabase/`: database schema and functions. Run by hand in the Supabase SQL editor.
- `TODOS.md`: deferred work. Check it before adding a feature that may already be planned.

## Rules

- Never put secrets under `docs/`. Only the publishable anon key belongs there.
- Never run SQL against the production Supabase project from a development path. Use a dev project.
- `supabase/schema-v2.sql` is not safe to re-run. It drops functions and columns. Add new migrations as new files instead of editing it.
- Use `textContent`, not `innerHTML`, for any text that comes from a user or a generator. Links go through `safeUrl` in `docs/trip.js`.
- Keep new code in the style of the surrounding file: short functions, no frameworks, no build tooling unless asked.

## Naming

- Database functions and parameters use `snake_case` with a `p_` prefix for parameters (`mark_car`, `p_car`).
- JavaScript uses `camelCase`. Constants use `UPPER_SNAKE_CASE` (`MAX_STOPS`, `REFRESH_MS`).
- Error codes use `UPPER_SNAKE_CASE` in square brackets at the end of the message (`[CURVA_CONFIG_MISSING]`).

## Glossary

Stop, waypoint, segment and road section are defined in `README.md`. Use those words exactly. Do not call a stop a waypoint in code or copy.

## How to verify

No automated tests yet. Follow the verify steps at the bottom of `README.md`. Say in your summary which steps you ran and which you did not.
