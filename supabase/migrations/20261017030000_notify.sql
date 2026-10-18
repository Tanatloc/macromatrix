-- Meldingen op de gsm bij een nieuwe battle-uitdaging, zonder dat de achtergrondtaak je sessie nodig heeft.
-- Elk toestel krijgt een willekeurige code (uuid) die alleen toelaat om de namen van openstaande uitdagingen
-- aan jou op te vragen. Uitloggen of het account verwijderen ruimt de codes op.

create table if not exists public.notify_tokens (
  token uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.notify_tokens enable row level security;
-- Geen policies: alleen bereikbaar via de functies hieronder

create or replace function public.notify_register() returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  t uuid;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  insert into public.notify_tokens (user_id) values (me) returning token into t;
  -- Hoogstens 5 toestellen per gebruiker
  delete from public.notify_tokens x
  where x.user_id = me and x.token not in (
    select y.token from public.notify_tokens y where y.user_id = me order by y.created_at desc limit 5
  );
  return t;
end;
$$;

create or replace function public.notify_unregister(p_token uuid) returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.notify_tokens x where x.token = p_token and x.user_id = auth.uid();
$$;

-- Openstaande uitdagingen aan de eigenaar van de code: id en naam van wie uitdaagt
create or replace function public.pending_challenges(p_token uuid)
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id, coalesce(p.name, '')
  from public.notify_tokens t
  join public.battles b on b.opponent = t.user_id
  left join public.friend_profiles p on p.user_id = b.challenger
  where t.token = p_token
    and not b.accepted
    and b.week >= current_date - 7
  order by b.created_at desc
  limit 10;
$$;

revoke all on function public.notify_register() from public, anon;
revoke all on function public.notify_unregister(uuid) from public, anon;
revoke all on function public.pending_challenges(uuid) from public;
grant execute on function public.notify_register() to authenticated;
grant execute on function public.notify_unregister(uuid) to authenticated;
grant execute on function public.pending_challenges(uuid) to anon, authenticated;
