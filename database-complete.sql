-- FBStore Academy : BASE COMPLÈTE POUR UNE NOUVELLE INSTALLATION (à exécuter une seule fois dans Supabase > SQL Editor).
-- Si votre base existe déjà, n'exécutez PAS ce fichier : lancez seulement sql/upgrade.sql, puis upgrade2.sql, upgrade3.sql et upgrade4.sql.
-- Dans Authentication, laissez "Confirm email" ACTIVÉ.

-- FBStore Academy : à coller dans Supabase > SQL Editor. Dans Authentication, laissez "Confirm email" ACTIVÉ.
create extension if not exists pgcrypto;
create table super_admins(email text primary key);            -- liste blanche des super admins (modifiable seulement ici, en SQL)
create table profiles(id uuid primary key references auth.users on delete cascade, name text, email text unique, phone text,
  role text not null default 'user' check (role in ('user','super_admin')), status text not null default 'FREE' check (status in ('FREE','PREMIUM')), created_at timestamptz default now());
create table courses(id uuid primary key default gen_random_uuid(), title text not null, description text, thumbnail text, price numeric(10,2) not null default 10, currency text not null default 'USD', pay_url text, pay_info text, created_at timestamptz default now());
create table modules(id uuid primary key default gen_random_uuid(), course_id uuid references courses on delete cascade, position int not null, title text not null, description text, video_url text, is_free boolean not null default false);
create table progress(user_id uuid references profiles on delete cascade, module_id uuid references modules on delete cascade, completed boolean default false, progress_percentage int default 0, primary key(user_id,module_id));
create table payments(id uuid primary key default gen_random_uuid(), user_id uuid references profiles, amount numeric(10,2), currency text default 'USD', status text, transaction_id text unique, created_at timestamptz default now());

create function is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and role='super_admin') $$;
create function is_premium() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and status='PREMIUM') $$;

-- Le rôle est attribué à l'inscription, d'après l'email présent dans super_admins. Aucun bouton, aucune autre voie.
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,email,name,phone,role) values(new.id,lower(new.email),coalesce(new.raw_user_meta_data->>'name',''),coalesce(new.raw_user_meta_data->>'phone',''),
  case when exists(select 1 from super_admins where lower(email)=lower(new.email)) then 'super_admin' else 'user' end); return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

-- Un utilisateur ne peut jamais modifier son rôle, son email ou son statut Premium.
create function guard_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin if auth.uid() is not null then new.role:=old.role; new.email:=old.email; if not is_admin() then new.status:=old.status; end if; end if; return new; end $$;
create trigger guard before update on profiles for each row execute function guard_profile();

alter table super_admins enable row level security;  -- aucune policy = inaccessible depuis l'app
alter table profiles enable row level security; alter table courses enable row level security; alter table modules enable row level security;
alter table progress enable row level security; alter table payments enable row level security;
create policy p_sel on profiles for select using (id=auth.uid() or is_admin());
create policy p_upd on profiles for update using (id=auth.uid() or is_admin());
create policy c_sel on courses for select using (true);
create policy c_adm on courses for all using (is_admin()) with check (is_admin());
create policy m_sel on modules for select using (is_free or is_premium() or is_admin());   -- les vidéos Premium sont protégées côté base
create policy m_adm on modules for all using (is_admin()) with check (is_admin());
create policy g_own on progress for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy y_sel on payments for select using (user_id=auth.uid() or is_admin());      -- pas d'insert : réservé au webhook (service role)

create view module_list as select id,course_id,position,title,description,is_free from modules;  -- titres publics, sans video_url
grant select on module_list to anon, authenticated;

-- Exemple de contenu
with c as (insert into courses(title,description,price) values('Formation Importation Chine → Afrique','Alibaba, 1688, Pinduoduo : de la recherche produit à la livraison',10) returning id)
insert into modules(course_id,position,title,description,is_free)
select c.id,t.p,t.t,t.d,t.p=1 from c,(values (1,'Comprendre l''importation','Les bases'),(2,'Créer et utiliser Alibaba','Compte, recherche, messagerie'),(3,'Trouver les bons produits','Tendances et produits qui se vendent'),(4,'Trouver et vérifier les fournisseurs','Badges, avis, alertes'),(5,'Utiliser 1688','Prix usine'),(6,'Utiliser Pinduoduo','Petits prix, achats groupés'),(7,'Négocier avec les fournisseurs','Méthodes de négociation'),(8,'Passer une commande','Étapes et vérifications'),(9,'Comprendre les paiements','Moyens et protections'),(10,'Organiser le transport','Livraison vers la RDC'),(11,'Éviter les erreurs et les arnaques','Les pièges fréquents'),(12,'Lancer son activité','Coûts, marge, première vente')) t(p,t,d);
-- Votre email super admin (AVANT de créer votre compte) :
-- insert into super_admins values ('votre@email.com');

-- Paiement manuel (Mobile Money) : l'élève envoie sa référence, un super admin valide, l'accès Premium s'active.
create table payment_requests(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, method text, reference text not null, amount numeric(10,2), currency text default 'USD', status text not null default 'pending' check (status in ('pending','approved','rejected')), created_at timestamptz default now());
create table testimonials(id uuid primary key default gen_random_uuid(), name text not null, text text not null, created_at timestamptz default now());
alter table payment_requests enable row level security; alter table testimonials enable row level security;
create policy pr_sel on payment_requests for select using (user_id=auth.uid() or is_admin());
create policy pr_ins on payment_requests for insert with check (user_id=auth.uid() and status='pending');
create policy pr_adm on payment_requests for update using (is_admin()) with check (is_admin());
create policy y_ins on payments for insert with check (is_admin());
create policy t_sel on testimonials for select using (true);
create policy t_adm on testimonials for all using (is_admin()) with check (is_admin());
create function student_count() returns int language sql stable security definer set search_path=public as $$ select count(*)::int from profiles where status='PREMIUM' and role='user' $$;
grant execute on function student_count() to anon, authenticated;

-- Statistiques admin : permet au super admin de lire la progression de tous les élèves.
create policy g_adm on progress for select using (is_admin());

-- SasPay : suivi des tentatives de paiement (écrit uniquement par la fonction serveur "saspay").
create table saspay_attempts(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, idempotency_key uuid not null default gen_random_uuid(), payment_id text unique, amount numeric(10,2), currency text, status text not null default 'PENDING', created_at timestamptz default now());
alter table saspay_attempts enable row level security;
create policy sa_sel on saspay_attempts for select using (user_id=auth.uid() or is_admin());

-- Votre compte super admin (l'email est reconnu à l'inscription) :
insert into super_admins values ('chaldinmulongo977@gmail.com') on conflict do nothing;

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

-- FBStore Academy : ENVOI DE FICHIERS (vidéos/images depuis votre ordinateur) + réseaux de paiement. À exécuter après upgrade.sql. Idempotent.
alter table modules add column if not exists video_path text;
alter table modules add column if not exists thumbnail text;
create or replace view module_list as select id,course_id,position,title,description,is_free,thumbnail from modules;
grant select on module_list to anon, authenticated;
insert into site_settings(key,value) values ('saspay_networks','') on conflict (key) do nothing;
drop policy if exists s_sel on site_settings;
create policy s_sel on site_settings for select using (key in ('fb_pixel','google_analytics','whatsapp','support_email','saspay_networks'));

-- Espaces de stockage : "media" (images publiques) et "videos" (privé : lisible seulement si le module est accessible à l'élève)
insert into storage.buckets (id,name,public,allowed_mime_types) values
 ('media','media',true,array['image/jpeg','image/png','image/webp','image/gif']),
 ('videos','videos',false,array['video/mp4','video/webm','video/quicktime'])
on conflict (id) do nothing;
drop policy if exists media_read on storage.objects; create policy media_read on storage.objects for select using (bucket_id='media');
drop policy if exists media_ins on storage.objects;  create policy media_ins on storage.objects for insert with check (bucket_id='media' and public.is_admin());
drop policy if exists media_upd on storage.objects;  create policy media_upd on storage.objects for update using (bucket_id='media' and public.is_admin());
drop policy if exists media_del on storage.objects;  create policy media_del on storage.objects for delete using (bucket_id='media' and public.is_admin());
drop policy if exists vid_read on storage.objects;   create policy vid_read on storage.objects for select using (bucket_id='videos' and (public.is_admin() or exists(select 1 from public.modules m where m.video_path=name)));
drop policy if exists vid_ins on storage.objects;    create policy vid_ins on storage.objects for insert with check (bucket_id='videos' and public.is_admin());
drop policy if exists vid_upd on storage.objects;    create policy vid_upd on storage.objects for update using (bucket_id='videos' and public.is_admin());
drop policy if exists vid_del on storage.objects;    create policy vid_del on storage.objects for delete using (bucket_id='videos' and public.is_admin());

-- Accepter davantage de formats vidéo à l'envoi. À exécuter après upgrade2.sql.
update storage.buckets set allowed_mime_types=array['video/mp4','video/webm','video/quicktime','video/x-matroska','video/x-msvideo','video/ogg','video/3gpp','video/mpeg','video/x-m4v'] where id='videos';

-- Modification de l'email par l'élève : synchronise profiles.email après confirmation. À exécuter après upgrade3.sql.
create or replace function guard_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin if auth.uid() is not null and coalesce(current_setting('app.sync_email',true),'')<>'1' then new.role:=old.role; new.email:=old.email; if not is_admin() then new.status:=old.status; end if; end if; return new; end $$;
create or replace function sync_profile_email() returns trigger language plpgsql security definer set search_path=public as $$
begin perform set_config('app.sync_email','1',true); update profiles set email=lower(new.email) where id=new.id; return new; end $$;
drop trigger if exists on_email_change on auth.users;
create trigger on_email_change after update of email on auth.users for each row when (old.email is distinct from new.email) execute function sync_profile_email();

-- FBStore Academy : ÉQUIPE ET RÔLES, MAINTENANCE, SUPPORT, COMMUNAUTÉ, TRANSITAIRES, TOKEN FACEBOOK. À exécuter après upgrade4.sql. Idempotent.
create table if not exists private_settings(key text primary key, value text);
create table if not exists staff_roles(user_id uuid primary key references profiles on delete cascade, role text not null check (role in ('admin','comptable','marketing','influenceur','personnalise')), permissions text[] not null default '{}', created_by uuid references profiles on delete set null, created_at timestamptz default now());
alter table coupons add column if not exists owner_id uuid references profiles on delete set null;
alter table payments drop constraint if exists payments_user_id_fkey;
alter table payments add constraint payments_user_id_fkey foreign key (user_id) references profiles(id) on delete set null;
alter table payments drop constraint if exists payments_confirmed_by_fkey;
alter table payments add constraint payments_confirmed_by_fkey foreign key (confirmed_by) references profiles(id) on delete set null;
insert into site_settings(key,value) values ('maintenance',''),('maintenance_msg',''),('cert_signer',''),('cert_title',''),('cert_signature',''),('site_logo','') on conflict (key) do nothing;

create or replace function mfa_ok() returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(auth.jwt()->>'aal','aal1')='aal2' or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified') $$;
create or replace function is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles where id=auth.uid() and role='super_admin') and mfa_ok() $$;
create or replace function has_perm(p text) returns boolean language sql stable security definer set search_path=public as $$
  select is_admin() or (mfa_ok() and exists(select 1 from staff_roles s where s.user_id=auth.uid() and p = any(s.permissions))) $$;
create or replace function is_maintenance() returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select value from site_settings where key='maintenance'),'')='1' $$;
create or replace function guard_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin if auth.uid() is not null and coalesce(current_setting('app.sync_email',true),'')<>'1' then new.role:=old.role; new.email:=old.email; if not has_perm('users') then new.status:=old.status; end if; end if; return new; end $$;

alter table private_settings enable row level security; alter table staff_roles enable row level security;
drop policy if exists ps_adm on private_settings; create policy ps_adm on private_settings for all using (has_perm('settings')) with check (has_perm('settings'));
drop policy if exists sr_sel on staff_roles; create policy sr_sel on staff_roles for select using (user_id=auth.uid() or is_admin());
drop policy if exists sr_adm on staff_roles; create policy sr_adm on staff_roles for all using (is_admin()) with check (is_admin());   -- seuls les super admins gèrent l'équipe
drop policy if exists p_sel on profiles; create policy p_sel on profiles for select using (id=auth.uid() or has_perm('users') or has_perm('payments') or has_perm('stats'));
drop policy if exists p_upd on profiles; create policy p_upd on profiles for update using (id=auth.uid() or has_perm('users'));
drop policy if exists c_adm on courses; create policy c_adm on courses for all using (has_perm('content')) with check (has_perm('content'));
drop policy if exists m_sel on modules; create policy m_sel on modules for select using ((not is_maintenance() and (is_free or is_premium())) or has_perm('content'));
drop policy if exists m_adm on modules; create policy m_adm on modules for all using (has_perm('content')) with check (has_perm('content'));
drop policy if exists k_adm on coupons; create policy k_adm on coupons for all using (has_perm('coupons')) with check (has_perm('coupons'));
drop policy if exists k_own on coupons; create policy k_own on coupons for select using (owner_id=auth.uid());
drop policy if exists t_adm on testimonials; create policy t_adm on testimonials for all using (has_perm('testimonials')) with check (has_perm('testimonials'));
drop policy if exists y_sel on payments; create policy y_sel on payments for select using (user_id=auth.uid() or has_perm('payments') or has_perm('stats'));
drop policy if exists y_ins on payments; create policy y_ins on payments for insert with check (has_perm('payments'));
drop policy if exists pr_sel on payment_requests; create policy pr_sel on payment_requests for select using (user_id=auth.uid() or has_perm('payments'));
drop policy if exists pr_adm on payment_requests; create policy pr_adm on payment_requests for update using (has_perm('payments')) with check (has_perm('payments'));
drop policy if exists g_adm on progress; create policy g_adm on progress for select using (has_perm('stats'));
drop policy if exists sa_sel on saspay_attempts; create policy sa_sel on saspay_attempts for select using (user_id=auth.uid() or has_perm('payments'));
drop policy if exists s_sel on site_settings; create policy s_sel on site_settings for select using (key in ('fb_pixel','google_analytics','whatsapp','support_email','saspay_networks','maintenance','maintenance_msg','cert_signer','cert_title','cert_signature','site_logo'));
drop policy if exists s_adm on site_settings; create policy s_adm on site_settings for all using (has_perm('settings')) with check (has_perm('settings'));
drop policy if exists media_ins on storage.objects; create policy media_ins on storage.objects for insert with check (bucket_id='media' and (has_perm('content') or has_perm('settings')));
drop policy if exists media_upd on storage.objects; create policy media_upd on storage.objects for update using (bucket_id='media' and (has_perm('content') or has_perm('settings')));
drop policy if exists media_del on storage.objects; create policy media_del on storage.objects for delete using (bucket_id='media' and (has_perm('content') or has_perm('settings')));
drop policy if exists vid_read on storage.objects; create policy vid_read on storage.objects for select using (bucket_id='videos' and (has_perm('content') or (not is_maintenance() and exists(select 1 from public.modules m where m.video_path=name))));
drop policy if exists vid_ins on storage.objects; create policy vid_ins on storage.objects for insert with check (bucket_id='videos' and has_perm('content'));
drop policy if exists vid_upd on storage.objects; create policy vid_upd on storage.objects for update using (bucket_id='videos' and has_perm('content'));
drop policy if exists vid_del on storage.objects; create policy vid_del on storage.objects for delete using (bucket_id='videos' and has_perm('content'));

-- Support client avec confirmation de lecture (read_at)
create table if not exists support_messages(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, user_name text, user_email text, sender text not null check (sender in ('user','staff')), body text not null check (length(body) between 1 and 2000), created_at timestamptz default now(), read_at timestamptz);
alter table support_messages enable row level security;
create or replace function sm_before() returns trigger language plpgsql security definer set search_path=public as $$
begin if tg_op='INSERT' then select name,email into new.user_name,new.user_email from profiles where id=new.user_id; new.read_at:=null; return new;
  else if (old.sender='staff' and old.user_id=auth.uid()) or (old.sender='user' and has_perm('support')) then new:=old; new.read_at:=coalesce(old.read_at,now()); else new:=old; end if; return new; end if; end $$;
drop trigger if exists sm_trg on support_messages; create trigger sm_trg before insert or update on support_messages for each row execute function sm_before();
drop policy if exists sm_sel on support_messages; create policy sm_sel on support_messages for select using (user_id=auth.uid() or has_perm('support'));
drop policy if exists sm_ins_u on support_messages; create policy sm_ins_u on support_messages for insert with check (user_id=auth.uid() and sender='user');
drop policy if exists sm_ins_s on support_messages; create policy sm_ins_s on support_messages for insert with check (has_perm('support') and sender='staff');
drop policy if exists sm_upd on support_messages; create policy sm_upd on support_messages for update using (user_id=auth.uid() or has_perm('support'));

-- Communauté Premium (publications, photos, j'aime, commentaires)
create table if not exists community_posts(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, author_name text, body text check (length(body)<=2000), image_path text, created_at timestamptz default now(), check (coalesce(length(body),0)>0 or image_path is not null));
create table if not exists community_comments(id uuid primary key default gen_random_uuid(), post_id uuid not null references community_posts on delete cascade, user_id uuid not null references profiles on delete cascade, author_name text, body text not null check (length(body) between 1 and 1000), created_at timestamptz default now());
create table if not exists community_likes(post_id uuid references community_posts on delete cascade, user_id uuid references profiles on delete cascade, primary key(post_id,user_id));
alter table community_posts enable row level security; alter table community_comments enable row level security; alter table community_likes enable row level security;
create or replace function set_author() returns trigger language plpgsql security definer set search_path=public as $$ begin new.author_name:=(select name from profiles where id=new.user_id); return new; end $$;
drop trigger if exists cp_author on community_posts; create trigger cp_author before insert on community_posts for each row execute function set_author();
drop trigger if exists cc_author on community_comments; create trigger cc_author before insert on community_comments for each row execute function set_author();
drop policy if exists cp_sel on community_posts; create policy cp_sel on community_posts for select using (is_premium() or has_perm('community'));
drop policy if exists cp_ins on community_posts; create policy cp_ins on community_posts for insert with check (user_id=auth.uid() and (is_premium() or has_perm('community')));
drop policy if exists cp_del on community_posts; create policy cp_del on community_posts for delete using (user_id=auth.uid() or has_perm('community'));
drop policy if exists cc_sel on community_comments; create policy cc_sel on community_comments for select using (is_premium() or has_perm('community'));
drop policy if exists cc_ins on community_comments; create policy cc_ins on community_comments for insert with check (user_id=auth.uid() and (is_premium() or has_perm('community')));
drop policy if exists cc_del on community_comments; create policy cc_del on community_comments for delete using (user_id=auth.uid() or has_perm('community'));
drop policy if exists cl_sel on community_likes; create policy cl_sel on community_likes for select using (is_premium() or has_perm('community'));
drop policy if exists cl_ins on community_likes; create policy cl_ins on community_likes for insert with check (user_id=auth.uid() and (is_premium() or has_perm('community')));
drop policy if exists cl_del on community_likes; create policy cl_del on community_likes for delete using (user_id=auth.uid());
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types) values ('community','community',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict (id) do nothing;
drop policy if exists com_read on storage.objects; create policy com_read on storage.objects for select using (bucket_id='community' and (is_premium() or has_perm('community')));
drop policy if exists com_ins on storage.objects; create policy com_ins on storage.objects for insert with check (bucket_id='community' and (is_premium() or has_perm('community')) and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists com_del on storage.objects; create policy com_del on storage.objects for delete using (bucket_id='community' and ((storage.foldername(name))[1]=auth.uid()::text or has_perm('community')));

-- Annuaire des transitaires (Premium)
create table if not exists forwarders(id uuid primary key default gen_random_uuid(), name text not null, city text, country text, address text, phone text, whatsapp text, services text, notes text, active boolean not null default true, created_at timestamptz default now());
alter table forwarders enable row level security;
drop policy if exists f_sel on forwarders; create policy f_sel on forwarders for select using ((active and is_premium()) or has_perm('forwarders'));
drop policy if exists f_adm on forwarders; create policy f_adm on forwarders for all using (has_perm('forwarders')) with check (has_perm('forwarders'));
