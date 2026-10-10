-- À exécuter seulement si schema.sql a déjà été exécuté avant l'ajout de SasPay

-- SasPay : suivi des tentatives de paiement (écrit uniquement par la fonction serveur "saspay").
create table saspay_attempts(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, idempotency_key uuid not null default gen_random_uuid(), payment_id text unique, amount numeric(10,2), currency text, status text not null default 'PENDING', created_at timestamptz default now());
alter table saspay_attempts enable row level security;
create policy sa_sel on saspay_attempts for select using (user_id=auth.uid() or is_admin());
