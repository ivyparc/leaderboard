create table if not exists public.app_leaderboard_scores (
  app_id text not null,
  scope text not null default 'default',
  player_id uuid not null,
  period text not null,
  name text not null check (char_length(name) between 1 and 32),
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
with check (char_length(name) between 1 and 32 and score >= 0);

drop policy if exists "leaderboard update" on public.app_leaderboard_scores;
create policy "leaderboard update"
on public.app_leaderboard_scores for update
to anon
using (true)
with check (char_length(name) between 1 and 32 and score >= 0);


-- Existing installations also need the expanded name constraint.
alter table public.app_leaderboard_scores drop constraint if exists app_leaderboard_scores_name_check;
alter table public.app_leaderboard_scores add constraint app_leaderboard_scores_name_check
  check (char_length(name) between 1 and 32);

create table if not exists public.app_leaderboard_boards (
  app_id text not null, scope text not null, period text not null,
  reset_at timestamptz, primary key (app_id, scope)
);
create table if not exists public.app_leaderboard_names (
  app_id text not null, scope text not null, player_id uuid not null,
  name text not null check (char_length(name) between 1 and 32),
  primary key (app_id, scope, player_id)
);
create unique index if not exists app_leaderboard_reserved_name_idx
  on public.app_leaderboard_names(app_id, scope, lower(name));
alter table public.app_leaderboard_boards enable row level security;
alter table public.app_leaderboard_names enable row level security;

-- Reserve historical names, newest first. Historical collisions are resolved
-- when the affected player next requests a name; score history is retained.
do $$
declare r record;
begin
  for r in select * from public.app_leaderboard_scores order by updated_at desc loop
    insert into public.app_leaderboard_names values(r.app_id,r.scope,r.player_id,r.name)
      on conflict do nothing;
  end loop;
end $$;

create or replace function public.leaderboard_period(p_app_id text, p_scope text)
returns text language plpgsql security definer set search_path = public as $$
declare b public.app_leaderboard_boards; m text := to_char(now() at time zone 'UTC','YYYY-MM');
begin
  insert into public.app_leaderboard_boards(app_id,scope,period)
    values(p_app_id,p_scope,coalesce((select max(period) from public.app_leaderboard_scores
      where app_id=p_app_id and scope=p_scope),m)) on conflict do nothing;
  select * into b from public.app_leaderboard_boards
    where app_id=p_app_id and scope=p_scope for update;
  if b.reset_at is not null and now() >= b.reset_at then
    update public.app_leaderboard_boards set period=m,reset_at=null
      where app_id=p_app_id and scope=p_scope returning * into b;
  end if;
  if b.reset_at is null and (select count(*) from public.app_leaderboard_scores
      where app_id=p_app_id and scope=p_scope and period=b.period)>1000 then
    update public.app_leaderboard_boards
      set reset_at=(date_trunc('month',now() at time zone 'UTC')+interval '1 month') at time zone 'UTC'
      where app_id=p_app_id and scope=p_scope;
  end if;
  return b.period;
end $$;

create or replace function public.leaderboard_name(p_app_id text,p_scope text,p_player_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare candidate text; words_a text[] := array['Amber','Aqua','Azure','Beige','Black','Blue','Bronze','Brown','Coral','Cream','Crimson','Cyan','Emerald','Gold','Gray','Green','Indigo','Ivory','Jade','Lilac','Lime','Mint','Navy','Ochre','Olive','Orange','Peach','Pink','Plum','Purple','Red','Ruby','Scarlet','Silver','Teal','Violet','White','Yellow','Amethyst','Apricot','Burgundy','Cerulean','Charcoal','Cobalt','Copper','Denim','Fuchsia','Graphite','Khaki','Lemon','Mauve','Mustard','Onyx','Pearl','Rosewood','Rust','Saffron','Salmon','Sand','Sepia','Sky','Slate','Snow','Steel','Tan','Topaz','Turquoise','Vermilion','Sunny','Cloudy','Misty','Windy','Stormy','Frosty','Rainy','Breezy','Brave','Calm','Clever','Gentle','Happy','Jolly','Kind','Lucky','Merry','Noble','Quiet','Swift','Rapid','Turbo','Zippy','Mighty','Bold','Agile','Bright','Glowing','Shiny','Lunar','Solar','Stellar','Dawn','Dusk','Tiny','Little','Grand','Cozy','Wild']; words_b text[] := array['Alpaca','Badger','Bear','Beaver','Bee','Bison','Camel','Cat','Crane','Deer','Dolphin','Eagle','Falcon','Finch','Fox','Frog','Gecko','Heron','Horse','Jaguar','Koala','Lion','Lynx','Moose','Otter','Owl','Panda','Parrot','Penguin','Rabbit','Raven','Robin','Seal','Shark','Sloth','Sparrow','Swan','Tiger','Turtle','Whale','Wolf','Wombat','Zebra','Aloe','Bamboo','Birch','Cactus','Cedar','Cherry','Clover','Daisy','Fern','Hazel','Holly','Iris','Ivy','Lotus','Maple','Moss','Oak','Orchid','Palm','Peony','Pine','Poppy','Reed','Sage','Spruce','Tulip','Willow','Ant','Bat','Boar','Buffalo','Cobra','Cougar','Coyote','Crow','Dove','Duck','Ferret','Gazelle','Goat','Goose','Hawk','Hippo','Hyena','Ibex','Lizard','Llama','Mantis','Mole','Moth','Newt','Orca','Osprey','Ox','Pelican','Puma','Quail','Raccoon','Ram','Skunk','Snail','Stork','Toucan','Viper','Walrus','Weasel','Yak','Ash','Aster','Azalea','Basil','Beech','Dahlia','Elm','Fennel','Fir','Ginkgo','Grape','Heather','Laurel','Marigold','Myrtle','Nettle','Rowan','Thyme','Yarrow','Yucca','Comet','Cosmos','Galaxy','Meteor','Moon','Nova','Orbit','Planet','Star','Sun','Breeze','Brook','Canyon','Cliff','Cloud','Coast','Creek','Dune','Flame','Frost','Glacier','Hill','Island','Lake','Ocean','Peak','River','Stone','Valley','Wave','Agate','Crystal','Flint','Marble','Opal','Pebble','Quartz','Beacon','Bell','Bridge','Compass','Engine','Lantern','Metro','Rail','Rocket','Signal','Station','Tunnel','Echo','Melody','Rhythm','Spark','Spirit'];
begin
  perform public.leaderboard_period(p_app_id,p_scope);
  select name into candidate from public.app_leaderboard_names
    where app_id=p_app_id and scope=p_scope and player_id=p_player_id;
  if found then return candidate; end if;
  for attempt in 1..10000 loop
    candidate := words_a[1+floor(random()*array_length(words_a,1))::int]
      || words_b[1+floor(random()*array_length(words_b,1))::int]
      || lpad(floor(random()*100)::int::text,2,'0');
    if exists(select 1 from public.app_leaderboard_names
      where app_id=p_app_id and scope=p_scope and lower(name)=lower(candidate)) then continue; end if;
    begin
      insert into public.app_leaderboard_names values(p_app_id,p_scope,p_player_id,candidate);
      return candidate;
    exception when unique_violation then
      select name into candidate from public.app_leaderboard_names
        where app_id=p_app_id and scope=p_scope and player_id=p_player_id;
      if found then return candidate; end if;
    end;
  end loop;
  raise exception 'Could not reserve a unique username';
end $$;

create or replace function public.leaderboard_prepare_score()
returns trigger language plpgsql security definer set search_path = public as $$
declare active_period text;
begin
  active_period := public.leaderboard_period(new.app_id,new.scope);
  if new.period <> active_period then
    raise exception 'Ranking period changed; refresh before submitting';
  end if;
  insert into public.app_leaderboard_names values(new.app_id,new.scope,new.player_id,new.name)
    on conflict(app_id,scope,player_id) do update set name=excluded.name;
  return new;
end $$;
create or replace function public.leaderboard_schedule_reset()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.leaderboard_period(new.app_id,new.scope);
  return new;
end $$;
drop trigger if exists leaderboard_prepare_score on public.app_leaderboard_scores;
create trigger leaderboard_prepare_score before insert or update on public.app_leaderboard_scores
  for each row execute function public.leaderboard_prepare_score();
drop trigger if exists leaderboard_schedule_reset on public.app_leaderboard_scores;
create trigger leaderboard_schedule_reset after insert on public.app_leaderboard_scores
  for each row execute function public.leaderboard_schedule_reset();

revoke all on function public.leaderboard_period(text,text) from public;
revoke all on function public.leaderboard_name(text,text,uuid) from public;
grant execute on function public.leaderboard_period(text,text) to anon,authenticated,service_role;
grant execute on function public.leaderboard_name(text,text,uuid) to anon,authenticated,service_role;
