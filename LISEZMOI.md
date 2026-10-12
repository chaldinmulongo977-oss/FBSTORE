# FBStore Academy : déploiement (environ 20 minutes)

## 1. Supabase (base de données et connexion)
1. supabase.com > New project. Notez le Project URL et la clé Publishable (Project Settings > API).
2. SQL Editor : collez et exécutez `database-complete.sql` (nouvelle installation).
   Base déjà existante : exécutez seulement `sql/upgrade.sql`, puis `sql/upgrade2.sql`, puis `sql/upgrade3.sql`, puis `sql/upgrade4.sql`, puis `sql/upgrade5.sql`.
3. Authentication > Providers > Email : "Confirm email" activé. Authentication > Multi-Factor : TOTP activé.
4. Authentication > URL Configuration : Site URL et Redirect URLs = l'adresse de votre site (étape 3).
5. Storage > Settings : réglez la taille maximale d'un fichier (50 Mo en gratuit).

## 2. Configuration du site
Ouvrez `config.js` : collez URL et clé Publishable (clés publiques seulement).

## 3. Hébergement
Netlify : glissez-déposez le dossier (sans `supabase/`, `sql/`, `.env`). Ou Vercel. HTTPS obligatoire (PWA).

## 4. Paiement SasPay (serveur)
1. Installez la CLI Supabase, puis : supabase login ; supabase link --project-ref VOTRE_REF
2. supabase secrets set SASPAY_API_KEY=sk_test_...   (testez avec sk_test_, puis sk_live_)
3. supabase functions deploy saspay
4. Admin > Paramètres > "Voir les pays et réseaux disponibles sur mon compte" : relevez les codes, puis remplissez
   "Réseaux de paiement" : Nom|PAYS|code_réseau|indicatif|mobile  (ou  ...|card pour la carte)
5. Ajoutez la clé API uniquement dans les secrets Supabase. Jamais dans config.js ni sur GitHub.

## 5. Premier lancement
Créez votre compte avec l'email super admin, confirmez-le, connectez-vous : l'onglet Admin apparaît.
Profil > Sécurité : activez la double authentification (scannez le QR code). Admin : prix, vidéos, codes promo, paramètres.

## Mise à jour : équipe, maintenance, support, communauté, transitaires
1. SQL : exécutez `sql/upgrade5.sql` (base existante). Les nouvelles installations utilisent `database-complete.sql`.
2. Fonctions serveur : supabase functions deploy saspay ; supabase functions deploy admin-users
3. Admin > Équipe et rôles (super admin) : ajoutez un membre par email (le compte doit exister), choisissez un rôle ou cochez seulement les accès voulus.
4. Admin > Paramètres : maintenance, support (email, WhatsApp), certificat (logo, signature), Pixel Facebook + token Conversions API.
5. Les fonctions Premium (communauté, transitaires, calculateur) sont réservées aux comptes Premium et à l'équipe autorisée.

## Mise à jour : suivi des paiements, test, notifications push
1. SQL : exécutez `sql/upgrade6.sql` (base existante). Les nouvelles installations utilisent `database-complete.sql`.
2. Secrets serveur : copiez `.env.example` en `.env`, remplissez-le, puis `supabase secrets set --env-file .env` (le `.env` est ignoré par git).
3. Notifications : `npx web-push generate-vapid-keys`. Clé publique : dans `config.js` (`VAPID_KEY`) et dans `VAPID_PUBLIC_KEY`. Clé privée : seulement dans `VAPID_PRIVATE_KEY`.
4. Déployez : `supabase functions deploy notify`, puis hébergez à nouveau le site.
5. Admin > Paiements : suivi Payé / En cours / Échec, bouton « Vérifier », test de connexion et test de paiement.
6. Admin > Notifications : envoi à tous, aux Premium, aux gratuits, ou à vous seul (test). Les élèves s'abonnent depuis Profil > Notifications.
