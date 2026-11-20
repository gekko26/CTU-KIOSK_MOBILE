# Admin login setup

The app has a staff-only login screen. There is no sign-up in the app:
only the administrator creates accounts, in the Supabase dashboard.

Do these steps in the **new** Supabase project (the same one the kiosk syncs to).

## 1. Turn off public sign-ups
Authentication → Sign In / Providers (or Settings) → turn **off**
"Allow new users to sign up". Keep the **Email** provider enabled.

Without this, someone could create an account directly through the API with
the publishable key, even though the app has no sign-up button.

## 2. Create a staff account
Authentication → Users → **Add user** → **Create new user**
- Enter the email and a password
- Tick **Auto Confirm User**

Repeat for each person. To remove someone: open the user → **Delete user**
(or **Ban**). They are signed out the next time their session refreshes (within about an hour).

## 3. Lock the tables (RLS)
SQL Editor → paste `supabase/001_mobile_auth_rls.sql` → Run.
The last query should show `rowsecurity = true` for all three tables.

- The kiosk on the Pi is not affected: it uses the `sb_secret_` key, which bypasses RLS.
- The app must use the **publishable** key (`sb_publishable_...`), never the secret key.

## 4. Test
1. Install the new APK → you should see the login screen after the splash.
2. Wrong password → "Wrong email or password."
3. Correct login → Dashboard loads data.
4. Close and reopen the app → you stay signed in.
5. Account icon (top right of Dashboard) → Sign out → back to login.
