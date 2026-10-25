-- Dagtellers voor spraak (/api/voice) en delen met Open Food Facts (/api/off-contribute), en een onthouden Pro onder
-- een Play-abonnement.
--
-- 1. Twee nieuwe soorten in dezelfde teller als etiketten, recepten en de coach (ai_usage, ai_quota_use):
--      voice: 60 per dag, 200 met Pro (Whisper op Cloudflare kost per opname)
--      off:   10 per dag, met of zonder Pro (alles gaat onder het ene account van de app bij Open Food Facts)
--    Tot nu hadden die alleen een rem per uur in de cache van Cloudflare, en die is met veel verzoeken tegelijk te
--    omzeilen. ai_quota_use telt in één stap in de database, dus ook veilig bij verzoeken tegelijk.
-- 2. pro_status.base_until en base_source: verlengt een Play-abonnement een kortere Pro met de hand of als geschenk,
--    dan onthoudt de server die hier (functions/_lib/play.js, grantPro). Na een terugbetaling of het einde van het
--    abonnement komt die Pro terug (tot base_until, met base_source) in plaats van te stoppen op dat moment.
--    Alleen de server schrijft hierin (service-role); de app leest de rij zoals vroeger.
--
-- Bouwt verder op 20261027000000_ai_quota.sql, 20261103000000_coach.sql en 20261026000000_pro.sql. Eerst toepassen in
-- de SQL-editor. Zonder deze migratie werken /api/voice en /api/off-contribute met alleen de rem per uur (de oude
-- ai_quota_use antwoordt "onbekende soort"), en werkt Play zoals vroeger.

-- 'voice' en 'off' toelaten in de teller (de naam van de check komt van Postgres: <tabel>_<kolom>_check)
alter table public.ai_usage drop constraint if exists ai_usage_kind_check;
alter table public.ai_usage add constraint ai_usage_kind_check check (kind in ('label', 'recipe', 'coach', 'voice', 'off'));

-- Hoeveel per dag, per soort, met of zonder Pro. Een onbekende soort mag nooit (0). Zoals in 20261103000000_coach.sql,
-- met 'voice' en 'off' erbij.
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
    when 'voice' then case when p_pro then 200 else 60 end
    when 'off' then 10
    else 0
  end;
$$;

-- Zoals in 20261103000000_coach.sql, met 'voice' en 'off' bij de toegelaten soorten.
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
  if p_kind is null or p_kind not in ('label', 'recipe', 'coach', 'voice', 'off') then
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

-- ai_quota (alleen lezen) blijft zoals het is: het kent de nieuwe soorten via ai_limit hierboven.

revoke all on function public.ai_limit(text, boolean) from public, anon;
revoke all on function public.ai_quota_use(text) from public, anon;
grant execute on function public.ai_limit(text, boolean) to authenticated;
grant execute on function public.ai_quota_use(text) to authenticated;

-- De Pro van vóór een Play-abonnement (met de hand, geschenk, web), zolang die korter liep dan het abonnement.
-- Beide leeg = niets onthouden. De app kan hier niets schrijven (zie 20261026000000_pro.sql: geen policies om te
-- schrijven, geen rechten).
alter table public.pro_status add column if not exists base_until timestamptz;
alter table public.pro_status add column if not exists base_source text
  check (base_source is null or char_length(base_source) between 1 and 40);
