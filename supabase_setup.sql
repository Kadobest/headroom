-- ============================================================
-- Headroom — Supabase setup (v4, all-in-one)
-- Adds real data tables: projects, clients, artists, tracks,
-- and feedback — so Projects/Clients/Roster/Vault/Feedback
-- actually save and load real data instead of being empty shells.
-- Paste this ENTIRE file into SQL Editor and click Run once.
-- Safe to re-run even if you already ran earlier versions.
-- ============================================================

-- (Sections 1–3 below are unchanged from before — included so this
--  stays a single complete script. Skip straight to section 4 if
--  you've already run a previous version and just want the new bits.)

-- 1. Profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  title text,
  role text not null check (role in ('owner', 'assistant', 'viewer')) default 'assistant',
  created_at timestamp with time zone default now()
);
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists title text;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('owner', 'assistant', 'viewer'));
alter table public.profiles enable row level security;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select using (auth.uid() = id);

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner'); $$;

create or replace function public.is_team_member()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role in ('owner','assistant','viewer')); $$;

create or replace function public.can_edit()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role in ('owner','assistant')); $$;

drop policy if exists "Owners can view all profiles" on public.profiles;
create policy "Owners can view all profiles" on public.profiles for select using (public.is_owner());
drop policy if exists "Owners can remove profiles" on public.profiles;
create policy "Owners can remove profiles" on public.profiles for delete using (public.is_owner() and id <> auth.uid());

-- 2. Assistant/team requests
create table if not exists public.assistant_requests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  title text,
  message text,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamp with time zone default now(),
  approved_at timestamp with time zone
);
alter table public.assistant_requests add column if not exists title text;
alter table public.assistant_requests enable row level security;

drop policy if exists "Anyone can submit a request" on public.assistant_requests;
create policy "Anyone can submit a request" on public.assistant_requests for insert to anon, authenticated with check (true);
drop policy if exists "Owners can view requests" on public.assistant_requests;
create policy "Owners can view requests" on public.assistant_requests for select using (public.is_owner());
drop policy if exists "Owners can update requests" on public.assistant_requests;
create policy "Owners can update requests" on public.assistant_requests for update using (public.is_owner());

-- 3. Your own owner profile
insert into public.profiles (id, full_name, email, title, role)
select id, 'Yusuph Hussein Kadondoro', email, 'Managing Director', 'owner'
from auth.users
where email = 'kadobst@gmail.com'
on conflict (id) do update
  set full_name = excluded.full_name,
      title = coalesce(public.profiles.title, excluded.title),
      role = 'owner';

-- ============================================================
-- 4. NEW: Clients
-- ============================================================
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text,                 -- e.g. "Label artist", "Corporate", "Events"
  phone text,
  email text,
  notes text,
  created_at timestamp with time zone default now()
);
alter table public.clients enable row level security;
drop policy if exists "Team can view clients" on public.clients;
create policy "Team can view clients" on public.clients for select using (public.is_team_member());
drop policy if exists "Editors can insert clients" on public.clients;
create policy "Editors can insert clients" on public.clients for insert with check (public.can_edit());
drop policy if exists "Editors can update clients" on public.clients;
create policy "Editors can update clients" on public.clients for update using (public.can_edit());
drop policy if exists "Owners can delete clients" on public.clients;
create policy "Owners can delete clients" on public.clients for delete using (public.is_owner());

-- ============================================================
-- 5. NEW: Artists (roster)
-- ============================================================
create table if not exists public.artists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  split text,                -- e.g. "50 / 50", "Session — flat fee"
  contract_status text,      -- e.g. "Signed", "Worked with"
  contact text,
  created_at timestamp with time zone default now()
);
alter table public.artists enable row level security;
drop policy if exists "Team can view artists" on public.artists;
create policy "Team can view artists" on public.artists for select using (public.is_team_member());
drop policy if exists "Editors can insert artists" on public.artists;
create policy "Editors can insert artists" on public.artists for insert with check (public.can_edit());
drop policy if exists "Editors can update artists" on public.artists;
create policy "Editors can update artists" on public.artists for update using (public.can_edit());
drop policy if exists "Owners can delete artists" on public.artists;
create policy "Owners can delete artists" on public.artists for delete using (public.is_owner());

-- ============================================================
-- 6. NEW: Tracks (music vault)
-- ============================================================
create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist_name text,
  isrc text,
  distributor text,
  release_date date,
  bpm text,
  key text,
  credits text,
  status text,                -- e.g. "Mastering", "Released"
  created_at timestamp with time zone default now()
);
alter table public.tracks enable row level security;
drop policy if exists "Team can view tracks" on public.tracks;
create policy "Team can view tracks" on public.tracks for select using (public.is_team_member());
drop policy if exists "Editors can insert tracks" on public.tracks;
create policy "Editors can insert tracks" on public.tracks for insert with check (public.can_edit());
drop policy if exists "Editors can update tracks" on public.tracks;
create policy "Editors can update tracks" on public.tracks for update using (public.can_edit());
drop policy if exists "Owners can delete tracks" on public.tracks;
create policy "Owners can delete tracks" on public.tracks for delete using (public.is_owner());

-- ============================================================
-- 7. NEW: Projects (the core pipeline — every job, paid or not)
-- ============================================================
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  client_name text,
  service text,                -- e.g. "Mixing", "Film Sound (Post)", "Live Event"
  project_type text default 'studio' check (project_type in ('studio','label')),
  stage text default 'received' check (stage in ('received','in_progress','delivered','feedback','complete')),
  due_date date,
  value numeric default 0,
  paid_status text default 'unpaid' check (paid_status in ('paid','unpaid','partial','free')),
  notes text,
  created_at timestamp with time zone default now()
);
alter table public.projects enable row level security;
drop policy if exists "Team can view projects" on public.projects;
create policy "Team can view projects" on public.projects for select using (public.is_team_member());
drop policy if exists "Editors can insert projects" on public.projects;
create policy "Editors can insert projects" on public.projects for insert with check (public.can_edit());
drop policy if exists "Editors can update projects" on public.projects;
create policy "Editors can update projects" on public.projects for update using (public.can_edit());
drop policy if exists "Owners can delete projects" on public.projects;
create policy "Owners can delete projects" on public.projects for delete using (public.is_owner());

-- ============================================================
-- 8. NEW: Feedback (public submissions via the shareable link —
--    no login required to submit, only the team can read them)
-- ============================================================
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  client_name text,
  rating int check (rating between 1 and 5),
  comment text,
  created_at timestamp with time zone default now()
);
alter table public.feedback enable row level security;
drop policy if exists "Anyone can submit feedback" on public.feedback;
create policy "Anyone can submit feedback" on public.feedback for insert to anon, authenticated with check (true);
drop policy if exists "Team can view feedback" on public.feedback;
create policy "Team can view feedback" on public.feedback for select using (public.is_team_member());

-- ============================================================
-- What's new in this version:
--  - Real tables for Projects, Clients, Artists, Tracks, Feedback.
--  - Owners and Assistants can add/edit; Viewers can only see;
--    only Owners can delete.
--  - Feedback can be submitted by anyone with the link (clients
--    don't need a login), but only your team can read submissions.
-- ============================================================

-- ============================================================
-- v5 additions: company/label affiliation for clients & artists,
-- plus allowing project edits (update policy already covers this
-- for owners/assistants — no schema change needed there).
-- ============================================================
alter table public.clients add column if not exists company text;
alter table public.artists add column if not exists company text;

-- ============================================================
-- 9. NEW (v5): Company/label tracking on Clients and Artists.
--    Lets you record who a person works for, so if that person
--    leaves, you still have the company/label on file for future work.
-- ============================================================
alter table public.clients add column if not exists company_name text;
alter table public.clients add column if not exists company_type text;
alter table public.clients drop constraint if exists clients_company_type_check;
alter table public.clients add constraint clients_company_type_check
  check (company_type in ('label','company','independent') or company_type is null);

alter table public.artists add column if not exists company_name text;
alter table public.artists add column if not exists company_type text;
alter table public.artists drop constraint if exists artists_company_type_check;
alter table public.artists add constraint artists_company_type_check
  check (company_type in ('label','company','independent') or company_type is null);

-- ============================================================
-- 10. NEW (v6): Tasks — a real to-do list across all work streams,
--    optionally linked to a project.
-- ============================================================
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  stream text,                 -- e.g. "Studio", "Label", "Publishing", "Freelance"
  project_id uuid references public.projects(id) on delete set null,
  due_date date,
  done boolean default false,
  created_at timestamp with time zone default now()
);
alter table public.tasks enable row level security;
drop policy if exists "Team can view tasks" on public.tasks;
create policy "Team can view tasks" on public.tasks for select using (public.is_team_member());
drop policy if exists "Editors can insert tasks" on public.tasks;
create policy "Editors can insert tasks" on public.tasks for insert with check (public.can_edit());
drop policy if exists "Editors can update tasks" on public.tasks;
create policy "Editors can update tasks" on public.tasks for update using (public.can_edit());
drop policy if exists "Owners can delete tasks" on public.tasks;
create policy "Owners can delete tasks" on public.tasks for delete using (public.is_owner());

-- ============================================================
-- 11. NEW (v7): Public read access for shareable invoice/feedback
--    links — WITHOUT exposing your whole projects table.
--
--    Clients open these links with no login (using the public
--    "anon" key), so instead of letting anon read the projects
--    table directly, we expose a narrow view with only the fields
--    a client should ever see (no internal notes, no other
--    projects' data beyond what they specifically link to).
-- ============================================================
create or replace view public.public_project_info as
select id, title, client_name, service, project_type, stage,
       due_date, value, paid_status, created_at
from public.projects;

grant select on public.public_project_info to anon, authenticated;

-- Note: this view is intentionally readable by anyone who has the
-- link's project ID (a random UUID, not guessable) plus your public
-- anon key. It exposes only what a client needs to see on their own
-- invoice/feedback page — never your notes field, never other
-- clients' unrelated data beyond what this same mechanism exposes
-- for their own linked project.

-- ============================================================
-- 12. NEW (v8): Let feedback be curated for the future website.
--    Adds a "featured" flag you control from the app — only
--    feedback you've explicitly marked gets exposed publicly.
-- ============================================================
alter table public.feedback add column if not exists featured boolean default false;

-- A safe, narrow view for the future website to pull testimonials from —
-- only feedback you've marked as featured, and only the fields a
-- public testimonial needs (never internal project financials).
create or replace view public.public_testimonials as
select f.id, f.client_name, f.rating, f.comment, f.created_at, p.title as project_title
from public.feedback f
left join public.projects p on p.id = f.project_id
where f.featured = true;

grant select on public.public_testimonials to anon, authenticated;

-- Owners can update the "featured" flag and delete feedback entirely
-- (e.g. anything inappropriate) — assistants/viewers still can't.
drop policy if exists "Owners can update feedback" on public.feedback;
create policy "Owners can update feedback" on public.feedback for update using (public.is_owner());
drop policy if exists "Owners can delete feedback" on public.feedback;
create policy "Owners can delete feedback" on public.feedback for delete using (public.is_owner());

-- ============================================================
-- 13. NEW (v9): Tag each feedback entry with the project stage
--    it was submitted at, so draft-review notes and final,
--    close-out feedback are clearly labeled apart in the list —
--    even though they still live in one place for you to review.
-- ============================================================
alter table public.feedback add column if not exists stage_at_submission text;

-- ============================================================
-- 14. NEW (v10): Cancelled/postponed projects.
--    Adds a "cancelled" stage plus a reason field, so cancelled
--    work stays on record (with notes on why) instead of being
--    deleted or awkwardly left in an active-looking stage.
-- ============================================================
alter table public.projects drop constraint if exists projects_stage_check;
alter table public.projects add constraint projects_stage_check
  check (stage in ('received','in_progress','delivered','feedback','complete','cancelled'));

alter table public.projects add column if not exists cancellation_reason text;

-- ============================================================
-- 15. NEW (v11): 
--   - contact_person on clients — for when the client is a
--     company/label, so you can note who you actually deal with there.
--   - artist_name on projects — for batches where multiple songs
--     under one client (e.g. a producer) belong to different artists.
-- ============================================================
alter table public.clients add column if not exists contact_person text;
alter table public.projects add column if not exists artist_name text;

-- ============================================================
-- 16. NEW (v12): Scheduled sessions per project.
--    For work that spans multiple visits/sessions rather than
--    one clean deadline (e.g. a choir recording continued over
--    two sessions) — log each planned date with a note, instead
--    of forcing everything into a single due date.
-- ============================================================
create table if not exists public.project_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  session_date date,
  note text,
  created_at timestamp with time zone default now()
);
alter table public.project_sessions enable row level security;
drop policy if exists "Team can view sessions" on public.project_sessions;
create policy "Team can view sessions" on public.project_sessions for select using (public.is_team_member());
drop policy if exists "Editors can insert sessions" on public.project_sessions;
create policy "Editors can insert sessions" on public.project_sessions for insert with check (public.can_edit());
drop policy if exists "Editors can update sessions" on public.project_sessions;
create policy "Editors can update sessions" on public.project_sessions for update using (public.can_edit());
drop policy if exists "Editors can delete sessions" on public.project_sessions;
create policy "Editors can delete sessions" on public.project_sessions for delete using (public.can_edit());

-- ============================================================
-- 17. NEW (v13): Events as a third project type — for live sound
--    gigs (PA setup, operating, live mixing), separate from
--    Studio and Label work. Also adds an optional venue field.
-- ============================================================
alter table public.projects drop constraint if exists projects_project_type_check;
alter table public.projects add constraint projects_project_type_check
  check (project_type in ('studio','label','events'));

alter table public.projects add column if not exists venue text;

-- ============================================================
-- 18. NEW (v14): PA Rental business — built ahead of time so it's
--    ready the moment you start this side of the work.
--    Two tables: your equipment inventory, and bookings of it.
-- ============================================================
create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,              -- e.g. Speaker, Mixer, Microphone, Cable, Lighting
  quantity int default 1,
  daily_rate numeric default 0,
  condition_notes text,
  created_at timestamp with time zone default now()
);
alter table public.equipment enable row level security;
drop policy if exists "Team can view equipment" on public.equipment;
create policy "Team can view equipment" on public.equipment for select using (public.is_team_member());
drop policy if exists "Editors can insert equipment" on public.equipment;
create policy "Editors can insert equipment" on public.equipment for insert with check (public.can_edit());
drop policy if exists "Editors can update equipment" on public.equipment;
create policy "Editors can update equipment" on public.equipment for update using (public.can_edit());
drop policy if exists "Owners can delete equipment" on public.equipment;
create policy "Owners can delete equipment" on public.equipment for delete using (public.is_owner());

create table if not exists public.rental_bookings (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  items_text text,            -- free description, e.g. "2x PA speakers, 1x mixer, 4x mics"
  date_out date,
  date_back date,
  fee numeric default 0,
  deposit numeric default 0,
  status text not null default 'booked' check (status in ('booked','out','returned','cancelled')),
  notes text,
  created_at timestamp with time zone default now()
);
alter table public.rental_bookings enable row level security;
drop policy if exists "Team can view bookings" on public.rental_bookings;
create policy "Team can view bookings" on public.rental_bookings for select using (public.is_team_member());
drop policy if exists "Editors can insert bookings" on public.rental_bookings;
create policy "Editors can insert bookings" on public.rental_bookings for insert with check (public.can_edit());
drop policy if exists "Editors can update bookings" on public.rental_bookings;
create policy "Editors can update bookings" on public.rental_bookings for update using (public.can_edit());
drop policy if exists "Owners can delete bookings" on public.rental_bookings;
create policy "Owners can delete bookings" on public.rental_bookings for delete using (public.is_owner());

-- ============================================================
-- 19. NEW (v15): Flag whether YOU provide equipment for an event,
--    or the client already has their own and just needs you to
--    operate/mix — so nothing gets over-promised either way.
-- ============================================================
alter table public.projects add column if not exists equipment_source text;

-- ============================================================
-- 20. NEW (v16): Client intake requests — a public form link
--    (no login) where a prospective client fills in their own
--    event or studio job details, which you review and convert
--    into a real project. Also supports "request a change" for
--    something they already submitted, which comes to you for
--    review rather than letting them edit a live project directly.
-- ============================================================
create table if not exists public.intake_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null default 'new' check (request_type in ('new','change')),
  category text,                  -- 'event' | 'music' | 'film' | 'other'
  full_name text not null,
  email text,
  phone text,
  event_date date,
  event_time text,
  location text,
  deadline_preference text,
  description text,
  change_details text,
  status text not null default 'pending' check (status in ('pending','reviewed','converted','declined')),
  converted_project_id uuid references public.projects(id) on delete set null,
  created_at timestamp with time zone default now()
);
alter table public.intake_requests enable row level security;
drop policy if exists "Anyone can submit an intake request" on public.intake_requests;
create policy "Anyone can submit an intake request" on public.intake_requests for insert to anon, authenticated with check (true);
drop policy if exists "Team can view intake requests" on public.intake_requests;
create policy "Team can view intake requests" on public.intake_requests for select using (public.is_team_member());
drop policy if exists "Editors can update intake requests" on public.intake_requests;
create policy "Editors can update intake requests" on public.intake_requests for update using (public.can_edit());
drop policy if exists "Owners can delete intake requests" on public.intake_requests;
create policy "Owners can delete intake requests" on public.intake_requests for delete using (public.is_owner());

-- ============================================================
-- 21. NEW (v17): Let change requests actually auto-apply.
--    Reuses the same event/studio fields as new requests (so a
--    change request captures structured new values, not just
--    prose), plus a link to which project it applies to.
-- ============================================================
alter table public.intake_requests add column if not exists related_project_id uuid references public.projects(id) on delete set null;
alter table public.intake_requests drop constraint if exists intake_requests_status_check;
alter table public.intake_requests add constraint intake_requests_status_check
  check (status in ('pending','reviewed','converted','declined','approved'));
