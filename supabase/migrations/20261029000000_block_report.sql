-- Blokkeren en melden bij vrienden, battles en uitdagingen.
--
-- Blokkeren: de vriendschap (of het verzoek) verdwijnt, net als openstaande battles en uitnodigingen voor
-- uitdagingen tussen jullie twee, en zolang de blokkade loopt kan geen van beiden de ander nog een verzoek sturen.
-- Wie geblokkeerd is, merkt daar niets van: zijn verzoek met jouw code geeft gewoon "niet gevonden".
--
-- Melden: een korte reden (en eventueel een notitie van max. 500 tekens) komt in user_reports, samen met de naam
-- en avatar van de gemelde persoon op dat moment (die kan je nadien wijzigen). Gebruikers kunnen meldingen niet
-- lezen; alleen de beheerder bekijkt ze om misbruik aan te pakken. Hoogstens 10 meldingen per dag per persoon.
--
-- Eerst toepassen in de SQL-editor; een app zonder deze migratie werkt gewoon verder (zonder blokkeren en melden).

create table public.user_blocks (
  blocker uuid not null references auth.users on delete cascade,
  blocked uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index user_blocks_blocked on public.user_blocks (blocked);

alter table public.user_blocks enable row level security;
-- Alleen je eigen blokkades zien (niet wie jou blokkeerde); toevoegen en wissen gaat via de functies hieronder
create policy "eigen blokkades lezen" on public.user_blocks for select to authenticated
  using (blocker = (select auth.uid()));

create table public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null references auth.users on delete cascade,
  reported uuid not null references auth.users on delete cascade,
  reason text not null check (reason in ('spam', 'harassment', 'inappropriate', 'other')),
  note text check (note is null or char_length(note) <= 500),
  -- Naam en avatar van de gemelde persoon op het moment van de melding
  reported_name text check (reported_name is null or char_length(reported_name) <= 40),
  reported_avatar text check (reported_avatar is null or char_length(reported_avatar) <= 100000),
  created_at timestamptz not null default now(),
  check (reporter <> reported)
);
create index user_reports_reporter on public.user_reports (reporter, created_at);
create index user_reports_reported on public.user_reports (reported);

-- Geen policies: niemand leest of schrijft rechtstreeks, melden gaat via friend_report
alter table public.user_reports enable row level security;

-- Iemand blokkeren: vriendschap of verzoek weg, openstaande en lopende battles weg, uitnodigingen tussen jullie weg.
create or replace function public.friend_block(p_other uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if p_other is null or p_other = me then
    return;
  end if;
  if not exists (select 1 from auth.users u where u.id = p_other) then
    return;
  end if;
  if (select count(*) from public.user_blocks x where x.blocker = me) >= 1000 then
    raise exception 'te veel blokkades';
  end if;
  insert into public.user_blocks (blocker, blocked) values (me, p_other) on conflict do nothing;
  delete from public.friendships f
  where (f.requester = me and f.addressee = p_other) or (f.requester = p_other and f.addressee = me);
  -- Openstaande uitdagingen, en battles van deze of een volgende week (afgelopen battles blijven in je geschiedenis)
  delete from public.battles b
  where ((b.challenger = me and b.opponent = p_other) or (b.challenger = p_other and b.opponent = me))
    and (not b.accepted or b.week + 7 > current_date);
  -- Niet-aanvaarde uitnodigingen voor uitdagingen die de een de ander stuurde
  delete from public.challenge_members m
  where not m.accepted
    and ((m.user_id = me and m.invited_by = p_other) or (m.user_id = p_other and m.invited_by = me));
end;
$$;

-- Een blokkade opheffen. Jullie zijn daarna geen vrienden meer; opnieuw toevoegen kan met de code.
create or replace function public.friend_unblock(p_other uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  delete from public.user_blocks x where x.blocker = auth.uid() and x.blocked = p_other;
end;
$$;

-- Wie je geblokkeerd hebt, met naam en avatar (voor de lijst om te deblokkeren).
create or replace function public.friend_blocked_list()
returns table (other uuid, name text, avatar text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select x.blocked, coalesce(p.name, ''), p.avatar, x.created_at
  from public.user_blocks x
  left join public.friend_profiles p on p.user_id = x.blocked
  where x.blocker = auth.uid()
  order by x.created_at desc;
$$;

-- Iemand melden. Alleen iemand met wie je een band hebt (vriend, verzoek, blokkade, battle of samen in een
-- uitdaging), zodat je geen willekeurige accounts kan melden. Geeft terug: reported, limit, bad_reason of not_found.
create or replace function public.friend_report(p_other uuid, p_reason text, p_note text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  n text := nullif(left(btrim(coalesce(p_note, '')), 500), '');
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if p_reason is null or p_reason not in ('spam', 'harassment', 'inappropriate', 'other') then
    return 'bad_reason';
  end if;
  if p_other is null or p_other = me or not (
    exists (select 1 from public.friendships f
            where (f.requester = me and f.addressee = p_other) or (f.requester = p_other and f.addressee = me))
    or exists (select 1 from public.user_blocks x where x.blocker = me and x.blocked = p_other)
    or exists (select 1 from public.battles b
               where (b.challenger = me and b.opponent = p_other) or (b.challenger = p_other and b.opponent = me))
    or exists (select 1 from public.challenge_members a join public.challenge_members o on o.challenge_id = a.challenge_id
               where a.user_id = me and o.user_id = p_other)
  ) then
    return 'not_found';
  end if;
  if (select count(*) from public.user_reports r where r.reporter = me and r.created_at > now() - interval '1 day') >= 10 then
    return 'limit';
  end if;
  insert into public.user_reports (reporter, reported, reason, note, reported_name, reported_avatar)
  select me, p_other, p_reason, n, p.name, p.avatar
  from (select 1) one
  left join public.friend_profiles p on p.user_id = p_other;
  return 'reported';
end;
$$;

-- friend_add (zelfde handtekening): wie geblokkeerd is of zelf blokkeerde, krijgt 'not_found', zoals bij een
-- onbestaande code. Zo verraadt de uitkomst niet dat er een blokkade is. friend_add_v2 roept deze functie aan.
create or replace function public.friend_add(p_code text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  other uuid;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  select p.user_id into other from public.friend_profiles p where p.code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if other is null then
    return 'not_found';
  end if;
  if other = me then
    return 'self';
  end if;
  if exists (select 1 from public.user_blocks x where (x.blocker = me and x.blocked = other) or (x.blocker = other and x.blocked = me)) then
    return 'not_found';
  end if;
  if exists (select 1 from public.friendships f where f.requester = other and f.addressee = me) then
    update public.friendships f set accepted = true where f.requester = other and f.addressee = me;
    return 'accepted';
  end if;
  if exists (select 1 from public.friendships f where f.requester = me and f.addressee = other) then
    return 'already';
  end if;
  if (select count(*) from public.friendships f where f.requester = me and not f.accepted) >= 50 then
    raise exception 'te veel openstaande verzoeken';
  end if;
  insert into public.friendships (requester, addressee) values (me, other);
  return 'requested';
end;
$$;

-- friend_add_v2: bij een blokkade ook 'not_found' en geen id (anders zou de id de blokkade verraden).
create or replace function public.friend_add_v2(p_code text)
returns table (result text, other uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  o uuid;
  r text;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  select p.user_id into o from public.friend_profiles p where p.code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if o is null then
    return query select 'not_found'::text, null::uuid;
    return;
  end if;
  if o = me then
    return query select 'self'::text, o;
    return;
  end if;
  if public.are_friends(me, o) then
    return query select 'friends'::text, o;
    return;
  end if;
  r := public.friend_add(p_code);
  return query select r, case when r = 'not_found' then null::uuid else o end;
end;
$$;

revoke all on function public.friend_block(uuid) from public, anon;
revoke all on function public.friend_unblock(uuid) from public, anon;
revoke all on function public.friend_blocked_list() from public, anon;
revoke all on function public.friend_report(uuid, text, text) from public, anon;
revoke all on function public.friend_add(text) from public, anon;
revoke all on function public.friend_add_v2(text) from public, anon;
grant execute on function public.friend_block(uuid) to authenticated;
grant execute on function public.friend_unblock(uuid) to authenticated;
grant execute on function public.friend_blocked_list() to authenticated;
grant execute on function public.friend_report(uuid, text, text) to authenticated;
grant execute on function public.friend_add(text) to authenticated;
grant execute on function public.friend_add_v2(text) to authenticated;
