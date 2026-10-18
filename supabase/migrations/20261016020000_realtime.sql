-- Live meldingen (Supabase Realtime): een toestel hoort meteen dat er op een ander toestel iets wijzigde en haalt
-- dan de wijzigingen op. Realtime controleert de beveiliging per gebruiker (RLS), net zoals bij gewone verzoeken.
alter publication supabase_realtime add table
  public.settings, public.foods, public.diary, public.meals, public.biometrics,
  public.notes, public.exercise, public.fasts, public.repeats;
