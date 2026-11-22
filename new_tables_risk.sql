-- ===== RISK MANAGER TABLES (purana data safe; dobara run karne se bhi dikkat nahi) =====
-- Supabase > SQL Editor mein paste karke Run karo.
create table if not exists risk_settings(
  id uuid primary key default gen_random_uuid(),
  start_capital numeric not null default 0,
  base_pct numeric not null default 2,
  high_pct numeric not null default 50,
  created_at timestamptz default now());
create table if not exists risk_trades(
  id uuid primary key default gen_random_uuid(),
  trade_date date not null default current_date,
  symbol text, risk_amount numeric not null, risk_pct numeric,
  mode text default 'base' check(mode in('base','high')),
  planned_rr numeric, pnl numeric not null, note text,
  created_at timestamptz default now());
create table if not exists risk_cash(
  id uuid primary key default gen_random_uuid(),
  tx_date date not null default current_date,
  kind text not null check(kind in('withdraw','deposit')),
  amount numeric not null check(amount>0), note text,
  created_at timestamptz default now());
alter table risk_settings enable row level security;
alter table risk_trades enable row level security;
alter table risk_cash enable row level security;
do $$ declare t text; begin
  foreach t in array array['risk_settings','risk_trades','risk_cash'] loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('create policy admin_all on %I for all to authenticated using(is_admin()) with check(is_admin())', t);
  end loop; end $$;
