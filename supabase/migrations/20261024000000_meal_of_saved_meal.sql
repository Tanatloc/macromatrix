-- Opgeslagen maaltijden onthouden bij welke maaltijd ze horen (0 = ontbijt ... 3 = snacks; leeg bij oudere).
-- Eerst toepassen, dan pas een app-versie uitbrengen die deze kolom meestuurt.
alter table public.meals add column if not exists meal integer;
alter table public.meals add constraint meals_meal check (meal is null or (meal >= 0 and meal <= 10)) not valid;
