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
- Fix stale error text in docs/api.js ("web/config.js").
