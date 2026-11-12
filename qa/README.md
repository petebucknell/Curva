# QA runs

A QA agent works through `accounts-checklist.md` against the **staging** project and reports what it finds. It does not change product code.

## For the person asking for a run

Tell the QA agent: "Run the accounts QA checklist." It needs nothing else. Before a run, make sure you are on the branch you want tested, because the test site serves whatever is checked out.

Run only before a merge, not after every change. Each run costs tokens.

## For the QA agent

### Rules

- Staging only: `https://fnkwearmthqeizkorpto.supabase.co`. Never open or call the live project (`hkhzgxzebciutavcwfvx`).
- Do not edit any file outside `qa/reports/`. Report problems; do not fix them.
- Never print or paste a password or token into your report or reply.
- Name every trip you create starting with `QA ` so it can be cleaned up.
- Say plainly what you ran and what you did not. A check you could not run is `BLOCKED`, not `PASS`.

### Setup

1. Read `qa/credentials.local.json` (it is git-ignored). It holds the staging site URL, a legacy trip id, and two test accounts: `planner` and `friend`. If it is missing, stop and tell the person to create it.
2. Start the site: run `./qa/serve-staging.sh` in a background shell and wait for `Serving ... at http://localhost:8081`. It serves the checked-out branch against staging with the test login switched on.
3. Use the Traycer browser (`repl`). Open two **isolated** sessions so the planner and the friend do not share storage: one for the planner, one for the friend.
4. To sign in as a test account, run this in that session's page, then reload:
   ```js
   await signInWithPassword("<email>", "<password>");
   ```
   It only works because the staging config turns it on.
5. The Complete trip button uses `window.confirm`. Before clicking it, run `window.confirm = () => true` in the page and say in the report that you did.
6. If a click does not register, try `element.click()` through the page and note that you did.

### Reporting

Write `qa/reports/YYYY-MM-DD-accounts.md` with:

- the branch and commit tested (`git rev-parse --short HEAD`);
- a table: case id, PASS / FAIL / BLOCKED, one line of what you saw;
- for each FAIL: exact steps, what you expected, what happened, and the exact text of any error message;
- browser console errors seen during the run;
- anything odd you noticed that is not in the checklist.

Then give a short summary in chat: counts, the worst failures, and anything blocked.

### Clean up

At the end, clear `localStorage` in both sessions. Staging trips named `QA ...` can stay. To remove them, the person runs this in the staging SQL Editor:

```sql
delete from public.trips where name like 'QA %';
```
