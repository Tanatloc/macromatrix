-- Wekelijkse coach: een korte samenvatting van je week met 2 à 3 tips, geschreven door een tekstmodel op Cloudflare
-- (/api/coach). De eerste functie in vroege toegang: supporters (Pro) nu, iedereen 3 weken later.
--
-- De dagteller is dezelfde als voor etiketten en recepten (ai_usage, ai_quota_use), met een nieuwe soort 'coach':
--   met Pro:    3 per dag
--   zonder Pro: 1 per dag, maar alleen als de functie 'coach' al voor iedereen open staat (public_from voorbij);
--               anders 0. Zo houdt ook de server zich aan de vroege toegang, niet alleen de app.
--
-- Er wordt niets van de samenvatting of het antwoord bewaard, alleen het getal in ai_usage.
--
-- Bouwt verder op 20261027000000_ai_quota.sql en 20261031000000_early_access.sql. Eerst toepassen in de
-- SQL-editor. Zonder deze migratie toont de app de coach niet (de vlag 'coach' bestaat dan niet), en weigert
-- /api/coach met not_configured.

-- 'coach' toelaten in de teller (de naam van de check komt van Postgres: <tabel>_<kolom>_check)
alter table public.ai_usage drop constraint if exists ai_usage_kind_check;
alter table public.ai_usage add constraint ai_usage_kind_check check (kind in ('label', 'recipe', 'coach'));

-- Hoeveel per dag, per soort, met of zonder Pro. Een onbekende soort mag nooit (0). Niet meer immutable: voor
-- 'coach' zonder Pro hangt het af van public.features en van het moment.
create or replace function public.ai_limit(p_kind text, p_pro boolean) returns integer
language sql
stable
set search_path = ''
as $$
  select case p_kind
    when 'label' then case when p_pro then 30 else 1 end
    when 'recipe' then case when p_pro then 20 else 0 end
    when 'coach' then case
      when p_pro then 3
      when exists (select 1 from public.features f where f.id = 'coach' and f.public_from <= now()) then 1
      else 0
    end
    else 0
  end;
$$;

-- Zoals in 20261027000000_ai_quota.sql, met 'coach' bij de toegelaten soorten.
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
  if p_kind is null or p_kind not in ('label', 'recipe', 'coach') then
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

-- Hetzelfde lezen zonder iets te verhogen. Ongewijzigd van vorm; kent 'coach' via ai_limit hierboven.
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

-- De vlag: supporters vanaf nu, iedereen over 3 weken. Bestaat ze al, dan blijft ze zoals ze is.
insert into public.features (id, title_en, title_nl, early_from, public_from)
values ('coach', 'Weekly coach', 'Wekelijkse coach', now(), now() + interval '3 weeks')
on conflict do nothing;

-- Op de roadmap: klaar (op wat klaar is, kan niet meer gestemd worden)
update public.roadmap_items set status = 'done' where title_en = 'Weekly AI coach summary';
