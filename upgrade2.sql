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
