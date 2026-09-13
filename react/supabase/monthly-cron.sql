-- Enable Supabase Cron (pg_cron), then run after leaderboard.sql.
-- Required even though leaderboard_period also purges on access.
select cron.schedule('app-leaderboard-monthly-purge', '0 0 1 * *',
  'select public.leaderboard_purge_expired()');
