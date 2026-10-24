-- Supporterranden: wie Pro heeft, kiest een rand rond zijn avatar die vrienden zien (ranglijst, vriendenlijst,
-- battles, profiel). De kleur van de ring blijft altijd de kleur van je level; de rand verandert alleen de stijl.
--
-- Bekende randen: glow (gloed), orbit (omloop), sparkle (fonkeling), laurel (lauwerkrans). null = geen rand.
--
-- Wat anderen zien: alleen de naam van de rand, en alleen zolang Pro loopt en het Supporter-badge aanstaat. Loopt
-- Pro af, dan geeft friend_frames niets meer terug; de kolom blijft staan zodat je rand terugkomt als je opnieuw Pro
-- neemt.
--
-- Eerst toepassen in de SQL-editor (na block_report.sql); een app zonder deze migratie werkt gewoon verder, zonder
-- randen.

alter table public.pro_status add column if not exists frame text
  check (frame is null or frame in ('glow', 'orbit', 'sparkle', 'laurel'));

-- Je eigen Pro-status: {pro, until, source, show_badge, frame}. Zonder rij: pro = false en de rest null.
create or replace function public.my_pro() returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object(
       'pro', s.until > now(), 'until', s.until, 'source', s.source, 'show_badge', s.show_badge, 'frame', s.frame
     )
     from public.pro_status s where s.user_id = auth.uid()),
    jsonb_build_object('pro', false, 'until', null, 'source', null, 'show_badge', true, 'frame', null)
  );
$$;

-- Je rand kiezen (null = geen). Alleen je eigen rij, en alleen zolang Pro loopt. Geeft true als het lukte.
create or replace function public.pro_set_frame(p_frame text) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  n integer;
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if p_frame is not null and p_frame not in ('glow', 'orbit', 'sparkle', 'laurel') then
    raise exception 'onbekende rand';
  end if;
  update public.pro_status s set frame = p_frame, updated_at = now()
  where s.user_id = me and s.until > now();
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- De randen van wie je ziet: bevestigde vrienden, tegenstanders uit je battles en medespelers in je uitdagingen.
-- Alleen wie Pro heeft, het badge toont en een rand koos. Niemand die jij blokkeerde of die jou blokkeerde.
create or replace function public.friend_frames()
returns table (other uuid, frame text)
language sql
stable
security definer
set search_path = ''
as $$
  with people as (
    select case when f.requester = auth.uid() then f.addressee else f.requester end as other
    from public.friendships f
    where f.accepted and (f.requester = auth.uid() or f.addressee = auth.uid())
    union
    select case when b.challenger = auth.uid() then b.opponent else b.challenger end
    from public.battles b
    where b.challenger = auth.uid() or b.opponent = auth.uid()
    union
    select m2.user_id
    from public.challenge_members m1
    join public.challenge_members m2 on m2.challenge_id = m1.challenge_id and m2.user_id <> m1.user_id
    where m1.user_id = auth.uid() and m1.accepted and m2.accepted
  )
  select p.other, s.frame
  from people p
  join public.pro_status s on s.user_id = p.other
  where s.until > now() and s.show_badge and s.frame is not null
    and not exists (
      select 1 from public.user_blocks k
      where (k.blocker = auth.uid() and k.blocked = p.other) or (k.blocker = p.other and k.blocked = auth.uid())
    );
$$;

revoke all on function public.my_pro() from public, anon;
revoke all on function public.pro_set_frame(text) from public, anon;
revoke all on function public.friend_frames() from public, anon;
grant execute on function public.my_pro() to authenticated;
grant execute on function public.pro_set_frame(text) to authenticated;
grant execute on function public.friend_frames() to authenticated;
