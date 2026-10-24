-- Vroege toegang en de roadmap: twee kleine extra's voor supporters (Pro).
--
-- 1. Vroege toegang (feature flags). Een nieuwe functie kan in de app achter een vlag staan (featureOn in
--    lib/sync/features.dart). Met een rij in public.features zet de beheerder ze eerst aan voor supporters
--    (early_from) en later voor iedereen (public_from). Zonder rij (of zonder deze migratie) geldt de standaard
--    die in de app staat.
-- 2. De roadmap: een korte lijst van wat er misschien komt. Iedereen met een account ziet de lijst en de stemmen;
--    alleen supporters stemmen, met hoogstens 3 stemmen tegelijk op wat nog niet klaar is. Loopt Pro af, dan blijven
--    je stemmen staan maar tellen ze niet mee: de tellers tonen wat de huidige supporters willen.
--
-- De app kan niets schrijven in features of roadmap_items (geen policies om te schrijven); de beheerder vult ze in
-- de SQL-editor (voorbeelden onderaan). Stemmen gaan alleen via roadmap_vote. Een stem is gekoppeld aan je account,
-- verdwijnt mee als je je account verwijdert, en anderen zien alleen tellers, nooit namen.
--
-- Vereist 20261026000000_pro.sql (pro_active). Een app zonder deze migratie op de server werkt gewoon: vlaggen
-- volgen hun standaard en het roadmapscherm zegt vriendelijk dat het er nog niet is.

create table public.features (
  -- Dezelfde id als in de app (knownFeatures in lib/sync/features.dart), bv. 'training_days'
  id text primary key check (id ~ '^[a-z0-9_]{1,60}$'),
  title_en text not null check (char_length(title_en) between 1 and 120),
  title_nl text not null check (char_length(title_nl) between 1 and 120),
  -- Vanaf wanneer supporters het hebben (null = geen vroege toegang)
  early_from timestamptz,
  -- Vanaf wanneer iedereen het heeft (null = nog niet voor iedereen)
  public_from timestamptz
);

create table public.roadmap_items (
  id uuid primary key default gen_random_uuid(),
  title_en text not null check (char_length(title_en) between 1 and 120),
  title_nl text not null check (char_length(title_nl) between 1 and 120),
  desc_en text not null default '' check (char_length(desc_en) <= 600),
  desc_nl text not null default '' check (char_length(desc_nl) <= 600),
  status text not null default 'idea' check (status in ('idea', 'planned', 'building', 'done')),
  sort integer not null default 100,
  created_at timestamptz not null default now()
);

create table public.roadmap_votes (
  item_id uuid not null references public.roadmap_items on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (item_id, user_id)
);

create index roadmap_votes_user on public.roadmap_votes (user_id);

alter table public.features enable row level security;
alter table public.roadmap_items enable row level security;
alter table public.roadmap_votes enable row level security;

-- Vlaggen en roadmap lezen met een account; schrijven kan niet vanuit de app. Stemmen: geen enkele directe toegang
-- (geen policies), alleen via de functies hieronder.
create policy "vlaggen lezen" on public.features for select to authenticated using (true);
create policy "roadmap lezen" on public.roadmap_items for select to authenticated using (true);
revoke insert, update, delete, truncate on public.features from public, anon, authenticated;
revoke insert, update, delete, truncate on public.roadmap_items from public, anon, authenticated;
revoke all on public.features from anon;
revoke all on public.roadmap_items from anon;
revoke all on public.roadmap_votes from public, anon, authenticated;

-- Alle vlaggen, met "enabled" = staat het nu aan voor jou: voor iedereen (public_from voorbij), of vroeg als supporter
-- (early_from voorbij en Pro loopt). "early" = zit nu in de periode van vroege toegang (nog niet voor iedereen).
-- De app rekent ook zelf met early_from en public_from, zodat een bewaard antwoord zonder internet blijft kloppen.
create or replace function public.my_features()
returns table (id text, title_en text, title_nl text, early_from timestamptz, public_from timestamptz, enabled boolean, early boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select f.id, f.title_en, f.title_nl, f.early_from, f.public_from,
    coalesce(f.public_from <= now(), false)
      or (coalesce(f.early_from <= now(), false) and public.pro_active(auth.uid())),
    coalesce(f.early_from <= now(), false) and not coalesce(f.public_from <= now(), false)
  from public.features f
  where auth.uid() is not null
  order by f.id;
$$;

-- De roadmap met per item het aantal stemmen van de huidige supporters en of jij erop stemde (ook als je Pro
-- intussen afliep: dan staat je stem er nog, maar telt ze niet mee). Eerst wat in de maak is, dan gepland, dan
-- ideeën, en wat klaar is onderaan.
create or replace function public.roadmap_list()
returns table (
  id uuid, title_en text, title_nl text, desc_en text, desc_nl text, status text, sort integer,
  votes integer, mine boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.title_en, i.title_nl, i.desc_en, i.desc_nl, i.status, i.sort,
    (select count(*)::integer from public.roadmap_votes v where v.item_id = i.id and public.pro_active(v.user_id)),
    exists (select 1 from public.roadmap_votes v where v.item_id = i.id and v.user_id = auth.uid())
  from public.roadmap_items i
  where auth.uid() is not null
  order by case i.status when 'building' then 0 when 'planned' then 1 when 'idea' then 2 else 3 end, i.sort, i.created_at;
$$;

-- Stemmen (p_on = true) of je stem terugnemen (p_on = false). Geeft terug:
--   'ok', 'not_pro' (alleen supporters stemmen), 'limit' (al 3 stemmen op wat nog niet klaar is),
--   'closed' (het item is klaar), 'not_found' (geen item met die id).
create or replace function public.roadmap_vote(p_item uuid, p_on boolean) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  st text;
  active integer;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  select i.status into st from public.roadmap_items i where i.id = p_item;
  if st is null then
    return 'not_found';
  end if;
  if st = 'done' then
    return 'closed';
  end if;
  if not public.pro_active(me) then
    return 'not_pro';
  end if;
  if not coalesce(p_on, false) then
    delete from public.roadmap_votes v where v.item_id = p_item and v.user_id = me;
    return 'ok';
  end if;
  -- Twee stemmen tegelijk mogen samen niet over de grens: per gebruiker na elkaar
  perform pg_advisory_xact_lock(hashtextextended('roadmap_vote:' || me::text, 0));
  if exists (select 1 from public.roadmap_votes v where v.item_id = p_item and v.user_id = me) then
    return 'ok';
  end if;
  select count(*) into active from public.roadmap_votes v
  join public.roadmap_items i on i.id = v.item_id
  where v.user_id = me and i.status <> 'done';
  if active >= 3 then
    return 'limit';
  end if;
  insert into public.roadmap_votes (item_id, user_id) values (p_item, me) on conflict do nothing;
  return 'ok';
end;
$$;

revoke all on function public.my_features() from public, anon;
revoke all on function public.roadmap_list() from public, anon;
revoke all on function public.roadmap_vote(uuid, boolean) from public, anon;
grant execute on function public.my_features() to authenticated;
grant execute on function public.roadmap_list() to authenticated;
grant execute on function public.roadmap_vote(uuid, boolean) to authenticated;

-- De eerste ideeën om op te stemmen
insert into public.roadmap_items (title_en, title_nl, desc_en, desc_nl, status, sort) values
  ('Training and rest days', 'Trainings- en rustdagen',
   'Different calorie and macro goals per weekday, or for the days you work out.',
   'Andere doelen voor calorieën en macro''s per weekdag, of voor de dagen dat je traint.',
   'idea', 10),
  ('Report for your dietitian or doctor', 'Rapport voor je diëtist of arts',
   'A clear PDF or CSV of a period you choose, with your intake, nutrients and weight, ready to share.',
   'Een overzichtelijke pdf of csv van een periode naar keuze, met wat je at, je voedingsstoffen en je gewicht, klaar om te delen.',
   'idea', 20),
  ('Deeper insights', 'Diepere inzichten',
   'Trends over 6 to 12 months, and links between what you eat, your weight and how your days go.',
   'Trends over 6 tot 12 maanden, en verbanden tussen wat je eet, je gewicht en hoe je dagen verlopen.',
   'idea', 30),
  ('Choose your own app icon', 'Kies je eigen app-icoon',
   'A few alternative icons for your home screen.',
   'Een paar andere icoontjes voor je startscherm.',
   'idea', 40),
  ('Bigger and custom challenges', 'Grotere en eigen uitdagingen',
   'Longer challenges, more people at once, and challenges with your own goal.',
   'Langere uitdagingen, met meer mensen tegelijk, en uitdagingen met je eigen doel.',
   'idea', 50),
  ('Weekly AI coach summary', 'Wekelijkse samenvatting van een AI-coach',
   'Every week a short, friendly summary of how it went and one or two tips for the week ahead.',
   'Elke week een korte, vriendelijke samenvatting van hoe het ging, met een of twee tips voor de week die komt.',
   'idea', 60);

-- Beheer in de SQL-editor:
--
-- Een functie in vroege toegang zetten (supporters nu, iedereen over 3 weken); de id moet gelijk zijn aan die in de app:
--   insert into public.features (id, title_en, title_nl, early_from, public_from)
--   values ('training_days', 'Training and rest days', 'Trainings- en rustdagen', now(), now() + interval '3 weeks')
--   on conflict (id) do update set early_from = excluded.early_from, public_from = excluded.public_from;
--
-- Een item op de roadmap zetten:
--   insert into public.roadmap_items (title_en, title_nl, desc_en, desc_nl, status, sort)
--   values ('Dark widgets', 'Donkere widgets', 'Home screen widgets in dark mode.', 'Widgets op je startscherm in donkere modus.', 'idea', 70);
--
-- De status van een item wijzigen (idea, planned, building, done):
--   update public.roadmap_items set status = 'building' where title_en = 'Training and rest days';
