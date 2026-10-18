-- Levels en profielfoto's bij vrienden: je avatar (standaardavatar of kleine foto, max. ~75 kB) en je level.
-- Alleen zichtbaar voor mensen met wie je een vriendschap of verzoek hebt (via friend_list).

alter table public.friend_profiles
  add column avatar text check (avatar is null or char_length(avatar) <= 100000),
  add column level integer not null default 1 check (level between 1 and 100000);

-- friend_me krijgt avatar en level erbij (andere parameters, dus eerst de oude weg)
drop function public.friend_me(text);

create function public.friend_me(p_name text default null, p_avatar text default null, p_level integer default null)
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
    level = coalesce(greatest(1, p_level), p.level),
    updated_at = now()
  where p.user_id = me;
  return query select p.code, p.name from public.friend_profiles p where p.user_id = me;
end;
$$;

drop function public.friend_list(date);

create function public.friend_list(p_week date)
returns table (other uuid, name text, state text, score smallint, days smallint, prev_score smallint, prev_days smallint, avatar text, level integer)
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
    w.score, w.days, v.score, v.days, p.avatar, coalesce(p.level, 1)
  from mine m
  left join public.friend_profiles p on p.user_id = m.other
  left join public.weekly_scores w on m.state = 'friend' and w.user_id = m.other and w.week = p_week
  left join public.weekly_scores v on m.state = 'friend' and v.user_id = m.other and v.week = p_week - 7
  order by m.state, coalesce(p.name, '');
$$;

revoke all on function public.friend_me(text, text, integer) from public, anon;
revoke all on function public.friend_list(date) from public, anon;
grant execute on function public.friend_me(text, text, integer) to authenticated;
grant execute on function public.friend_list(date) to authenticated;
