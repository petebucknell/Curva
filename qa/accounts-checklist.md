# Accounts QA checklist

Run against staging with `./qa/serve-staging.sh`. Case ids are what the report uses. "Planner" and "friend" are the two test accounts in `qa/credentials.local.json`. Use the viewport 1280x720 unless a case says otherwise.

## A. Signed out

| Id | Do | Expect |
|---|---|---|
| A1 | Open the home page signed out. | A sign-in panel with an Email field and an "Email me a code" button. The new-trip form is not shown. |
| A2 | Type `nope` in the Email field and click "Email me a code". | An error asking for an email address. No request is sent. |
| A3 | Open the legacy trip (`trip.html?id=<legacyTripId>`) signed out. | The trip opens normally with no sign-in prompt. Its cars list and stops show. |
| A4 | Open `trip.html` with no id. | A message that the link has no trip in it. No script errors. |
| A5 | Open `trip.html?id=00000000-0000-0000-0000-000000000000`. | A message that the trip doesn't exist. |

## B. Planner

| Id | Do | Expect |
|---|---|---|
| B1 | Sign in as planner, reload the home page. (After section F the planner has a profile; before it, the profile step comes first.) | The header shows the planner's email, a Profile button and a Sign out button. The new-trip form is shown. The sign-in panel is gone. |
| B2 | Create `QA planner trip` with stops `Stuttgart`, `Black Forest`, `Freiburg`. | A share link appears. |
| B3 | Open the share link. | The trip loads with the title, three stops, and a "Which car are you?" join section. |
| B4 | Join with the car name `QA car 1`. | The "Your car" section appears at 0 of 3. The Mark as reached button is enabled straight away, not after a refresh. |
| B5 | Click Mark as reached once. | The button reads Saving… while it works, then 1 of 3. The next stop moves on. The group list shows the progress. |
| B6 | Click Undo last check-in. | Back to 0 of 3. |
| B7 | Mark three times. | 3 of 3, and a message that the car reached the last stop. A fourth Mark is not possible. |
| B8 | Click Complete trip (after `window.confirm = () => true`). | A banner says the trip is completed. Mark and Undo are disabled. |
| B9 | Reload the page. | Still signed in, still completed. |
| B10 | Click Sign out. | The header account area empties. Reloading the planner's trip link shows the sign-in prompt. |

## C. Friend

| Id | Do | Expect |
|---|---|---|
| C1 | In the friend's session (signed out), open a trip link the planner created. First create a fresh trip `QA friend trip` as planner. | An invitation card with the trip name, "Invited by" and a car count, and a sign-up button. No stops, route or master link. (See F1.) |
| C2 | Sign in as friend (`signInWithPassword`), reload. | The trip shows and the join section is offered. |
| C3 | Join as `QA car 2`, then mark once. | 1 of 3 for the friend's car. |
| C4 | Join again from the same account with a different name. | No second car appears. The friend keeps the same car. |
| C5 | As planner, reload the trip. | The group shows the friend's car and its progress. |
| C6 | As friend, click Complete trip. | A message that only the planner can complete the trip. The trip stays open. |
| C7 | As friend, run `callFunction("mark_car", {p_car: <planner car id>, p_expected: 0})` in the page. | A result whose status is `forbidden`. The planner's car does not change. |
| C8 | As planner, mark the friend's car through the same call with the right expected count. | Status `ok`. The planner can move any car. |

## D. Sessions

| Id | Do | Expect |
|---|---|---|
| D1 | In the planner's session, set `expires_at` in the `curva-session` entry of `localStorage` to a past time and reload. | The page keeps working: the session renews silently. |
| D2 | Set the `access_token` and `refresh_token` in that entry to the text `bad` and reload a private trip. | The sign-in panel appears, and the header no longer shows the old email or Sign out. No blank page, no uncaught error. |
| D3 | Sign in on a trip page, then open the home page in the same session. | Still signed in. |

## E. Safety and edges

| Id | Do | Expect |
|---|---|---|
| E1 | Create a trip named `QA <img src=x onerror=alert(1)>` with a stop `<b>bold</b>`. | The names show as plain text. No alert, no bold stop. |
| E2 | On the home page, add 50 stops, then try a 51st with the Add button. | The Add button is not disabled, and a message says a trip can have up to 50 stops. |
| E3 | Create a trip with a master route link that does not start with `https://`. | A clear error, not a crash. |
| E4 | Set the viewport to 390x844 and open the home page and a trip page. | The header wraps without overlapping. No sideways scroll. Every button is at least 40px high, including Sign out. |
| E5 | Watch the browser console through the whole run. | No uncaught errors. Report anything logged as an error. |
| E6 | On the live-site config, `signInWithPassword` must be refused. Open `docs/config.js` as served by staging and confirm the staging URL is in use. | The page talks to the staging project only. |

## F. Profiles and the invitation card

Run F2 and F3 with an account that has no profile. A profile cannot be removed from the front end, so a repeat run needs a fresh account or the profile deleted in the staging SQL editor.

| Id | Do | Expect |
|---|---|---|
| F1 | Signed out, open a trip link created by the planner. Click "Sign up to see the route and join". | The card shows the trip name as plain text, who invited them, and dates only if the trip has them. The sign-in panel appears under the card. No stops. |
| F2 | Sign in as an account with no profile and no saved name, on that trip link. | The profile step shows before the trip: Your name, Your car (optional), avatar colours and silhouettes, with a live preview. No trip details yet. |
| F3 | Leave the name empty and click Save and continue. Then enter `<b>x</b>`, a 60 character car, pick a colour and a silhouette, and save. | First an error asking for a name. Then the trip opens. The name shows as the literal text `<b>x</b>`, never bold. |
| F4 | On the trip, look at the join box. | It holds the profile's car, cut to 40 characters. Changing it and joining uses the changed name. With no car in the profile it holds the name. |
| F5 | Join, then look at the Group list. | The car shows the avatar, the car name and the person's name. The legacy trip's cars show only the car name, with no avatar. |
| F6 | Reload while signed in with a profile. | No profile step. The trip opens directly. |
| F7 | Join a trip with a profile that has a car and an avatar, then RELOAD. Click Profile in the header, look at the form, then Save without changing anything. Also try Cancel. | The form shows the saved name, car and avatar (selected). Saving unchanged keeps all three; the group avatar stays. Changing the name and saving updates the group. Cancel returns with no change. |
| F8 | Signed in as an account with no profile, open the home page. | The profile step shows and the new-trip form does not, until the profile is saved. |
| F9 | Open the legacy trip signed out, and with the staging config. | Unchanged: the trip opens, no card, no profile step, joining takes only a car name. |
| F10 | Viewport 390x844 on the card and the profile step. | No sideways scroll. Every button, swatch and silhouette is at least 40px high. |
| F11 | `profile_required` on join: with the trip open and signed in, make `join_car` return `profile_required` (profile deleted in the SQL editor), then click Join. | The profile step shows. After saving, the join runs again with the typed car name. Not testable from the front end alone. |
