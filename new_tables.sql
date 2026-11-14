-- ===== NAYI TABLES (purana data bilkul safe: koi purani table change/delete nahi hoti) =====
-- Supabase > SQL Editor mein paste karke Run karo. Dobara run karoge to bhi koi dikkat nahi.

create table if not exists bank_accounts(
  id uuid primary key default gen_random_uuid(),
  name text not null, acc_no text,
  purpose text default 'daily' check(purpose in('investment','profit_withdraw','daily','other')),
  opening_balance numeric default 0,
  created_at timestamptz default now());

create table if not exists expenses(
  id uuid primary key default gen_random_uuid(),
  exp_date date not null default current_date,
  amount numeric not null, category text default 'Other', note text,
  bank_id uuid references bank_accounts on delete set null,
  proofs text[] default '{}',
  created_at timestamptz default now());

create table if not exists bank_txns(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references bank_accounts on delete cascade,
  kind text not null check(kind in('in','out')),
  amount numeric not null check(amount>0),
  tx_date date not null default current_date,
  reason text, notes text,
  proofs text[] default '{}',
  expense_id uuid,
  created_at timestamptz default now());

create table if not exists setups(
  id uuid primary key default gen_random_uuid(),
  name text not null, description text,
  created_at timestamptz default now());

create table if not exists journal_trades(
  id uuid primary key default gen_random_uuid(),
  trade_date date not null default current_date,
  symbol text not null, side text, setup_id uuid references setups on delete set null,
  timeframe text, amount_used numeric, lot_size numeric,
  entry_price numeric, exit_price numeric, stop_loss numeric, target numeric,
  pnl numeric, reason text, notes text,
  created_at timestamptz default now());

create table if not exists trade_shots(
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references journal_trades on delete cascade,
  path text not null,
  created_at timestamptz default now());

-- Security: in sab tables ko sirf ADMIN (aap) dekh/badal sakte ho. Investors ko kuch nahi dikhega.
alter table bank_accounts enable row level security;
alter table expenses enable row level security;
alter table bank_txns enable row level security;
alter table setups enable row level security;
alter table journal_trades enable row level security;
alter table trade_shots enable row level security;

do $$ declare t text; begin
  foreach t in array array['bank_accounts','expenses','bank_txns','setups','journal_trades','trade_shots'] loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('create policy admin_all on %I for all to authenticated using(is_admin()) with check(is_admin())', t);
  end loop; end $$;

-- Photos: pehle se bani 'proofs' private bucket mein hi folders bank/, expense/, trades/ mein jayengi.
-- Us bucket ki admin policy pehle se hai (schema.sql ka s1), isliye kuch aur karna nahi.
