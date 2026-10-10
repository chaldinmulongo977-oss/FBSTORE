-- FBStore Academy : MISE À JOUR COMPLÈTE. À exécuter UNE fois dans Supabase > SQL Editor, après votre schéma de base.
-- Idempotent : peut être relancé sans casser. Corrige aussi la sécurité (RLS) des tables coupons et site_settings.
create extension if not exists pgcrypto;
alter table courses add column if not exists pay_info text;
create table if not exists coupons(id uuid default gen_random_uuid() primary key, code text unique not null, discount_percent numeric default 0, discount_amount numeric default 0, active boolean default true, uses_count integer default 0, created_at timestamptz default now() not null);
create table if not exists site_settings(id uuid default gen_random_uuid() primary key, key text unique not null, value text);
alter table payments add column if not exists coupon_id uuid references coupons(id);
alter table payments add column if not exists confirmed_by uuid references profiles(id);
create table if not exists payment_requests(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, method text, reference text not null, amount numeric(10,2), currency text default 'USD', status text not null default 'pending' check (status in ('pending','approved','rejected')), created_at timestamptz default now());
alter table payment_requests add column if not exists coupon_code text;
alter table payment_requests add column if not exists coupon_id uuid references coupons(id);
create table if not exists testimonials(id uuid primary key default gen_random_uuid(), name text not null, text text not null, created_at timestamptz default now());
create table if not exists saspay_attempts(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, idempotency_key uuid not null default gen_random_uuid(), payment_id text unique, amount numeric(10,2), currency text, status text not null default 'PENDING', created_at timestamptz default now());
alter table saspay_attempts add column if not exists coupon_id uuid references coupons(id);
insert into site_settings(key,value) values ('fb_pixel',''),('google_analytics',''),('whatsapp',''),('support_email','') on conflict (key) do nothing;

-- Fonctions. is_admin exige la double authentification (aal2) dès que l'admin l'a activée.
create or replace function is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles where id=auth.uid() and role='super_admin')
  and (coalesce(auth.jwt()->>'aal','aal1')='aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified')) $$;
create or replace function is_premium() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles where id=auth.uid() and status='PREMIUM') $$;
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,email,name,phone,role) values(new.id,lower(new.email),coalesce(new.raw_user_meta_data->>'name',''),coalesce(new.raw_user_meta_data->>'phone',''),
  case when exists(select 1 from super_admins where lower(email)=lower(new.email)) then 'super_admin' else 'user' end); return new; end $$;
drop trigger if exists on_signup on auth.users;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();
create or replace function guard_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin if auth.uid() is not null then new.role:=old.role; new.email:=old.email; if not is_admin() then new.status:=old.status; end if; end if; return new; end $$;
drop trigger if exists guard on profiles;
create trigger guard before update on profiles for each row execute function guard_profile();
update profiles set role='super_admin' where lower(email) in (select lower(email) from super_admins);

-- Prix et codes promo calculés côté serveur uniquement
create or replace function quote(p_code text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare c courses; k coupons; f numeric;
begin select * into c from courses order by created_at limit 1;
  if c.id is null then return jsonb_build_object('valid',false,'price',0,'final',0); end if;
  if p_code is not null and length(trim(p_code))>0 then
    select * into k from coupons where upper(code)=upper(trim(p_code)) and active;
    if k.id is not null then
      f:=greatest(c.price - c.price*coalesce(k.discount_percent,0)/100 - coalesce(k.discount_amount,0),0);
      return jsonb_build_object('valid',true,'price',c.price,'final',round(f,2),'coupon_id',k.id,'currency',c.currency);
    end if;
  end if;
  return jsonb_build_object('valid',false,'price',c.price,'final',c.price,'currency',c.currency);
end $$;
create or replace function bump_coupon(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin if auth.uid() is not null and not is_admin() then raise exception 'forbidden'; end if; update coupons set uses_count=uses_count+1 where id=p_id; end $$;
revoke all on function quote(text) from public; grant execute on function quote(text) to authenticated, service_role;
revoke all on function bump_coupon(uuid) from public; grant execute on function bump_coupon(uuid) to authenticated, service_role;
create or replace function pr_price() returns trigger language plpgsql security definer set search_path=public as $$
declare q jsonb; begin q:=quote(new.coupon_code); new.amount:=(q->>'final')::numeric; new.coupon_id:=(q->>'coupon_id')::uuid;
  new.currency:=(select currency from courses order by created_at limit 1); return new; end $$;
drop trigger if exists pr_price on payment_requests;
create trigger pr_price before insert on payment_requests for each row execute function pr_price();
create or replace function student_count() returns int language sql stable security definer set search_path=public as $$ select count(*)::int from profiles where status='PREMIUM' and role='user' $$;
grant execute on function student_count() to anon, authenticated;

-- RLS partout (coupons et site_settings n'étaient PAS protégées : n'importe qui avec la clé publique pouvait les modifier)
alter table super_admins enable row level security; alter table profiles enable row level security; alter table courses enable row level security;
alter table modules enable row level security; alter table progress enable row level security; alter table payments enable row level security;
alter table coupons enable row level security; alter table site_settings enable row level security; alter table payment_requests enable row level security;
alter table testimonials enable row level security; alter table saspay_attempts enable row level security;
drop policy if exists p_sel on profiles; create policy p_sel on profiles for select using (id=auth.uid() or is_admin());
drop policy if exists p_upd on profiles; create policy p_upd on profiles for update using (id=auth.uid() or is_admin());
drop policy if exists c_sel on courses; create policy c_sel on courses for select using (true);
drop policy if exists c_adm on courses; create policy c_adm on courses for all using (is_admin()) with check (is_admin());
drop policy if exists m_sel on modules; create policy m_sel on modules for select using (is_free or is_premium() or is_admin());
drop policy if exists m_adm on modules; create policy m_adm on modules for all using (is_admin()) with check (is_admin());
drop policy if exists g_own on progress; create policy g_own on progress for all using (user_id=auth.uid()) with check (user_id=auth.uid());
drop policy if exists g_adm on progress; create policy g_adm on progress for select using (is_admin());
drop policy if exists y_sel on payments; create policy y_sel on payments for select using (user_id=auth.uid() or is_admin());
drop policy if exists y_ins on payments; create policy y_ins on payments for insert with check (is_admin());
drop policy if exists pr_sel on payment_requests; create policy pr_sel on payment_requests for select using (user_id=auth.uid() or is_admin());
drop policy if exists pr_ins on payment_requests; create policy pr_ins on payment_requests for insert with check (user_id=auth.uid() and status='pending');
drop policy if exists pr_adm on payment_requests; create policy pr_adm on payment_requests for update using (is_admin()) with check (is_admin());
drop policy if exists t_sel on testimonials; create policy t_sel on testimonials for select using (true);
drop policy if exists t_adm on testimonials; create policy t_adm on testimonials for all using (is_admin()) with check (is_admin());
drop policy if exists sa_sel on saspay_attempts; create policy sa_sel on saspay_attempts for select using (user_id=auth.uid() or is_admin());
drop policy if exists k_adm on coupons; create policy k_adm on coupons for all using (is_admin()) with check (is_admin());   -- les codes ne sont jamais lisibles par les élèves
drop policy if exists s_sel on site_settings; create policy s_sel on site_settings for select using (key in ('fb_pixel','google_analytics','whatsapp','support_email'));
drop policy if exists s_adm on site_settings; create policy s_adm on site_settings for all using (is_admin()) with check (is_admin());
create or replace view module_list as select id,course_id,position,title,description,is_free from modules;
grant select on module_list to anon, authenticated;
