-- ===== COPY TRADING MANAGER: poora database (Supabase SQL Editor mein paste karke Run karo) =====
create extension if not exists pgcrypto;
create sequence if not exists inv_seq;

-- 1) Tables
create table profiles(id uuid primary key references auth.users on delete cascade, role text not null default 'investor' check(role in('admin','investor')));
create table investors(
  id uuid primary key default gen_random_uuid(),
  code text unique default 'INV-'||lpad(nextval('inv_seq')::text,4,'0'),   -- auto Investor ID
  name text not null, phone text, email text, notes text,
  join_date date default current_date,
  status text default 'active' check(status in('active','inactive')),
  share_pct numeric default 100 check(share_pct between 0 and 100));      -- investor ka profit hissa %
create table accounts(
  id uuid primary key default gen_random_uuid(),
  investor_id uuid not null references investors on delete restrict,
  account_no text not null, broker text, platform text, acc_type text,
  start_balance numeric default 0, start_date date default current_date,
  current_balance numeric default 0, status text default 'active');
create table transactions(                                                -- append-only ledger
  id uuid primary key default gen_random_uuid(),
  investor_id uuid not null references investors, account_id uuid references accounts,
  type text not null check(type in('deposit','withdrawal','profit_share','profit_payout')),
  amount numeric not null check(amount<>0),                               -- galti = ulta (negative) entry
  currency text default 'USD', tx_date date default current_date,
  method text, reference text, notes text,
  proofs text[] default '{}',                                             -- proof image paths
  created_by uuid default auth.uid(), created_at timestamptz default now());
create table daily_profit(
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts, pdate date not null,
  amount numeric not null, unique(account_id,pdate));
create table audit_log(id bigserial primary key, who uuid, tbl text, action text, row_data jsonb, at timestamptz default now());

-- 2) Helper functions
create function is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
create function my_investor_ids() returns setof uuid language sql stable security definer set search_path=public as
$$ select id from investors where lower(email)=lower(auth.jwt()->>'email') $$;

-- Sabse pehla signup = admin (aap), baaki investor
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as
$$ begin insert into profiles(id,role) values(new.id, case when exists(select 1 from profiles) then 'investor' else 'admin' end); return new; end $$;
create trigger on_auth_user after insert on auth.users for each row execute function handle_new_user();

-- 3) Audit log (kisne, kab, kya)
create function log_change() returns trigger language plpgsql security definer set search_path=public as
$$ begin insert into audit_log(who,tbl,action,row_data) values(auth.uid(),tg_table_name,tg_op,to_jsonb(new)); return new; end $$;
create trigger a1 after insert or update on investors for each row execute function log_change();
create trigger a2 after insert or update on accounts for each row execute function log_change();
create trigger a3 after insert or update on transactions for each row execute function log_change();
create trigger a4 after insert or update on daily_profit for each row execute function log_change();

-- 4) Auto calculation view (hamesha current numbers)
create view investor_summary with(security_invoker=true) as
select i.id,i.code,i.name,i.status,i.share_pct,
  coalesce(t.dep,0) invested, coalesce(t.wd,0) withdrawn,
  coalesce(p.tot,0)*i.share_pct/100 profit_earned,
  coalesce(t.paid,0) profit_paid,
  coalesce(p.tot,0)*i.share_pct/100 - coalesce(t.paid,0) profit_pending,
  coalesce(t.dep,0)-coalesce(t.wd,0)+coalesce(p.tot,0)*i.share_pct/100-coalesce(t.paid,0) remaining,
  case when coalesce(t.dep,0)>0 then round(coalesce(p.tot,0)*i.share_pct/100/t.dep*100,2) else 0 end roi_pct
from investors i
left join (select investor_id,
   sum(amount) filter(where type='deposit') dep,
   sum(amount) filter(where type='withdrawal') wd,
   sum(amount) filter(where type='profit_payout') paid
   from transactions group by 1) t on t.investor_id=i.id
left join (select a.investor_id,sum(d.amount) tot from daily_profit d join accounts a on a.id=d.account_id group by 1) p on p.investor_id=i.id;

-- 5) Security (RLS): admin sab, investor sirf apna (read-only)
alter table profiles enable row level security;  alter table investors enable row level security;
alter table accounts enable row level security;  alter table transactions enable row level security;
alter table daily_profit enable row level security; alter table audit_log enable row level security;

create policy p0 on profiles for select to authenticated using(id=auth.uid() or is_admin());
create policy i1 on investors for all to authenticated using(is_admin()) with check(is_admin());
create policy i2 on investors for select to authenticated using(id in(select my_investor_ids()));
create policy a1 on accounts for all to authenticated using(is_admin()) with check(is_admin());
create policy a2 on accounts for select to authenticated using(investor_id in(select my_investor_ids()));
create policy t1 on transactions for select to authenticated using(is_admin() or investor_id in(select my_investor_ids()));
create policy t2 on transactions for insert to authenticated with check(is_admin());   -- update/delete ki policy hi nahi = delete impossible
revoke update,delete on transactions from authenticated;
create policy d1 on daily_profit for all to authenticated using(is_admin()) with check(is_admin());
create policy d2 on daily_profit for select to authenticated using(account_id in(select id from accounts where investor_id in(select my_investor_ids())));
create policy l1 on audit_log for select to authenticated using(is_admin());

-- 6) Private storage bucket (proof images)
insert into storage.buckets(id,name,public) values('proofs','proofs',false) on conflict do nothing;
create policy s1 on storage.objects for all to authenticated using(bucket_id='proofs' and is_admin()) with check(bucket_id='proofs' and is_admin());
create policy s2 on storage.objects for select to authenticated using(bucket_id='proofs' and (storage.foldername(name))[1] in(select i::text from my_investor_ids() i));
