create table if not exists public.app_leaderboard_scores (
  app_id text not null,
  scope text not null default 'default',
  player_id uuid not null,
  period text not null,
  name text not null check (char_length(name) between 1 and 16),
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  score bigint not null default 0 check (score >= 0),
  updated_at timestamptz not null default now(),
  primary key (app_id, scope, player_id, period)
);

alter table public.app_leaderboard_scores
add column if not exists scope text not null default 'default';

alter table public.app_leaderboard_scores
drop constraint if exists app_leaderboard_scores_pkey;

alter table public.app_leaderboard_scores
add primary key (app_id, scope, player_id, period);

drop index if exists app_leaderboard_unique_name_idx;
create unique index app_leaderboard_unique_name_idx
on public.app_leaderboard_scores (app_id, scope, period, lower(name));

drop index if exists app_leaderboard_ranking_idx;
create index app_leaderboard_ranking_idx
on public.app_leaderboard_scores (
  app_id,
  scope,
  period,
  score desc,
  updated_at desc
);

drop index if exists app_leaderboard_ranking_lower_idx;
create index app_leaderboard_ranking_lower_idx
on public.app_leaderboard_scores (
  app_id,
  scope,
  period,
  score asc,
  updated_at desc
);

alter table public.app_leaderboard_scores enable row level security;

drop policy if exists "leaderboard read" on public.app_leaderboard_scores;
create policy "leaderboard read"
on public.app_leaderboard_scores for select
to anon
using (true);

drop policy if exists "leaderboard insert" on public.app_leaderboard_scores;
create policy "leaderboard insert"
on public.app_leaderboard_scores for insert
to anon
with check (char_length(name) between 1 and 16 and score >= 0);

drop policy if exists "leaderboard update" on public.app_leaderboard_scores;
create policy "leaderboard update"
on public.app_leaderboard_scores for update
to anon
using (true)
with check (char_length(name) between 1 and 16 and score >= 0);

-- Optional monthly cleanup. Run manually or from Supabase Cron.
-- delete from public.app_leaderboard_scores
-- where period < to_char(now(), 'YYYY-MM');
