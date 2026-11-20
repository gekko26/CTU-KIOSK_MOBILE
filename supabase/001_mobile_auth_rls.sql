-- CTU Kiosk Mobile: lock the kiosk tables to signed-in staff.
-- Run once in the NEW Supabase project: Dashboard → SQL Editor → paste → Run.
--
-- Who can do what after this:
--   * Kiosk (Pi, uses the sb_secret_ key): unchanged. Secret keys bypass RLS.
--   * Mobile app, signed in:              can READ transactions, breakdown, counters.
--   * Anyone with only the publishable key (not signed in): sees nothing.
--
-- Safe to run more than once.

alter table public.transactions          enable row level security;
alter table public.transaction_breakdown enable row level security;
alter table public.ticket_counters       enable row level security;

drop policy if exists "staff can read transactions"          on public.transactions;
drop policy if exists "staff can read transaction_breakdown" on public.transaction_breakdown;
drop policy if exists "staff can read ticket_counters"       on public.ticket_counters;

create policy "staff can read transactions"
  on public.transactions for select
  to authenticated
  using (true);

create policy "staff can read transaction_breakdown"
  on public.transaction_breakdown for select
  to authenticated
  using (true);

create policy "staff can read ticket_counters"
  on public.ticket_counters for select
  to authenticated
  using (true);

-- Remove direct table access for logged-out visitors as a second layer.
revoke all on public.transactions          from anon;
revoke all on public.transaction_breakdown from anon;
revoke all on public.ticket_counters       from anon;

-- Check: every row should show rowsecurity = true.
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('transactions', 'transaction_breakdown', 'ticket_counters');
