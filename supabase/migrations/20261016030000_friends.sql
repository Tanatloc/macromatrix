-- Vrienden: elkaar toevoegen met een code en elkaars wekelijkse gemiddelde volledigheidsscore zien.
-- Er wordt niets anders gedeeld: geen dagboek, geen gewicht, geen e-mailadres. Alleen een zelfgekozen naam en per
-- week één getal (0–100) met het aantal gelogde dagen.
--
-- friend_profiles en friendships zijn niet rechtstreeks leesbaar; alles gaat via de functies hieronder, die
-- telkens alleen de eigen rij of die van bevestigde vrienden teruggeven.

create table public.friend_profiles (
  user_id uuid primary key references auth.users on delete cascade,
  code text not null unique,
  name text not null default '' check (char_length(name) <= 40),
  updated_at timestamptz not null default now()
);

create table public.friendships (
  requester uuid not null references auth.users on delete cascade,
  addressee uuid not null references auth.users on delete cascade,
  accepted boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create index friendships_addressee on public.friendships (addressee);

create table public.weekly_scores (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  week date not null check (extract(isodow from week) = 1),
  score smallint not null check (score between 0 and 100),
  days smallint not null check (days between 1 and 7),
  updated_at timestamptz not null default now(),
  primary key (user_id, week)
);

alter table public.friend_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.weekly_scores enable row level security;

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.accepted and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a))
  );
$$;
revoke all on function public.are_friends(uuid, uuid) from public, anon;
grant execute on function public.are_friends(uuid, uuid) to authenticated;

create policy "eigen profiel lezen" on public.friend_profiles for select to authenticated
  using (user_id = (select auth.uid()));

create policy "eigen en vrienden lezen" on public.weekly_scores for select to authenticated
  using (user_id = (select auth.uid()) or public.are_friends((select auth.uid()), user_id));
create policy "eigen score bewaren" on public.weekly_scores for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "eigen score bijwerken" on public.weekly_scores for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "eigen score wissen" on public.weekly_scores for delete to authenticated
  using (user_id = (select auth.uid()));

-- Eigen vriendcode (wordt aangemaakt bij de eerste keer) en eventueel de naam aanpassen.
create or replace function public.friend_me(p_name text default null)
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
  if p_name is not null then
    update public.friend_profiles p set name = left(btrim(p_name), 40), updated_at = now() where p.user_id = me;
  end if;
  return query select p.code, p.name from public.friend_profiles p where p.user_id = me;
end;
$$;

-- Iemand toevoegen met zijn code. Heeft die persoon jou al gevraagd, dan zijn jullie meteen vrienden.
-- Geeft terug: requested, accepted, already, self of not_found.
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

-- Een verzoek aannemen of weigeren.
create or replace function public.friend_respond(p_other uuid, p_accept boolean) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  if p_accept then
    update public.friendships f set accepted = true where f.requester = p_other and f.addressee = auth.uid();
  else
    delete from public.friendships f where f.requester = p_other and f.addressee = auth.uid() and not f.accepted;
  end if;
end;
$$;

-- Vriendschap of verzoek (in beide richtingen) verwijderen.
create or replace function public.friend_remove(p_other uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  delete from public.friendships f
  where (f.requester = auth.uid() and f.addressee = p_other) or (f.requester = p_other and f.addressee = auth.uid());
end;
$$;

-- Vrienden en verzoeken, met de score van deze en vorige week (alleen bij bevestigde vrienden).
create or replace function public.friend_list(p_week date)
returns table (other uuid, name text, state text, score smallint, days smallint, prev_score smallint, prev_days smallint)
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
    w.score, w.days, v.score, v.days
  from mine m
  left join public.friend_profiles p on p.user_id = m.other
  left join public.weekly_scores w on m.state = 'friend' and w.user_id = m.other and w.week = p_week
  left join public.weekly_scores v on m.state = 'friend' and v.user_id = m.other and v.week = p_week - 7
  order by m.state, coalesce(p.name, '');
$$;

revoke all on function public.friend_me(text) from public, anon;
revoke all on function public.friend_add(text) from public, anon;
revoke all on function public.friend_respond(uuid, boolean) from public, anon;
revoke all on function public.friend_remove(uuid) from public, anon;
revoke all on function public.friend_list(date) from public, anon;
grant execute on function public.friend_me(text) to authenticated;
grant execute on function public.friend_add(text) to authenticated;
grant execute on function public.friend_respond(uuid, boolean) to authenticated;
grant execute on function public.friend_remove(uuid) to authenticated;
grant execute on function public.friend_list(date) to authenticated;
