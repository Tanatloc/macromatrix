-- Een AI-tekst melden (Google Play-beleid voor generatieve AI: melden of vlaggen in de app zelf).
--
-- Onder de wekelijkse coach staat een vlagje "Report this text". Een melding bewaart de tekst (samenvatting en tips),
-- de soort (p_kind: 'coach', later ook 'photo', 'label', 'recipe', 'voice'), en in de notitie de week, het model en
-- wat de gebruiker eventueel schreef. Alleen bij een melding wordt een AI-tekst bewaard; anders niets.
--
-- Gebruikers kunnen meldingen niet lezen of wijzigen; alleen de beheerder bekijkt ze (SQL-editor). Toevoegen gaat
-- alleen via ai_report, hoogstens 20 per dag per persoon. Een melding verdwijnt als je je account wist.
--
-- Eerst toepassen in de SQL-editor. Zonder deze migratie zegt de app "De melding kon niet weg" (PGRST202).

create table public.ai_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('coach', 'photo', 'label', 'recipe', 'voice', 'other')),
  text text not null check (char_length(text) between 1 and 4000),
  note text check (note is null or char_length(note) <= 1000),
  created_at timestamptz not null default now()
);
create index ai_reports_reporter on public.ai_reports (reporter, created_at);

-- Geen policies: niemand leest of schrijft rechtstreeks, melden gaat via ai_report
alter table public.ai_reports enable row level security;
revoke all on table public.ai_reports from public, anon, authenticated;

-- Een AI-tekst melden. Geeft terug: reported, limit, bad_kind of empty.
create or replace function public.ai_report(p_kind text, p_text text, p_note text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  t text := left(btrim(coalesce(p_text, '')), 4000);
  n text := nullif(left(btrim(coalesce(p_note, '')), 1000), '');
begin
  if me is null then
    raise exception 'niet ingelogd';
  end if;
  if p_kind is null or p_kind not in ('coach', 'photo', 'label', 'recipe', 'voice', 'other') then
    return 'bad_kind';
  end if;
  if t = '' then
    return 'empty';
  end if;
  if (select count(*) from public.ai_reports r where r.reporter = me and r.created_at > now() - interval '1 day') >= 20 then
    return 'limit';
  end if;
  insert into public.ai_reports (reporter, kind, text, note) values (me, p_kind, t, n);
  return 'reported';
end;
$$;

revoke all on function public.ai_report(text, text, text) from public, anon;
grant execute on function public.ai_report(text, text, text) to authenticated;
