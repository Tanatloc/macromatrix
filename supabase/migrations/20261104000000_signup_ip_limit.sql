-- Hoogstens een paar nieuwe accounts per netwerk (IP-adres): tegen bots die met verzonnen adressen accounts aanmaken
-- en zo alle bevestigingsmails van de dag opgebruiken. Echte gebruikers merken er niets van.
--
-- Werkt als Auth-hook "Before User Created" (Supabase roept deze functie op vlak voor een nieuw account). We bewaren
-- het IP-adres niet zelf: alleen een hash ervan, en hoogstens een dag lang.
--
-- Aanzetten na deze migratie: Authentication → Hooks → "Before User Created" → Postgres-functie
-- public.hook_before_user_created.

create table public.signup_ips (
  ip_hash text not null,
  at timestamptz not null default now()
);
create index signup_ips_hash_at on public.signup_ips (ip_hash, at);

-- Niemand leest of schrijft hier rechtstreeks; alleen de hook (als supabase_auth_admin)
alter table public.signup_ips enable row level security;
revoke all on public.signup_ips from public, anon, authenticated;
grant select, insert, delete on public.signup_ips to supabase_auth_admin;
create policy "alleen de hook" on public.signup_ips as permissive for all to supabase_auth_admin using (true) with check (true);

create or replace function public.hook_before_user_created(event jsonb) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  ip text := nullif(event -> 'metadata' ->> 'ip_address', '');
  h text;
  last_hour integer;
  last_day integer;
begin
  -- Zonder IP (bv. een account dat de beheerder zelf aanmaakt): gewoon doorlaten
  if ip is null then
    return '{}'::jsonb;
  end if;
  -- md5 is ingebouwd: de hookgebruiker (supabase_auth_admin) mag niet in het schema extensions
  h := md5('macromatrix-signup:' || ip);
  delete from public.signup_ips s where s.at < now() - interval '1 day';
  select count(*) filter (where s.at > now() - interval '1 hour'), count(*) into last_hour, last_day
  from public.signup_ips s where s.ip_hash = h;
  if last_hour >= 3 or last_day >= 10 then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 429,
      'message', 'Too many new accounts from this network. Try again later.'
    ));
  end if;
  insert into public.signup_ips (ip_hash) values (h);
  return '{}'::jsonb;
end;
$$;

revoke all on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
