-- Uitdagingen met vrienden ("30 dagen 30 g vezels", "een week max. 25 g vrije suikers", ...).
--
-- Een uitdaging heeft een sjabloon (voedingsstof, regel per dag en duur), een startdag en deelnemers. Elke app
-- rekent zelf uit of je dag gehaald is, uit het eigen dagboek, en zet alleen dat (ja/nee per dag) in
-- challenge_days. Er gaat niets over wat je eet naar de server, net zoals bij battles.
--
-- Alleen-voor-jezelf-uitdagingen staan niet op de server; die bewaart de app zelf.
-- challenges en challenge_members zijn niet rechtstreeks leesbaar; alles gaat via de functies hieronder.
-- Eerst toepassen in de SQL-editor; een app zonder deze migratie werkt gewoon verder (zonder groepsuitdagingen).

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users on delete cascade,
  -- Sleutel van een ingebouwd sjabloon (bv. "fiber30") of "custom"
  template text not null check (char_length(template) between 1 and 40),
  title text check (title is null or char_length(title) <= 60),
  nutrient text not null check (char_length(nutrient) between 1 and 40),
  rule text not null check (rule in ('min', 'max', 'goal')),
  amount double precision not null default 0 check (amount >= 0 and amount <= 100000),
  days smallint not null check (days between 1 and 90),
  need smallint not null check (need between 1 and 90),
  start_day date not null,
  created_at timestamptz not null default now(),
  check (need <= days)
);
create index challenges_owner on public.challenges (owner);

create table public.challenge_members (
  challenge_id uuid not null references public.challenges on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  invited_by uuid references auth.users on delete set null,
  accepted boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);
create index challenge_members_user on public.challenge_members (user_id);

-- Per deelnemer per dag: gehaald of niet. Meer niet.
create table public.challenge_days (
  challenge_id uuid not null references public.challenges on delete cascade,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  day date not null,
  met boolean not null,
  updated_at timestamptz not null default now(),
  primary key (challenge_id, user_id, day)
);

alter table public.challenges enable row level security;
alter table public.challenge_members enable row level security;
alter table public.challenge_days enable row level security;

-- Ben je (aanvaard) deelnemer? Alleen vragen over jezelf, zoals are_friends.
create or replace function public.challenge_member(p_challenge uuid, p_user uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) = p_user and exists (
    select 1 from public.challenge_members m
    where m.challenge_id = p_challenge and m.user_id = p_user and m.accepted
  );
$$;

-- Ligt de dag binnen de uitdaging (en niet ver in de toekomst)?
create or replace function public.challenge_day_ok(p_challenge uuid, p_day date) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.challenges c
    where c.id = p_challenge and p_day >= c.start_day and p_day < c.start_day + c.days and p_day <= current_date + 1
  );
$$;

-- Geen policies op challenges en challenge_members: alleen via de functies hieronder.
-- Eigen dagen lezen, bewaren, bijwerken en wissen, alleen als aanvaard deelnemer en binnen de looptijd.
create policy "eigen dagen lezen" on public.challenge_days for select to authenticated
  using (user_id = (select auth.uid()));
create policy "eigen dag bewaren" on public.challenge_days for insert to authenticated
  with check (user_id = (select auth.uid()) and public.challenge_member(challenge_id, user_id) and public.challenge_day_ok(challenge_id, day));
create policy "eigen dag bijwerken" on public.challenge_days for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.challenge_member(challenge_id, user_id) and public.challenge_day_ok(challenge_id, day));
create policy "eigen dag wissen" on public.challenge_days for delete to authenticated
  using (user_id = (select auth.uid()));

-- Een uitdaging starten en meteen vrienden uitnodigen (alleen bevestigde vrienden; de rest wordt overgeslagen).
-- Geeft het id terug.
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

-- Een vriend uitnodigen voor een uitdaging waar je zelf aan meedoet.
-- Geeft terug: invited, exists, not_friends, full, finished of not_member.
create or replace function public.challenge_invite(p_id uuid, p_other uuid) returns text
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
  if not public.challenge_member(p_id, me) then
    return 'not_member';
  end if;
  if exists (select 1 from public.challenges c where c.id = p_id and c.start_day + c.days <= current_date) then
    return 'finished';
  end if;
  if not public.are_friends(me, p_other) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.challenge_members m where m.challenge_id = p_id and m.user_id = p_other) then
    return 'exists';
  end if;
  if (select count(*) from public.challenge_members m where m.challenge_id = p_id) >= 20 then
    return 'full';
  end if;
  insert into public.challenge_members (challenge_id, user_id, invited_by) values (p_id, p_other, me);
  return 'invited';
end;
$$;

-- Een uitnodiging aannemen of weigeren.
create or replace function public.challenge_respond(p_id uuid, p_accept boolean) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  if p_accept then
    update public.challenge_members m set accepted = true where m.challenge_id = p_id and m.user_id = auth.uid();
  else
    delete from public.challenge_members m where m.challenge_id = p_id and m.user_id = auth.uid() and not m.accepted;
  end if;
end;
$$;

-- Stoppen met een uitdaging: je dagen en je plaats verdwijnen. Is er niemand meer over, dan verdwijnt ze helemaal.
create or replace function public.challenge_leave(p_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  delete from public.challenge_days d where d.challenge_id = p_id and d.user_id = auth.uid();
  delete from public.challenge_members m where m.challenge_id = p_id and m.user_id = auth.uid();
  delete from public.challenges c
  where c.id = p_id and not exists (select 1 from public.challenge_members m where m.challenge_id = p_id and m.accepted);
end;
$$;

-- Je uitdagingen (meegedaan of uitgenodigd, tot 60 dagen na het einde), één rij per deelnemer, met het aantal
-- gehaalde dagen. Wie nog niet aanvaard heeft, staat erbij met accepted = false.
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
  order by c.start_day desc, c.created_at desc, m.created_at;
$$;

revoke all on function public.challenge_member(uuid, uuid) from public, anon;
revoke all on function public.challenge_day_ok(uuid, date) from public, anon;
revoke all on function public.challenge_create(text, text, text, text, double precision, integer, integer, date, uuid[]) from public, anon;
revoke all on function public.challenge_invite(uuid, uuid) from public, anon;
revoke all on function public.challenge_respond(uuid, boolean) from public, anon;
revoke all on function public.challenge_leave(uuid) from public, anon;
revoke all on function public.challenge_list() from public, anon;
grant execute on function public.challenge_member(uuid, uuid) to authenticated;
grant execute on function public.challenge_day_ok(uuid, date) to authenticated;
grant execute on function public.challenge_create(text, text, text, text, double precision, integer, integer, date, uuid[]) to authenticated;
grant execute on function public.challenge_invite(uuid, uuid) to authenticated;
grant execute on function public.challenge_respond(uuid, boolean) to authenticated;
grant execute on function public.challenge_leave(uuid) to authenticated;
grant execute on function public.challenge_list() to authenticated;
