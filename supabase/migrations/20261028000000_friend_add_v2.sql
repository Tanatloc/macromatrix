-- friend_add_v2: zoals friend_add, maar zegt ook wanneer jullie al vrienden zijn en met wie.
--
-- friend_add gaf voor een bestaande vriendschap 'accepted' (als de ander ooit het verzoek stuurde) of 'already'
-- (als jij het stuurde), waardoor de app "Jullie zijn nu vrienden" of "Je stuurde al een verzoek" toonde terwijl
-- jullie al lang vrienden waren. Deze versie geeft dan 'friends' terug, en bij elke gevonden code ook de id van de
-- ander, zodat de app de naam uit de vriendenlijst kan tonen ("Je bent al vrienden met Jens").
--
-- Uitkomsten: requested, accepted, already, friends, self, not_found. friend_add blijft bestaan voor oudere apps.

create or replace function public.friend_add_v2(p_code text)
returns table (result text, other uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  o uuid;
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
  -- Verder precies zoals friend_add (verzoek sturen, of een verzoek van de ander aanvaarden)
  return query select public.friend_add(p_code), o;
end;
$$;

revoke all on function public.friend_add_v2(text) from public, anon;
grant execute on function public.friend_add_v2(text) to authenticated;
