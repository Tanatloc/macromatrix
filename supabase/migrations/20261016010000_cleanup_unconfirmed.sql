-- Accounts die nooit bevestigd werden, na 30 dagen wissen (zo staat het in het privacybeleid).
-- Dagelijks om 04:00 UTC met pg_cron.
create extension if not exists pg_cron;

select cron.schedule(
  'onbevestigde-accounts-opruimen',
  '0 4 * * *',
  $$delete from auth.users where email_confirmed_at is null and created_at < now() - interval '30 days'$$
);
