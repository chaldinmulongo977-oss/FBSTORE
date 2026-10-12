-- ===== Notifications push (upgrade6) =====
create table if not exists push_subscriptions(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, endpoint text unique not null, p256dh text not null, auth text not null, created_at timestamptz default now());
create table if not exists notifications(id uuid primary key default gen_random_uuid(), title text not null, body text, url text, audience text, sent int default 0, failed int default 0, created_by uuid references profiles on delete set null, created_at timestamptz default now());
alter table push_subscriptions enable row level security; alter table notifications enable row level security;
drop policy if exists psub_own on push_subscriptions; create policy psub_own on push_subscriptions for select using (user_id=auth.uid() or has_perm('settings'));
drop policy if exists psub_del on push_subscriptions; create policy psub_del on push_subscriptions for delete using (user_id=auth.uid());
drop policy if exists notif_sel on notifications; create policy notif_sel on notifications for select using (has_perm('settings'));
create or replace function save_push(p_endpoint text, p_p256dh text, p_auth text) returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  insert into push_subscriptions(user_id,endpoint,p256dh,auth) values(auth.uid(),p_endpoint,p_p256dh,p_auth)
  on conflict (endpoint) do update set user_id=auth.uid(), p256dh=excluded.p256dh, auth=excluded.auth;
end $$;
revoke all on function save_push(text,text,text) from public; grant execute on function save_push(text,text,text) to authenticated;

-- ===== upgrade6 (suite) : clés SasPay saisies dans l'admin + suivi détaillé des paiements =====
-- Coffre à secrets : RLS activée SANS aucune policy = illisible/inscriptible depuis le navigateur.
-- Seules les fonctions serveur (service_role) y accèdent. Les clés ne sont jamais renvoyées en clair à l'admin (aperçu masqué seulement).
create table if not exists payment_secrets(key text primary key, value text, updated_at timestamptz default now());
alter table payment_secrets enable row level security;
revoke all on payment_secrets from anon, authenticated;

alter table saspay_attempts add column if not exists full_name text;
alter table saspay_attempts add column if not exists phone text;
alter table saspay_attempts add column if not exists email text;
alter table saspay_attempts add column if not exists country text;
alter table saspay_attempts add column if not exists network text;
alter table saspay_attempts add column if not exists is_test boolean not null default false;
alter table saspay_attempts add column if not exists mode text;
alter table saspay_attempts add column if not exists checkout_url text;
alter table saspay_attempts add column if not exists error text;
alter table saspay_attempts add column if not exists sent_amount numeric(14,2);
alter table saspay_attempts add column if not exists sent_currency text;
alter table saspay_attempts add column if not exists updated_at timestamptz default now();
create index if not exists saspay_attempts_status_idx on saspay_attempts(status, created_at desc);
drop policy if exists sa_sel on saspay_attempts;
create policy sa_sel on saspay_attempts for select using (user_id=auth.uid() or has_perm('payments'));
