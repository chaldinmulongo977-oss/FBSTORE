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
