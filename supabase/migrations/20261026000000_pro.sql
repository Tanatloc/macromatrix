-- Pro: een betalend abonnement bovenop de gratis app, plus een dagteller voor loggen met een foto.
--
-- Bijna alles blijft gratis. Loggen met een foto kost echte rekenkracht (een beeldmodel op Cloudflare), dus gratis
-- krijg je 3 foto's per dag (UTC) en met Pro onbeperkt, met een rem tegen misbruik van 50 per dag.
--
-- pro_status wordt alleen geschreven met de service-role of met SQL door de beheerder (later door de koppeling met
-- Google Play en een webbetaling). De app kan er niets in zetten: er zijn geen policies om te schrijven. Je kunt
-- alleen je eigen rij lezen.
--
-- photo_usage bewaart per account per dag alleen een getal. Geen foto's, geen beschrijving van je bord.
--
-- Eerst toepassen in de SQL-editor; een app of /api/photo zonder deze migratie werkt gewoon verder zoals vroeger
-- (zonder teller en zonder Pro).

create table public.pro_status (
  user_id uuid primary key references auth.users on delete cascade,
  -- Tot wanneer Pro loopt. Levenslang = ver in de toekomst (bv. 9999-12-31).
  until timestamptz not null,
  -- Waar het vandaan komt: manual, gift, play, web, ...
  source text not null default 'manual' check (char_length(source) between 1 and 40),
  -- Het Supporter-badge tonen aan vrienden (zelf uit te zetten via pro_show_badge)
  show_badge boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.photo_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0 and count <= 10000),
  primary key (user_id, day)
);

alter table public.pro_status enable row level security;
alter table public.photo_usage enable row level security;

-- Alleen je eigen rij lezen; schrijven kan niet vanuit de app (geen policies en geen rechten)
create policy "eigen pro-status lezen" on public.pro_status for select to authenticated
  using (user_id = (select auth.uid()));
create policy "eigen fototeller lezen" on public.photo_usage for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.pro_status from public, anon, authenticated;
revoke insert, update, delete, truncate on public.photo_usage from public, anon, authenticated;

-- Loopt Pro nu voor deze gebruiker? Alleen voor gebruik binnen de functies hieronder.
create or replace function public.pro_active(p_user uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.pro_status s where s.user_id = p_user and s.until > now());
$$;

-- Hoeveel foto's per dag: 3 gratis, 50 met Pro (rem tegen misbruik).
create or replace function public.photo_limit(p_pro boolean) returns integer
language sql
immutable
set search_path = ''
as $$
  select case when p_pro then 50 else 3 end;
$$;

-- Een foto gebruiken: in één stap nakijken of het nog mag en de teller van vandaag (UTC) verhogen.
-- Geeft terug: {allowed, used, limit, pro}. Bij allowed = false blijft de teller staan.
create or replace function public.photo_quota_use() returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  today date := (now() at time zone 'utc')::date;
  is_pro boolean;
  lim integer;
  used integer;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  is_pro := public.pro_active(me);
  lim := public.photo_limit(is_pro);
  insert into public.photo_usage (user_id, day, count) values (me, today, 0) on conflict (user_id, day) do nothing;
  -- De update vergrendelt de rij: twee foto's tegelijk kunnen samen niet over de grens
  update public.photo_usage u set count = u.count + 1
  where u.user_id = me and u.day = today and u.count < lim
  returning u.count into used;
  if used is null then
    select u.count into used from public.photo_usage u where u.user_id = me and u.day = today;
    return jsonb_build_object('allowed', false, 'used', used, 'limit', lim, 'pro', is_pro);
  end if;
  -- Oude dagen opruimen: alleen vandaag doet ertoe
  delete from public.photo_usage u where u.user_id = me and u.day < today - 7;
  return jsonb_build_object('allowed', true, 'used', used, 'limit', lim, 'pro', is_pro);
end;
$$;

-- Hetzelfde lezen zonder iets te verhogen (voor "nog 2 van 3 gratis foto's vandaag").
create or replace function public.photo_quota() returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  is_pro boolean;
  lim integer;
  used integer;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  is_pro := public.pro_active(me);
  lim := public.photo_limit(is_pro);
  select coalesce(max(u.count), 0) into used from public.photo_usage u
  where u.user_id = me and u.day = (now() at time zone 'utc')::date;
  return jsonb_build_object('allowed', used < lim, 'used', used, 'limit', lim, 'pro', is_pro);
end;
$$;

-- Je eigen Pro-status: {pro, until, source, show_badge}. Zonder rij: pro = false en de rest null.
create or replace function public.my_pro() returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('pro', s.until > now(), 'until', s.until, 'source', s.source, 'show_badge', s.show_badge)
     from public.pro_status s where s.user_id = auth.uid()),
    jsonb_build_object('pro', false, 'until', null, 'source', null, 'show_badge', true)
  );
$$;

-- Het Supporter-badge bij vrienden tonen of verbergen (alleen je eigen rij, en alleen deze kolom).
create or replace function public.pro_show_badge(p_show boolean) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'niet ingelogd';
  end if;
  update public.pro_status s set show_badge = coalesce(p_show, true), updated_at = now() where s.user_id = auth.uid();
end;
$$;

-- friend_list met een extra kolom "supporter" (Pro loopt en het badge staat aan; alleen bij bevestigde vrienden).
-- Nieuwe naam, zodat oudere versies van de app gewoon friend_list(date) blijven gebruiken.
create or replace function public.friend_list_v2(p_week date)
returns table (
  other uuid, name text, state text, score smallint, days smallint, prev_score smallint, prev_days smallint,
  avatar text, level integer, title text, badges text, supporter boolean
)
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
    case when m.state = 'friend' then p.title end, case when m.state = 'friend' then p.badges end,
    m.state = 'friend' and exists (
      select 1 from public.pro_status s where s.user_id = m.other and s.until > now() and s.show_badge
    )
  from mine m
  left join public.friend_profiles p on p.user_id = m.other
  left join public.weekly_scores w on m.state = 'friend' and w.user_id = m.other and w.week = p_week
  left join public.weekly_scores v on m.state = 'friend' and v.user_id = m.other and v.week = p_week - 7
  order by m.state, coalesce(p.name, '');
$$;

revoke all on function public.pro_active(uuid) from public, anon, authenticated;
revoke all on function public.photo_limit(boolean) from public, anon;
revoke all on function public.photo_quota_use() from public, anon;
revoke all on function public.photo_quota() from public, anon;
revoke all on function public.my_pro() from public, anon;
revoke all on function public.pro_show_badge(boolean) from public, anon;
revoke all on function public.friend_list_v2(date) from public, anon;
grant execute on function public.photo_limit(boolean) to authenticated;
grant execute on function public.photo_quota_use() to authenticated;
grant execute on function public.photo_quota() to authenticated;
grant execute on function public.my_pro() to authenticated;
grant execute on function public.pro_show_badge(boolean) to authenticated;
grant execute on function public.friend_list_v2(date) to authenticated;

-- Pro met de hand toekennen (in de SQL-editor, als beheerder), bv. een jaar:
--   insert into public.pro_status (user_id, until, source)
--   select id, now() + interval '1 year', 'manual' from auth.users where email = 'iemand@example.com'
--   on conflict (user_id) do update set until = excluded.until, source = excluded.source, updated_at = now();
