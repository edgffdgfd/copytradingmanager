-- Market reach: ek naya column (purana data safe, dobara run karne se bhi dikkat nahi)
alter table risk_trades add column if not exists max_r numeric;
