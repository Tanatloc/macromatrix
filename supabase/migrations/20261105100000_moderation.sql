-- Moderatie van wat vrienden van je zien: namen en titels van uitdagingen (Google Play, gebruikersinhoud).
--
-- 1. Een eenvoudig woordfilter (public.text_blocked) voor je vriendennaam (friend_me) en de titel van een
--    uitdaging (challenge_create). Geweigerd = een fout 'name_not_allowed' of 'title_not_allowed' (code 22023),
--    die de app als vriendelijke melding toont. Het filter kijkt naar hele woorden, niet naar stukjes van woorden:
--    "Scunthorpe" of "shiitake" mag gewoon. Eerst kleine letters, accenten weg en cijfers die als letters gebruikt
--    worden (sh1t, 5hit), en drie of meer dezelfde letters na elkaar worden er één (fuuuck).
--    Dezelfde lijst staat in de app (lib/sync/name_filter.dart), voor meteen feedback; test/review_r11_test.dart
--    controleert dat beide lijsten gelijk zijn.
-- 2. Een uitdaging melden om haar titel (challenge_report): de melding komt in user_reports, met reden
--    'challenge_title', het id en de titel van de uitdaging op dat moment, tegen wie ze aanmaakte.
-- 3. challenge_list (zelfde handtekening) toont geen deelnemers meer die je geblokkeerd hebt.
--
-- Bestaande namen en titels blijven staan; het filter werkt bij een nieuwe naam of een nieuwe uitdaging.
-- Eerst toepassen in de SQL-editor; een app zonder deze migratie werkt gewoon verder (zonder filter op de server
-- en zonder "uitdaging melden").

-- Hele woorden (na normaliseren) die niet mogen, Engels en Nederlands. Woorden met een spatie zijn vaste reeksen.
create or replace function public.blocked_words() returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    -- Engels
    'shit', 'shits', 'shitty', 'shithead', 'bullshit', 'bitch', 'bitches', 'bitchy', 'asshole', 'assholes',
    'arsehole', 'arseholes', 'dickhead', 'dickheads', 'pussy', 'bastard', 'bastards', 'wanker', 'wankers', 'wanking',
    'twat', 'twats', 'retard', 'retarded', 'retards', 'tranny', 'trannies', 'kike', 'kikes', 'nazi', 'nazis',
    'hitler', 'kkk', 'nigga', 'niggas', 'niggaz', 'rapist', 'rapists', 'pedo', 'paedo', 'pedophile', 'paedophile', 'kys',
    'heil hitler', 'sieg heil', 'white power', 'kill yourself',
    -- Nederlands
    'kut', 'kutje', 'kutwijf', 'kutwijven', 'klootzak', 'klootzakken', 'lul', 'hoer', 'hoeren', 'hoerig',
    'hoerenzoon', 'kankerlijer', 'kankerhoer', 'kankerjood', 'kankerwijf', 'kankerzooi', 'kankermongool',
    'kankerhomo', 'kankerneger', 'tering', 'teringlijer', 'tyfus', 'tyfuslijer', 'pleurislijer', 'godverdomme',
    'godverdomse', 'neuk', 'neuken', 'neuker', 'neukt', 'flikker', 'flikkers', 'nikker', 'nikkers', 'mongool',
    'mongolen', 'slet', 'sletten', 'sletje'
  ]::text[];
$$;

-- Woordbegin dat niet mag (fuck, fucking, fucker, ...). Alleen stammen die geen gewoon woord beginnen.
create or replace function public.blocked_stems() returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['fuck', 'motherfuck', 'cunt', 'nigger', 'faggot', 'whore', 'slut', 'cocksuck', 'porn']::text[];
$$;

-- Bevat de tekst een geweigerd woord? Kleine letters, accenten weg, cijfers als letters, herhalingen ingekort en
-- alles wat geen letter is wordt een spatie; dan zoeken naar " woord " (heel woord) of " stam" (woordbegin).
create or replace function public.text_blocked(p text) returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  t text;
begin
  if p is null or btrim(p) = '' then
    return false;
  end if;
  t := translate(lower(p), 'áàâäãåéèêëíìîïóòôöõúùûüçñ013457@$', 'aaaaaaeeeeiiiiooooouuuucnoieastas');
  t := regexp_replace(t, '(.)\1\1+', '\1', 'g');
  t := ' ' || btrim(regexp_replace(t, '[^a-z]+', ' ', 'g')) || ' ';
  return exists (select 1 from unnest(public.blocked_words()) w where position(' ' || w || ' ' in t) > 0)
      or exists (select 1 from unnest(public.blocked_stems()) s where position(' ' || s in t) > 0);
end;
$$;

-- friend_me (zelfde handtekening, zie level_max.sql): een nieuwe naam met een geweigerd woord geeft name_not_allowed.
create or replace function public.friend_me(p_name text default null, p_avatar text default null, p_level integer default null)
returns table (code text, name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if p_name is not null and public.text_blocked(left(btrim(p_name), 40)) then
    raise exception 'name_not_allowed' using errcode = '22023', hint = 'Kies een andere naam.';
  end if;
  if not exists (select 1 from public.friend_profiles p where p.user_id = me) then
    loop
      c := '';
      for i in 1..8 loop
        c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
      end loop;
      exit when not exists (select 1 from public.friend_profiles p where p.code = c);
    end loop;
    insert into public.friend_profiles (user_id, code) values (me, c);
  end if;
  update public.friend_profiles p set
    name = coalesce(left(btrim(p_name), 40), p.name),
    avatar = case when p_avatar is null then p.avatar else nullif(p_avatar, '') end,
    level = greatest(p.level, p_level),
    updated_at = now()
  where p.user_id = me;
  return query select p.code, p.name from public.friend_profiles p where p.user_id = me;
end;
$$;

-- challenge_create (zelfde handtekening, zie challenges.sql): een titel met een geweigerd woord geeft title_not_allowed.
create or replace function public.challenge_create(
  p_template text, p_title text, p_nutrient text, p_rule text, p_amount double precision,
  p_days integer, p_need integer, p_start date, p_invite uuid[] default '{}'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
  other uuid;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if public.text_blocked(left(btrim(coalesce(p_title, '')), 60)) then
    raise exception 'title_not_allowed' using errcode = '22023', hint = 'Kies een andere titel.';
  end if;
  if p_start < current_date - 1 or p_start > current_date + 14 then
    raise exception 'startdag buiten bereik';
  end if;
  if (select count(*) from public.challenge_members m join public.challenges c on c.id = m.challenge_id
      where m.user_id = me and c.start_day + c.days >= current_date) >= 20 then
    raise exception 'te veel lopende uitdagingen';
  end if;
  insert into public.challenges (owner, template, title, nutrient, rule, amount, days, need, start_day)
  values (me, p_template, nullif(left(btrim(coalesce(p_title, '')), 60), ''), p_nutrient, p_rule, coalesce(p_amount, 0), p_days, p_need, p_start)
  returning id into new_id;
  insert into public.challenge_members (challenge_id, user_id, invited_by, accepted) values (new_id, me, me, true);
  foreach other in array coalesce(p_invite, '{}') loop
    exit when (select count(*) from public.challenge_members m where m.challenge_id = new_id) >= 20;
    if other <> me and public.are_friends(me, other) then
      insert into public.challenge_members (challenge_id, user_id, invited_by) values (new_id, other, me) on conflict do nothing;
    end if;
  end loop;
  return new_id;
end;
$$;

-- Meldingen over een uitdaging: nieuwe reden, en welke uitdaging en titel het was (de titel kan nadien niet meer
-- veranderen, maar de uitdaging kan verdwijnen: dan blijft de titel in de melding staan).
alter table public.user_reports drop constraint if exists user_reports_reason_check;
alter table public.user_reports add constraint user_reports_reason_check
  check (reason in ('spam', 'harassment', 'inappropriate', 'other', 'challenge_title'));
alter table public.user_reports
  add column challenge_id uuid references public.challenges on delete set null,
  add column challenge_title text check (challenge_title is null or char_length(challenge_title) <= 60);

-- Een uitdaging melden om haar titel. Alleen als je er zelf in zit (meegedaan of uitgenodigd) en ze niet van jezelf
-- is. Telt mee voor de 10 meldingen per dag. Geeft terug: reported, limit of not_found.
create or replace function public.challenge_report(p_id uuid, p_note text default null) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  n text := nullif(left(btrim(coalesce(p_note, '')), 500), '');
  ch public.challenges%rowtype;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  select c.* into ch from public.challenges c
  where c.id = p_id and exists (select 1 from public.challenge_members m where m.challenge_id = c.id and m.user_id = me);
  if ch.id is null or ch.owner = me then
    return 'not_found';
  end if;
  if (select count(*) from public.user_reports r where r.reporter = me and r.created_at > now() - interval '1 day') >= 10 then
    return 'limit';
  end if;
  insert into public.user_reports (reporter, reported, reason, note, reported_name, reported_avatar, challenge_id, challenge_title)
  select me, ch.owner, 'challenge_title', n, p.name, p.avatar, ch.id, coalesce(ch.title, ch.template)
  from (select 1) one
  left join public.friend_profiles p on p.user_id = ch.owner;
  return 'reported';
end;
$$;

-- challenge_list (zelfde handtekening, zie challenges.sql): zonder deelnemers die je geblokkeerd hebt.
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
    and not exists (select 1 from public.user_blocks x where x.blocker = auth.uid() and x.blocked = m.user_id)
  order by c.start_day desc, c.created_at desc, m.created_at;
$$;

revoke all on function public.blocked_words() from public, anon;
revoke all on function public.blocked_stems() from public, anon;
revoke all on function public.text_blocked(text) from public, anon;
revoke all on function public.friend_me(text, text, integer) from public, anon;
revoke all on function public.challenge_create(text, text, text, text, double precision, integer, integer, date, uuid[]) from public, anon;
revoke all on function public.challenge_report(uuid, text) from public, anon;
revoke all on function public.challenge_list() from public, anon;
grant execute on function public.blocked_words() to authenticated;
grant execute on function public.blocked_stems() to authenticated;
grant execute on function public.text_blocked(text) to authenticated;
grant execute on function public.friend_me(text, text, integer) to authenticated;
grant execute on function public.challenge_create(text, text, text, text, double precision, integer, integer, date, uuid[]) to authenticated;
grant execute on function public.challenge_report(uuid, text) to authenticated;
grant execute on function public.challenge_list() to authenticated;
