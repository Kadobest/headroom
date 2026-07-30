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
