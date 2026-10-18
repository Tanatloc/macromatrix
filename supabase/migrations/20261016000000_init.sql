-- MacroMatrix: tabellen voor accounts en synchronisatie.
--
-- Elke tabel heeft dezelfde kolommen als de lokale database (lib/data/user_db.dart, UserDb.syncTables), plus:
--   user_id    van wie de rij is (Row Level Security: iedereen ziet en wijzigt alleen zijn eigen rijen)
--   server_ts  klok van de server bij de laatste wijziging; toestellen halen op wat nieuwer is dan hun cursor
-- Conflicten: de laatste wijziging (updated_at, in ms) wint. Een oudere versie overschrijft nooit een nieuwere.
-- Verwijderen gebeurt "zacht" (deleted = 1), zodat andere toestellen het ook te weten komen.

-- ── Stempel en "laatste wijziging wint" ──

create or replace function public.sync_stamp() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- Een oudere versie (bv. van een toestel dat lang offline was) negeren
    if new.updated_at < old.updated_at then
      return null;
    end if;
    new.user_id := old.user_id;
  end if;
  new.server_ts := clock_timestamp();
  return new;
end;
$$;

-- ── Tabellen ──

create table public.settings (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  key text not null,
  value text not null,
  updated_at bigint not null,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, key)
);

create table public.foods (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  source text not null,
  name text not null,
  brand text,
  barcode text,
  nutrients text not null,
  portions text,
  extra text,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.diary (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  day text not null,
  meal integer not null,
  food_ref text not null,
  name text not null,
  brand text,
  grams double precision not null,
  portion_label text,
  quantity double precision not null,
  nutrients text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted integer not null default 0,
  time text,
  repeat_id text,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.meals (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  items text not null,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.biometrics (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  day text not null,
  time text,
  type text not null,
  value double precision not null,
  value2 double precision,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.notes (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day text not null,
  text text not null,
  updated_at bigint not null,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, day)
);

create table public.exercise (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  day text not null,
  name text not null,
  minutes double precision,
  kcal double precision not null,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.fasts (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  start bigint not null,
  "end" bigint,
  goal_hours double precision not null,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.repeats (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  meal integer not null,
  item text not null,
  weekdays integer not null,
  start_day text not null,
  updated_at bigint not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ── Trigger, index en beveiliging per tabel ──

do $$
declare
  t text;
begin
  foreach t in array array['settings', 'foods', 'diary', 'meals', 'biometrics', 'notes', 'exercise', 'fasts', 'repeats'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.sync_stamp()', t || '_stamp', t);
    execute format('create index %I on public.%I (user_id, server_ts)', t || '_changes', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "eigen rijen lezen" on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
    execute format('create policy "eigen rijen toevoegen" on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "eigen rijen wijzigen" on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      t
    );
    execute format('revoke all on public.%I from anon', t);
  end loop;
end;
$$;

-- ── Account verwijderen (vereist door de Play Store) ──
-- Verwijdert de gebruiker; al zijn rijen verdwijnen mee (on delete cascade).

create or replace function public.delete_account() returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
