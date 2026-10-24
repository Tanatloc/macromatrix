-- Vier extra supporterranden: ripple (rimpeling), spin (draaikrans), sunburst (zonnestralen), crown (kroon).
-- Alleen de lijst met toegestane namen verandert; pro_set_frame krijgt dezelfde lijst.

alter table public.pro_status drop constraint if exists pro_status_frame_check;
alter table public.pro_status add constraint pro_status_frame_check
  check (frame is null or frame in ('glow', 'orbit', 'sparkle', 'laurel', 'ripple', 'spin', 'sunburst', 'crown', 'wings', 'blades', 'royal'));

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
  if p_frame is not null and p_frame not in ('glow', 'orbit', 'sparkle', 'laurel', 'ripple', 'spin', 'sunburst', 'crown', 'wings', 'blades', 'royal') then
    raise exception 'onbekende rand';
  end if;
  update public.pro_status s set frame = p_frame, updated_at = now()
  where s.user_id = me and s.until > now();
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.pro_set_frame(text) from public, anon;
grant execute on function public.pro_set_frame(text) to authenticated;
