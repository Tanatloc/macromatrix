-- Google Play Billing: welke aankoop (purchase token) bij welk account hoort.
--
-- Alleen /api/play-verify en /api/play-rtdn (Cloudflare, met de service-role) lezen en schrijven hierin. Eén aankoop
-- hoort bij één account: een token dat al aan een ander account hangt, wordt geweigerd. Een wissel van abonnement of
-- een nieuw abonnement na het opzeggen (linked_purchase_token) blijft bij hetzelfde account.
--
-- We bewaren alleen het token, het product en de vervaldatum; geen naam, e-mail of betaalgegevens (die heeft alleen
-- Google). Weg met het account (on delete cascade).
--
-- pro_status.source mag al elke tekst van 1 tot 40 tekens zijn (migratie 20261026000000_pro.sql), dus 'play' kan.

create table public.play_purchases (
  purchase_token text primary key check (char_length(purchase_token) between 10 and 4096),
  user_id uuid not null references auth.users on delete cascade,
  product text not null check (product in ('pro_monthly', 'pro_yearly')),
  -- De vorige aankoop bij een wissel of een nieuw abonnement (zoals Google het meegeeft)
  linked_purchase_token text,
  -- Tot wanneer deze aankoop Pro geeft (na een einde of terugbetaling: het moment waarop ze stopte)
  expiry timestamptz not null,
  updated_at timestamptz not null default now()
);

create index play_purchases_user on public.play_purchases (user_id, expiry desc);

-- RLS aan en geen policies: de app kan hier niets lezen of schrijven, alleen de service-role
alter table public.play_purchases enable row level security;
revoke all on public.play_purchases from public, anon, authenticated;
grant select, insert, update, delete on public.play_purchases to service_role;
