-- Wekelijkse battles tussen vrienden, plus titels en badges op het vriendenprofiel.
--
-- Een battle loopt van maandag tot en met zondag. Punten = som van de volledigheidsscores van de dagen die je die
-- week op tijd logde (max. 100 per dag). De app berekent ze en zet ze in weekly_scores (points, mid_points =
-- maandag tot en met woensdag, voor de badge "Comeback"). Wie zondagavond de meeste punten heeft, wint.
-- Battles, titels en badges geven geen XP.

alter table public.weekly_scores
  add column points integer check (points is null or points between 0 and 1000),
  add column mid_points integer check (mid_points is null or mid_points between 0 and 1000);

alter table public.friend_profiles
  add column title text check (title is null or char_length(title) <= 40),
  add column badges text check (badges is null or char_length(badges) <= 2000);

create table public.battles (
  id uuid primary key default gen_random_uuid(),
  week date not null check (extract(isodow from week) = 1),
  challenger uuid not null references auth.users on delete cascade,
  opponent uuid not null references auth.users on delete cascade,
  accepted boolean not null default false,
  created_at timestamptz not null default now(),
  check (challenger <> opponent)
);
create unique index battles_pair_week on public.battles (week, least(challenger, opponent), greatest(challenger, opponent));
create index battles_challenger on public.battles (challenger);
create index battles_opponent on public.battles (opponent);
-- Geen policies: alleen bereikbaar via de functies hieronder
alter table public.battles enable row level security;

-- Titel (sleutel, bv. "champion") en badges (komma-gescheiden sleutels) op je vriendenprofiel.
create or replace function public.friend_extra(p_title text, p_badges text) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  update public.friend_profiles p set
    title = nullif(left(btrim(coalesce(p_title, '')), 40), ''),
    badges = nullif(left(coalesce(p_badges, ''), 2000), ''),
    updated_at = now()
  where p.user_id = auth.uid();
end;
$$;

-- friend_list met titel en badges (ander resultaattype, dus opnieuw aanmaken)
drop function public.friend_list(date);

create function public.friend_list(p_week date)
returns table (other uuid, name text, state text, score smallint, days smallint, prev_score smallint, prev_days smallint, avatar text, level integer, title text, badges text)
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select case when f.requester = auth.uid() then f.addressee else f.requester end as other,
      case when f.accepted then 'friend' when f.requester = auth.uid() then 'outgoing' else 'incoming' end as state
    from public.friendships f
    where f.requester = auth.uid() or f.addressee = auth.uid()
  )
  select m.other, coalesce(p.name, ''), m.state,
    w.score, w.days, v.score, v.days, p.avatar, coalesce(p.level, 1),
    case when m.state = 'friend' then p.title end, case when m.state = 'friend' then p.badges end
  from mine m
  left join public.friend_profiles p on p.user_id = m.other
  left join public.weekly_scores w on m.state = 'friend' and w.user_id = m.other and w.week = p_week
  left join public.weekly_scores v on m.state = 'friend' and v.user_id = m.other and v.week = p_week - 7
  order by m.state, coalesce(p.name, '');
$$;

-- Een vriend uitdagen voor de week die op p_week (maandag) begint. Heeft die jou al uitgedaagd, dan is de battle
-- meteen aanvaard. Geeft terug: created, accepted, exists, not_friends of bad_week.
create or replace function public.battle_challenge(p_other uuid, p_week date) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  b public.battles;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if extract(isodow from p_week) <> 1 or p_week < current_date - 8 or p_week > current_date + 7 then
    return 'bad_week';
  end if;
  if not public.are_friends(me, p_other) then
    return 'not_friends';
  end if;
  select * into b from public.battles x
  where x.week = p_week and least(x.challenger, x.opponent) = least(me, p_other) and greatest(x.challenger, x.opponent) = greatest(me, p_other);
  if found then
    if b.opponent = me and not b.accepted then
      update public.battles x set accepted = true where x.id = b.id;
      return 'accepted';
    end if;
    return 'exists';
  end if;
  insert into public.battles (week, challenger, opponent) values (p_week, me, p_other);
  return 'created';
end;
$$;

-- Een uitdaging aannemen of weigeren (alleen door wie uitgedaagd werd).
create or replace function public.battle_respond(p_id uuid, p_accept boolean) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  if p_accept then
    update public.battles x set accepted = true where x.id = p_id and x.opponent = auth.uid();
  else
    delete from public.battles x where x.id = p_id and x.opponent = auth.uid() and not x.accepted;
  end if;
end;
$$;

-- Een eigen uitdaging intrekken zolang ze niet aanvaard is.
create or replace function public.battle_cancel(p_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  delete from public.battles x where x.id = p_id and x.challenger = auth.uid() and not x.accepted;
end;
$$;

-- Al je battles (aanvaard, of nog open vanaf vorige week), met de punten van beide kanten.
create or replace function public.battle_list()
returns table (
  id uuid, week date, challenged_by_me boolean, accepted boolean,
  other uuid, other_name text, other_avatar text, other_level integer, other_title text,
  my_points integer, my_mid integer, other_points integer, other_mid integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id, b.week, b.challenger = auth.uid(), b.accepted,
    o.other, coalesce(p.name, ''), p.avatar, coalesce(p.level, 1), p.title,
    coalesce(mw.points, 0), coalesce(mw.mid_points, 0), coalesce(ow.points, 0), coalesce(ow.mid_points, 0)
  from public.battles b
  cross join lateral (select case when b.challenger = auth.uid() then b.opponent else b.challenger end as other) o
  left join public.friend_profiles p on p.user_id = o.other
  left join public.weekly_scores mw on mw.user_id = auth.uid() and mw.week = b.week
  left join public.weekly_scores ow on ow.user_id = o.other and ow.week = b.week
  where (b.challenger = auth.uid() or b.opponent = auth.uid())
    and (b.accepted or b.week >= current_date - 14)
  order by b.week desc, b.created_at desc;
$$;

revoke all on function public.friend_extra(text, text) from public, anon;
revoke all on function public.friend_list(date) from public, anon;
revoke all on function public.battle_challenge(uuid, date) from public, anon;
revoke all on function public.battle_respond(uuid, boolean) from public, anon;
revoke all on function public.battle_cancel(uuid) from public, anon;
revoke all on function public.battle_list() from public, anon;
grant execute on function public.friend_extra(text, text) to authenticated;
grant execute on function public.friend_list(date) to authenticated;
grant execute on function public.battle_challenge(uuid, date) to authenticated;
grant execute on function public.battle_respond(uuid, boolean) to authenticated;
grant execute on function public.battle_cancel(uuid) to authenticated;
grant execute on function public.battle_list() to authenticated;
