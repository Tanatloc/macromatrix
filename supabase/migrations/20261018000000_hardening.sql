-- Beveiliging (security review 2026-10-18): misbruik beperken.
-- 1. Grootte per veld: niemand kan de database vullen met enorme rijen.
-- 2. Hoogstens 50.000 rijen per gebruiker per tabel (ruim genoeg voor tientallen jaren loggen).
-- 3. are_friends alleen voor jezelf, zodat je niet kunt navragen of twee anderen bevriend zijn.
-- 4. Battlepunten hoogstens 7 x 100 (een week van perfecte dagen).
-- NOT VALID: bestaande rijen worden niet opnieuw gecontroleerd, nieuwe en gewijzigde wel.

alter table public.settings add constraint settings_size check (char_length(key) <= 100 and char_length(value) <= 300000) not valid;
alter table public.foods add constraint foods_size check (
  char_length(id) <= 200 and char_length(name) <= 500 and coalesce(char_length(brand), 0) <= 300 and coalesce(char_length(barcode), 0) <= 64
  and coalesce(char_length(source), 0) <= 40 and char_length(nutrients) <= 30000 and coalesce(char_length(portions), 0) <= 30000
  and coalesce(char_length(extra), 0) <= 300000) not valid;
alter table public.diary add constraint diary_size check (
  char_length(id) <= 100 and char_length(day) <= 20 and char_length(food_ref) <= 200 and char_length(name) <= 500
  and coalesce(char_length(brand), 0) <= 300 and char_length(nutrients) <= 30000 and coalesce(char_length(portion_label), 0) <= 200
  and coalesce(char_length(repeat_id), 0) <= 100 and coalesce(char_length(time), 0) <= 10) not valid;
alter table public.meals add constraint meals_size check (char_length(id) <= 100 and char_length(name) <= 300 and char_length(items) <= 300000) not valid;
alter table public.notes add constraint notes_size check (char_length(day) <= 20 and char_length(text) <= 20000) not valid;
alter table public.biometrics add constraint biometrics_size check (
  char_length(id) <= 100 and char_length(day) <= 20 and char_length(type) <= 120 and coalesce(char_length(time), 0) <= 10) not valid;
alter table public.exercise add constraint exercise_size check (char_length(id) <= 100 and char_length(day) <= 20 and char_length(name) <= 300) not valid;
alter table public.fasts add constraint fasts_size check (char_length(id) <= 100) not valid;
alter table public.repeats add constraint repeats_size check (char_length(id) <= 100 and char_length(item) <= 30000 and coalesce(char_length(start_day), 0) <= 20) not valid;

-- Rijen per gebruiker begrenzen
create or replace function public.limit_rows() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare n bigint;
begin
  execute format('select count(*) from public.%I where user_id = $1', tg_table_name) into n using new.user_id;
  if n >= 50000 then
    raise exception 'te veel rijen in %', tg_table_name using errcode = '54000';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_rows() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['settings','foods','diary','meals','biometrics','notes','exercise','fasts','repeats'] loop
    execute format('drop trigger if exists limit_rows on public.%I', t);
    execute format('create trigger limit_rows before insert on public.%I for each row execute function public.limit_rows()', t);
  end loop;
end $$;

-- are_friends: alleen vragen over jezelf
create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) in (a, b) and exists (
    select 1 from public.friendships f
    where f.accepted and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a))
  );
$$;

-- Battlepunten: een week heeft hoogstens 7 dagen van 100
alter table public.weekly_scores add constraint weekly_points_max check ((points is null or points <= 700) and (mid_points is null or mid_points <= 700)) not valid;
