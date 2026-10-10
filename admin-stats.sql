-- À exécuter seulement si vous aviez déjà exécuté l'ancien schema.sql

-- Statistiques admin : permet au super admin de lire la progression de tous les élèves.
create policy g_adm on progress for select using (is_admin());
