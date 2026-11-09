# TODOS

Deferred items collected by the review pipeline (CEO, DX, Eng). Nothing here is scheduled.

## From strategy review
- Decide payment timing and price, the free versus paid line, per-device limits, adoption target, the [X] km threshold and review turnaround hours.
- Choose the moat; decide guest-join versus friend accounts; decide the demand-before-build gate.

## From developer-experience review
- README, CLAUDE.md, numbered migrations, seed data, staging project, config.example.js, constants file (DX-1 to DX-10).

## From engineering review
- Security model v3, generation job table, spend ledger, abuse controls, data model and state machines (ENG-1 to ENG-16).
- Gitignore docs/config.js or generate it at deploy time; add a pre-commit secret scan.
- Measure the 15 s poll (docs/trip.js:1): back off when idle, add a cheap version check, set a request budget.
- Define the road-section algorithm and store its version with each QA record; pin the routing provider version.
- Define a CSV format and import script for reviewer verdicts.
- Name the data processors (LLM, routing, email, payments) in the privacy notice; choose an EU Supabase region.
- Fix stale error text in docs/api.js ("web/config.js"). (Done in b7e3f0b.)

## Accounts rollout (as of 2026-11-09)

Done: design (design/accounts-security.md), migration 001 applied to staging and to the live project, rollback tested on staging, live baseline in supabase/baseline-live-2026-11-09.csv, sign-in front end built and tested on staging, off by default.

Still to do, in order:
1. Set up real email sending (own domain, custom SMTP) on staging and live. Without it, Supabase's default sender is rate-limited and its email templates cannot be edited to include the sign-in code.
2. Edit the Magic Link and Confirm signup templates to include `{{ .Token }}` so the typed code works. The sign-in link already works, but not from WhatsApp or Facebook in-app browsers.
3. Add the live site URL to Auth redirect URLs, and test the second-member flow with a second real address (join, mark own car, cannot mark another's, only the planner completes).
4. Hide the Complete trip button for people who are not the planner (needs get_trip to say who the caller is), and show who owns the trip.
5. Merge the front-end branch, set `requireSignIn` to true on the live config, and check on a real phone.
6. Cutover: refuse anonymous trip creation, and decide what happens to old link-only trips.
7. Close the open decision on the legacy cutover date.

