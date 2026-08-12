-- ============================================================
-- Headroom — complete Supabase setup (consolidated, all versions)
-- Paste this ENTIRE file into SQL Editor and click Run once.
-- Safe to re-run any time — everything uses IF NOT EXISTS /
-- CREATE OR REPLACE, so it only adds what's missing.
-- ============================================================

-- 1. Profiles: one row per real login.
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
create policy "Users can view their own profile" on public.profiles for select using (auth.uid() = id);

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

-- Make sure your own account is set up correctly as owner.
insert into public.profiles (id, full_name, email, title, role)
select id, 'Yusuph Hussein Kadondoro', email, 'Managing Director', 'owner'
from auth.users
where email = 'kadobst@gmail.com'
on conflict (id) do update
  set full_name = excluded.full_name,
      title = coalesce(public.profiles.title, excluded.title),
      role = 'owner';

-- 2. Assistant/team requests.
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

-- 3. Clients.
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text,
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
alter table public.clients add column if not exists company_name text;
alter table public.clients add column if not exists company_type text;
alter table public.clients drop constraint if exists clients_company_type_check;
alter table public.clients add constraint clients_company_type_check
  check (company_type in ('label','company','independent') or company_type is null);
alter table public.clients add column if not exists contact_person text;

-- 4. Artists (roster).
create table if not exists public.artists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  split text,
  contract_status text,
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
alter table public.artists add column if not exists company_name text;
alter table public.artists add column if not exists company_type text;
alter table public.artists drop constraint if exists artists_company_type_check;
alter table public.artists add constraint artists_company_type_check
  check (company_type in ('label','company','independent') or company_type is null);

-- 5. Tracks (music vault).
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
  status text,
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

-- 6. Projects (the core pipeline — every job, paid or not).
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  client_name text,
  service text,
  project_type text default 'studio',
  stage text default 'received',
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

alter table public.projects drop constraint if exists projects_stage_check;
alter table public.projects add constraint projects_stage_check
  check (stage in ('received','in_progress','delivered','feedback','complete','cancelled'));
alter table public.projects add column if not exists cancellation_reason text;
alter table public.projects add column if not exists artist_name text;
alter table public.projects drop constraint if exists projects_project_type_check;
alter table public.projects add constraint projects_project_type_check
  check (project_type in ('studio','label','events'));
alter table public.projects add column if not exists venue text;
alter table public.projects add column if not exists equipment_source text;
alter table public.projects add column if not exists received_at timestamp with time zone;
alter table public.projects add column if not exists started_at timestamp with time zone;
alter table public.projects add column if not exists delivered_at timestamp with time zone;
alter table public.projects add column if not exists feedback_at timestamp with time zone;
alter table public.projects add column if not exists completed_at timestamp with time zone;

-- 7. Project sessions (for work spanning multiple visits, not one due date).
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

-- 8. Feedback (public submissions via the shareable link).
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
drop policy if exists "Owners can update feedback" on public.feedback;
create policy "Owners can update feedback" on public.feedback for update using (public.is_owner());
drop policy if exists "Owners can delete feedback" on public.feedback;
create policy "Owners can delete feedback" on public.feedback for delete using (public.is_owner());
alter table public.feedback add column if not exists featured boolean default false;
alter table public.feedback add column if not exists stage_at_submission text;

create or replace view public.public_testimonials as
select f.id, f.client_name, f.rating, f.comment, f.created_at, p.title as project_title
from public.feedback f
left join public.projects p on p.id = f.project_id
where f.featured = true;
grant select on public.public_testimonials to anon, authenticated;

-- 9. Tasks — a to-do list across all work streams, optionally linked to a project.
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  stream text,
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

-- 10. Public read access for shareable invoice/feedback links — a narrow
--     view only, never your whole projects table.
create or replace view public.public_project_info as
select id, title, client_name, service, project_type, stage,
       due_date, value, paid_status, created_at
from public.projects;
grant select on public.public_project_info to anon, authenticated;

-- 11. Equipment (PA rental inventory).
create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,
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

-- 12. Rental bookings.
create table if not exists public.rental_bookings (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  items_text text,
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

-- 13. Intake requests (public job-request form + change requests).
create table if not exists public.intake_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null default 'new' check (request_type in ('new','change')),
  category text,
  full_name text not null,
  email text,
  phone text,
  event_date date,
  event_time text,
  location text,
  deadline_preference text,
  description text,
  change_details text,
  status text not null default 'pending',
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
alter table public.intake_requests add column if not exists related_project_id uuid references public.projects(id) on delete set null;
alter table public.intake_requests drop constraint if exists intake_requests_status_check;
alter table public.intake_requests add constraint intake_requests_status_check
  check (status in ('pending','reviewed','converted','declined','approved'));

-- ============================================================
-- Done. This covers every table, column, and policy the app
-- currently expects. Safe to re-run in full any time you're
-- unsure whether something's missing.
-- ============================================================
