-- Level bij vrienden kan alleen nog stijgen: een toestel met een oudere versie van de app (die je level anders
-- berekent) kan het niet meer verlagen. greatest() negeert null, dus zonder p_level blijft het level staan.

create or replace function public.friend_me(p_name text default null, p_avatar text default null, p_level integer default null)
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
  update public.friend_profiles p set
    name = coalesce(left(btrim(p_name), 40), p.name),
    avatar = case when p_avatar is null then p.avatar else nullif(p_avatar, '') end,
    level = greatest(p.level, p_level),
    updated_at = now()
  where p.user_id = me;
  return query select p.code, p.name from public.friend_profiles p where p.user_id = me;
end;
$$;

