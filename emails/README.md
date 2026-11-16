# Email templates

On-brand sign-in emails for Supabase Auth. They are pasted into the Supabase dashboard by hand; the site does not read these files.

| File | Supabase template | Used when | Subject line |
|---|---|---|---|
| `magic-link.html` | Magic Link | An existing person signs in | `Your Curva sign-in code` |
| `confirm-signup.html` | Confirm signup | A new person signs in for the first time | `Welcome to Curva: your code` |

## How to apply (once per Supabase project: staging, then live)

1. Open the project, then **Authentication > Emails > Templates**.
2. Open **Magic Link**. Set the **Subject** from the table. Replace the whole **Message body** (source view) with the contents of `magic-link.html`. Save.
3. Open **Confirm signup** and do the same with `confirm-signup.html`. Save.
4. Send yourself a code and check the email, the code and the button.

## Rules

- Keep `{{ .Token }}` (the code) and `{{ .ConfirmationURL }}` (the one-tap link). The sign-in page needs the code.
- Email clients ignore custom fonts and most CSS, so the layout is simple tables with inline styles and safe font stacks (Georgia, Helvetica, Menlo). Do not add web fonts or external images.
- Colours are the brand: asphalt `#242624`, ivory `#f3f0e8`, limestone `#b7b1a4`, signal peach `#f2b07a`.
