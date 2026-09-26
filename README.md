# Our Little World

A React 19 + Vite app for a private couple space. Supabase provides password authentication, Postgres storage with row-level security, realtime chat/presence, and private object storage. The UI follows the supplied warm cream, rose and burgundy mockup with responsive desktop navigation and mobile bottom navigation.

## Run it locally

Requirements: Node.js 20.19+ and npm.

```sh
npm install
Copy-Item .env.example .env.local
# Fill in the two Supabase values in .env.local
npm run dev
```

Open the localhost address Vite prints. The app deliberately has no demo login and no local fake messages: it stays on the setup screen until the Supabase URL and publishable key are configured. Keep `.env.local` and all Supabase secret/service-role keys out of Git and out of the browser. Only the publishable/anon key belongs in `VITE_SUPABASE_PUBLISHABLE_KEY`.

## Set up the two-person private backend

1. Create a Supabase project and save its Project URL and **publishable** key in `.env.local`.
2. In Supabase, open **Authentication → Sign In / Providers → Email**. Turn **Allow new users to sign up** off and leave email confirmation on. This is an invite-only app; the React app intentionally has no sign-up screen.
3. In **Authentication → URL Configuration**, set **Site URL** to the exact app origin you are using right now. For local development use `http://localhost:5173` (Vite's default); for a deployed app use its HTTPS origin. Under **Redirect URLs**, allow `http://localhost:5173/**` and your deployed HTTPS origin (for example, `https://your-app.example.com/**`). The invite link returns to the Site URL, so a stale value such as `http://localhost:3000` will lead to a connection error. Save these settings before sending an invitation.
4. In **Authentication → Users**, choose **Add user → Send invitation** and invite only the two email addresses you and your partner will use. Open the newest invitation email on the same device/browser where the app is running, and use the link once before it expires. If Supabase reports `otp_expired` or says the link is invalid, send a fresh invitation and use that newest link; old or already-used links cannot be reused. Accept each invitation and set a password.
5. Open **SQL Editor** and run [supabase/migrations/0001_private_pair.sql](supabase/migrations/0001_private_pair.sql) once. It creates the space, member, profile, message, reaction, read receipt, and shared record tables; RLS policies; private storage; and a database trigger that refuses a third member.
6. In **Authentication → Users**, copy the two invited users' UUIDs. In SQL Editor, create your shared space and add those two members. Replace the sample values with your own:

```sql
insert into public.spaces (name, start_date)
values ('Our Little World', '2025-11-03')
returning id;
```

Copy the returned space UUID, then run:

```sql
insert into public.space_members (space_id, user_id, display_name)
values
  ('PASTE_SPACE_UUID', 'PASTE_YOUR_AUTH_USER_UUID', 'Alex'),
  ('PASTE_SPACE_UUID', 'PASTE_PARTNER_AUTH_USER_UUID', 'Jamie');
```

The database rejects a third member for that space. RLS checks membership on every database and storage operation. A signed-in account without a membership row sees no relationship content. Do not share your Supabase dashboard/admin credentials.

7. Confirm the `couple-private` storage bucket is **private** (the migration creates it that way). Keep public Realtime access disabled; the client uses private channels and membership policies. The migration adds the content tables to the `supabase_realtime` publication.
8. Start the app, sign into your invited account, edit your profile name, and check chat/media access. Then have your partner sign in with their own invited account on another device. Try that an unrelated account cannot read the space before sharing the app URL.

### What access means here

The app is restricted to the two Supabase Auth users manually enrolled in the same space. Supabase Auth verifies passwords; database RLS, not hidden UI, enforces access. Supabase-hosted storage is private and media is displayed via expiring signed URLs. Network traffic uses HTTPS when deployed. **This is not end-to-end encrypted:** the Supabase project owner and the service provider operate the backend and can technically access stored content. If you require that even the backend cannot read messages, a separately designed and reviewed end-to-end encryption/key recovery system is still needed. Never put the service-role key in this frontend.

## Build and deploy

Build the static production site locally:

```sh
npm run build
npm run preview
```

The deployable files are in `dist/`.

### Deploy with Vercel

1. Push this project to a Git repository you control.
2. In Vercel, choose **Add New → Project** and import that repository.
3. Use the Vite preset. The build command is `npm run build`; the output directory is `dist`.
4. In **Project → Settings → Environment Variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for Production (and Preview only if you want preview builds to connect to real data).
5. Deploy, copy the HTTPS domain, set it as Supabase Auth's **Site URL**, and add that exact domain to **Redirect URLs** before sending production invitations.

### Deploy with Netlify

1. Push this project to a Git repository you control and import it in Netlify.
2. Set build command to `npm run build` and publish directory to `dist`.
3. In **Site configuration → Environment variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
4. Deploy, then add the assigned HTTPS domain to Supabase Auth's allowed redirect URLs.

Vite's SPA fallback should serve `index.html` for app routes. Redeploy after changing an environment variable because Vite embeds `VITE_` values at build time. Keep the database migration in version control and back up the Supabase project.

## Send it to your partner and install it on a phone

1. Finish the Supabase setup and deploy the app. Send your partner the deployed HTTPS URL (not the `file:///...` prototype address).
2. Send their Supabase invitation to the exact email address you added as the second member. They accept the invitation, set a password, then visit your app URL and sign in. Share the site URL privately; the URL alone does not grant access.
3. The app is a Progressive Web App. On Android, open the HTTPS site in Chrome and choose **Install app** or **Add to Home screen** from the browser menu. On iPhone, open it in Safari, tap **Share**, then **Add to Home Screen**. The installed icon opens the same secure web app. Keep using the same invited login on both phone and computer.

## Included app features

- Invite-only sign-in, password reset, paired-member gate, member limit in SQL, private media storage.
- Realtime one-to-one text chat, typing/presence, read receipts, replies, edit/delete your own messages, search, reactions, pin/star flags, links, and private image/video/audio uploads and voice recording.
- Relationship dashboard and day counter, private-until-both-answer daily question, mood check-ins, love pings, saved compliments, memories, journal notes, milestone timeline, songs, Open When letters with unlock times, map-place records, collaborative bucket items, date ideas and couple prompts/games.
- Responsive desktop/mobile layouts, dark appearance, app manifest, service worker, and browser install flow.

## Current limits to understand before relying on it

- The map displays OpenStreetMap tiles and places you give it latitude/longitude for; there is no geocoding/address search. The tile provider can observe map tile requests, so don’t add sensitive locations if that metadata exposure is unacceptable.
- Shared songs store their official link and notes; playback happens on the linked music service, not inside the app.
- Couple games are lightweight shared prompts/answers, not a full multiplayer game engine with synchronized rounds, game-specific scoring, and relationship statistics.
- Browser notifications can be permission-gated while the app is open. Reliable push while it is closed needs a push provider, VAPID keys and a server/Edge Function; do not turn on that provider until you configure it.
- Data export currently downloads the relationship metadata and shared feature records. Add a server-side export/delete flow before promising full account erasure or complete media exports.
- The PWA caches the application shell only. Messaging, sign-in and media need an internet connection.
- Confirm the relationship start date and the two display names during setup. Back up the Supabase project before storing irreplaceable memories.

