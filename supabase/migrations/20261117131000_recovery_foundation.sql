-- FS recovery v1. Additive migration: no changes to existing nutrition or training data.
create table if not exists fitness.recovery_sleep_sessions (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 source text not null check (source in ('healthkit','manual')),
 source_id text not null,
 sleep_day date not null,
 started_at timestamptz not null,
 ended_at timestamptz not null,
 timezone_id text not null,
 asleep_minutes numeric(7,2),
 awake_minutes numeric(7,2),
 rem_minutes numeric(7,2),
 deep_minutes numeric(7,2),
 core_minutes numeric(7,2),
 source_metadata jsonb not null default '{}'::jsonb,
 imported_at timestamptz not null default now(),
 constraint recovery_sleep_interval_valid check (ended_at > started_at),
 constraint recovery_sleep_duration_valid check (asleep_minutes is null or asleep_minutes between 0 and 1440),
 unique(owner_id,source,source_id)
);
create index if not exists recovery_sleep_owner_day_idx on fitness.recovery_sleep_sessions(owner_id,sleep_day desc);
create table if not exists fitness.recovery_sleep_stages (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references fitness.recovery_sleep_sessions(id) on delete cascade,
 source_id text not null,
 stage text not null check(stage in ('awake','rem','deep','core','in_bed','asleep_unspecified')),
 started_at timestamptz not null,
 ended_at timestamptz not null,
 constraint recovery_stage_interval_valid check(ended_at>started_at),
 unique(owner_id,source_id)
);
create index if not exists recovery_stages_session_idx on fitness.recovery_sleep_stages(session_id);
create table if not exists fitness.recovery_heart_metrics (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 metric_day date not null,
 metric_type text not null check(metric_type in ('sleep_hr_avg','sleep_hr_min','resting_hr','hrv_sdnn')),
 value numeric(10,3) not null check(value>0),
 unit text not null check(unit in ('bpm','ms')),
 source text not null default 'healthkit',
 source_id text not null,
 sampled_at timestamptz,
 source_metadata jsonb not null default '{}'::jsonb,
 imported_at timestamptz not null default now(),
 unique(owner_id,source,source_id)
);
create index if not exists recovery_heart_owner_day_idx on fitness.recovery_heart_metrics(owner_id,metric_day desc,metric_type);
create table if not exists fitness.recovery_daily_checkins (
 owner_id uuid not null references auth.users(id) on delete cascade,
 day date not null,
 energy smallint not null check(energy between 1 and 10),
 sleepiness smallint not null check(sleepiness between 1 and 10),
 muscle_fatigue smallint not null check(muscle_fatigue between 1 and 10),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(owner_id,day)
);
create table if not exists fitness.recovery_daily_scores (
 owner_id uuid not null references auth.users(id) on delete cascade,
 day date not null,
 algorithm_version text not null,
 score smallint check(score between 0 and 100),
 baseline_days integer not null default 0 check(baseline_days>=0),
 confidence text not null check(confidence in ('insufficient','preliminary','established')),
 factors jsonb not null default '{}'::jsonb,
 explanation jsonb not null default '{}'::jsonb,
 calculated_at timestamptz not null default now(),
 primary key(owner_id,day,algorithm_version)
);
create table if not exists fitness.recovery_sync_state (
 owner_id uuid not null references auth.users(id) on delete cascade,
 device_id text not null,
 source text not null default 'healthkit',
 cursor_data jsonb not null default '{}'::jsonb,
 last_success_at timestamptz,
 last_attempt_at timestamptz,
 last_error text,
 updated_at timestamptz not null default now(),
 primary key(owner_id,device_id,source)
);
-- Prevent stages from referencing another user's sleep session.
create unique index if not exists recovery_sleep_owner_id_idx on fitness.recovery_sleep_sessions(id,owner_id);
alter table fitness.recovery_sleep_stages add constraint recovery_stage_session_owner_fk foreign key(session_id,owner_id) references fitness.recovery_sleep_sessions(id,owner_id) on delete cascade;
-- Restrict all new medical data to authenticated owners.
alter table fitness.recovery_sleep_sessions enable row level security;
alter table fitness.recovery_sleep_stages enable row level security;
alter table fitness.recovery_heart_metrics enable row level security;
alter table fitness.recovery_daily_checkins enable row level security;
alter table fitness.recovery_daily_scores enable row level security;
alter table fitness.recovery_sync_state enable row level security;
revoke all on fitness.recovery_sleep_sessions,fitness.recovery_sleep_stages,fitness.recovery_heart_metrics,fitness.recovery_daily_checkins,fitness.recovery_daily_scores,fitness.recovery_sync_state from anon;
grant select,insert,update,delete on fitness.recovery_sleep_sessions,fitness.recovery_sleep_stages,fitness.recovery_heart_metrics,fitness.recovery_daily_checkins,fitness.recovery_daily_scores,fitness.recovery_sync_state to authenticated;
create policy recovery_sleep_owner on fitness.recovery_sleep_sessions for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy recovery_stages_owner on fitness.recovery_sleep_stages for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy recovery_heart_owner on fitness.recovery_heart_metrics for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy recovery_checkins_owner on fitness.recovery_daily_checkins for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy recovery_scores_owner on fitness.recovery_daily_scores for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy recovery_sync_owner on fitness.recovery_sync_state for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
