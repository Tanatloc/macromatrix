-- Synchronisatie veiliger (review 2026-10-25). De app werkt ook zonder deze migratie; ze maakt twee dingen strenger
-- of eerlijker:
--
-- 1. sync_stamp: een tijd (updated_at, in ms) ver in de toekomst wordt begrensd op "nu + 5 minuten" (klok van de
--    server). Een toestel met een klok die voorloopt, kon anders met zijn versie elke latere wijziging van andere
--    toestellen blokkeren. De app vergelijkt na het versturen wat de server bewaarde (upsert ... returning) en neemt
--    de begrensde versie over (lib/sync/sync_engine.dart).
--
-- 2. limit_rows: telde elke upsert als nieuwe rij (de trigger draait "before insert", ook als de rij al bestaat en een
--    update wordt). Wie aan 50.000 rijen zat, kon zo ook niets meer wijzigen. Nu: een rij die er al is, telt niet; en
--    verwijderde rijen (deleted = 1) tellen niet mee voor de 50.000. Om de tabel toch te begrenzen, mogen er in totaal
--    (met verwijderde) hoogstens 200.000 zijn. Zelfde functienaam, de triggers blijven dus gewoon werken.

create or replace function public.sync_stamp() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  max_at bigint := (extract(epoch from now()) * 1000)::bigint + 5 * 60 * 1000;
begin
  -- Een klok die voorloopt: niet verder dan vijf minuten na nu
  if new.updated_at > max_at then
    new.updated_at := max_at;
  end if;
  if tg_op = 'UPDATE' then
    -- Een oudere versie (bv. van een toestel dat lang offline was) negeren
    if new.updated_at < old.updated_at then
      return null;
    end if;
    new.user_id := old.user_id;
  end if;
  new.server_ts := clock_timestamp();
  return new;
end;
$$;

create or replace function public.limit_rows() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  key_col text := case tg_table_name when 'settings' then 'key' when 'notes' then 'day' else 'id' end;
  has_deleted boolean := tg_table_name not in ('settings', 'notes');
  already boolean;
  live bigint;
  total bigint;
begin
  -- Een upsert van een rij die er al is, wordt een update: die telt niet
  execute format('select exists (select 1 from public.%I where user_id = $1 and %I = $2)', tg_table_name, key_col)
    into already using new.user_id, to_jsonb(new) ->> key_col;
  if already then
    return new;
  end if;
  if has_deleted then
    execute format('select count(*) filter (where deleted = 0), count(*) from public.%I where user_id = $1', tg_table_name)
      into live, total using new.user_id;
  else
    execute format('select count(*), count(*) from public.%I where user_id = $1', tg_table_name) into live, total using new.user_id;
  end if;
  if live >= 50000 or total >= 200000 then
    raise exception 'te veel rijen in %', tg_table_name using errcode = '54000';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_rows() from public, anon, authenticated;
