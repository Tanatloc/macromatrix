-- Blokkeren in gedeelde uitdagingen, en de roadmap opgeruimd (testronde 11: SO-2, SU-12).
--
-- 1. challenge_list (zelfde handtekening, zie challenges.sql en moderation.sql) laat een deelnemer weg als een van
--    jullie twee de ander blokkeerde, in beide richtingen. Tot nu toe verdween alleen wie jij blokkeerde; wie jou
--    blokkeerde, zag jou nog in de ranglijst. Jullie blijven elk gewoon in de uitdaging; je ziet elkaar alleen niet
--    meer. Wie jou blokkeerde, merkt de app zo niet: die persoon staat er gewoon niet meer bij.
-- 2. Roadmap: een nieuwe status 'early' (in vroege toegang: klaar voor supporters, nog niet voor iedereen). Stemmen
--    kan dan niet meer, net als bij 'done'. De wekelijkse coach staat nu op 'early' in plaats van 'done'.
--    Twee ideeën die al (deels) bestaan, krijgen een scherpere uitleg: een vast schema per weekdag zit al in de app
--    (Macroschema), en een eigen uitdaging maken kan al.
--
-- Eerst toepassen in de SQL-editor. Een app zonder deze migratie werkt gewoon verder. Een oudere app kent 'early'
-- niet en toont het item als idee; stemmen geeft dan 'closed' en de app laadt de lijst opnieuw.

create or replace function public.challenge_list()
returns table (
  id uuid, template text, title text, nutrient text, rule text, amount double precision, days smallint, need smallint,
  start_day date, owner_is_me boolean, invited_by_name text,
  member uuid, member_name text, member_avatar text, member_level integer, member_accepted boolean, member_met integer, is_me boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.template, c.title, c.nutrient, c.rule, c.amount, c.days, c.need,
    c.start_day, c.owner = auth.uid(), coalesce(ip.name, ''),
    m.user_id, coalesce(p.name, ''), p.avatar, coalesce(p.level, 1), m.accepted,
    (select count(*)::integer from public.challenge_days d where d.challenge_id = c.id and d.user_id = m.user_id and d.met),
    m.user_id = auth.uid()
  from public.challenge_members mine
  join public.challenges c on c.id = mine.challenge_id
  join public.challenge_members m on m.challenge_id = c.id
  left join public.friend_profiles p on p.user_id = m.user_id
  left join public.friend_profiles ip on ip.user_id = mine.invited_by
  where mine.user_id = auth.uid() and c.start_day + c.days + 60 >= current_date
    and not exists (
      select 1 from public.user_blocks x
      where (x.blocker = auth.uid() and x.blocked = m.user_id) or (x.blocker = m.user_id and x.blocked = auth.uid())
    )
  order by c.start_day desc, c.created_at desc, m.created_at;
$$;

-- Roadmap: status 'early' erbij
alter table public.roadmap_items drop constraint if exists roadmap_items_status_check;
alter table public.roadmap_items add constraint roadmap_items_status_check
  check (status in ('idea', 'planned', 'building', 'early', 'done'));

-- roadmap_list (zelfde handtekening, zie early_access.sql): wat in vroege toegang is, staat net boven wat klaar is
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
  order by case i.status when 'building' then 0 when 'planned' then 1 when 'idea' then 2 when 'early' then 3 else 4 end,
    i.sort, i.created_at;
$$;

-- roadmap_vote (zelfde handtekening): op wat in vroege toegang of klaar is, stem je niet meer, en zulke stemmen
-- tellen niet mee voor de grens van 3
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
  if st in ('early', 'done') then
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
  where v.user_id = me and i.status not in ('early', 'done');
  if active >= 3 then
    return 'limit';
  end if;
  insert into public.roadmap_votes (item_id, user_id) values (p_item, me) on conflict do nothing;
  return 'ok';
end;
$$;

revoke all on function public.challenge_list() from public, anon;
revoke all on function public.roadmap_list() from public, anon;
revoke all on function public.roadmap_vote(uuid, boolean) from public, anon;
grant execute on function public.challenge_list() to authenticated;
grant execute on function public.roadmap_list() to authenticated;
grant execute on function public.roadmap_vote(uuid, boolean) to authenticated;

-- De coach: in vroege toegang (zet hem op 'done' zodra hij voor iedereen is)
update public.roadmap_items set status = 'early' where title_en = 'Weekly AI coach summary' and status = 'done';

-- Wat al bestaat, niet meer als nieuw idee voorstellen
update public.roadmap_items set
  title_en = 'Goals that follow your training',
  title_nl = 'Doelen die je training volgen',
  desc_en = 'More energy and carbs on the days you work out, picked up from the workouts you log or from Health Connect. '
    'A fixed plan per weekday is already in Settings under Macro schedule.',
  desc_nl = 'Meer energie en koolhydraten op de dagen dat je traint, op basis van de workouts die je logt of uit Health Connect. '
    'Een vast schema per weekdag staat al in de instellingen onder Macroschema.'
where title_en = 'Training and rest days';

update public.roadmap_items set
  title_en = 'Bigger challenges',
  title_nl = 'Grotere uitdagingen',
  desc_en = 'Challenges longer than 90 days, with more than 20 people, and team challenges where friends count together. '
    'Your own challenge with your own goal is already possible.',
  desc_nl = 'Uitdagingen langer dan 90 dagen, met meer dan 20 mensen, en teamuitdagingen waarbij vrienden samen tellen. '
    'Een eigen uitdaging met je eigen doel kan al.'
where title_en = 'Bigger and custom challenges';
