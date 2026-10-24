-- Dagtellers voor de andere AI-functies: een etiket lezen (label) en een recept importeren (recipe).
--
-- Net als bij loggen met een foto kost dit echte rekenkracht (een beeldmodel op Cloudflare). Daarom een teller per
-- account, per soort en per dag (UTC):
--   label:  gratis 1 per dag, met Pro 30 per dag (rem tegen misbruik)
--   recipe: alleen met Pro, 20 per dag
--
-- ai_usage bewaart per account, per soort en per dag alleen een getal. Geen foto's, geen links, geen recepten.
--
-- Bouwt verder op 20261026000000_pro.sql (pro_active). Eerst toepassen in de SQL-editor. Zonder deze migratie werkt
-- /api/label zoals zonder teller (alleen de rem per uur), en weigert /api/recipe (Pro kan dan niet nagekeken worden).

create table public.ai_usage (
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('label', 'recipe')),
  day date not null,
  count integer not null default 0 check (count >= 0 and count <= 10000),
  primary key (user_id, kind, day)
);

alter table public.ai_usage enable row level security;

-- Alleen je eigen rijen lezen; schrijven kan alleen via ai_quota_use hieronder
create policy "eigen AI-teller lezen" on public.ai_usage for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete, truncate on public.ai_usage from public, anon, authenticated;

-- Hoeveel per dag, per soort, met of zonder Pro. Een onbekende soort mag nooit (0).
create or replace function public.ai_limit(p_kind text, p_pro boolean) returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'label' then case when p_pro then 30 else 1 end
    when 'recipe' then case when p_pro then 20 else 0 end
    else 0
  end;
$$;

-- Eén keer gebruiken: in één stap nakijken of het nog mag en de teller van vandaag (UTC) verhogen.
-- Geeft terug: {allowed, used, limit, pro}. Bij allowed = false blijft de teller staan.
create or replace function public.ai_quota_use(p_kind text) returns jsonb
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
  if p_kind is null or p_kind not in ('label', 'recipe') then
    raise exception 'onbekende soort';
  end if;
  is_pro := public.pro_active(me);
  lim := public.ai_limit(p_kind, is_pro);
  if lim <= 0 then
    return jsonb_build_object('allowed', false, 'used', 0, 'limit', lim, 'pro', is_pro);
  end if;
  insert into public.ai_usage (user_id, kind, day, count) values (me, p_kind, today, 0)
  on conflict (user_id, kind, day) do nothing;
  -- De update vergrendelt de rij: twee verzoeken tegelijk kunnen samen niet over de grens
  update public.ai_usage u set count = u.count + 1
  where u.user_id = me and u.kind = p_kind and u.day = today and u.count < lim
  returning u.count into used;
  if used is null then
    select u.count into used from public.ai_usage u where u.user_id = me and u.kind = p_kind and u.day = today;
    return jsonb_build_object('allowed', false, 'used', used, 'limit', lim, 'pro', is_pro);
  end if;
  -- Oude dagen opruimen: alleen vandaag doet ertoe
  delete from public.ai_usage u where u.user_id = me and u.day < today - 7;
  return jsonb_build_object('allowed', true, 'used', used, 'limit', lim, 'pro', is_pro);
end;
$$;

-- Hetzelfde lezen zonder iets te verhogen (voor "gratis etiket van vandaag gebruikt").
create or replace function public.ai_quota(p_kind text) returns jsonb
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
  lim := public.ai_limit(p_kind, is_pro);
  select coalesce(max(u.count), 0) into used from public.ai_usage u
  where u.user_id = me and u.kind = p_kind and u.day = (now() at time zone 'utc')::date;
  return jsonb_build_object('allowed', used < lim, 'used', used, 'limit', lim, 'pro', is_pro);
end;
$$;

revoke all on function public.ai_limit(text, boolean) from public, anon;
revoke all on function public.ai_quota_use(text) from public, anon;
revoke all on function public.ai_quota(text) from public, anon;
grant execute on function public.ai_limit(text, boolean) to authenticated;
grant execute on function public.ai_quota_use(text) to authenticated;
grant execute on function public.ai_quota(text) to authenticated;
