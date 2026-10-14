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

## Paiements, webhook et notifications (mise à jour)
1. SQL : exécutez `sql/upgrade6.sql` (base existante). Nouvelle installation : `database-complete.sql`.
2. Fonctions (Supabase > Edge Functions) : redéployez `saspay` ; créez `saspay-webhook` (Verify JWT DÉSACTIVÉ) et `push-send` (Verify JWT activé).
3. Admin > Config. paiements : choisissez le mode (test/production), collez vos clés sk_test_ / sk_live_, vos moyens de paiement, le lien SasPay, puis "Tester la configuration" et "Envoyer un paiement de test".
4. Webhook : générez un secret, enregistrez, puis collez l'adresse affichée dans le tableau de bord SasPay (section Webhooks).
5. Admin > Notifications : générez les clés d'envoi une fois ; les élèves activent les notifications dans Profil.

## Mise à jour : moyens de paiement, chat vocal, visiteurs, suivi des ventes
1. SQL : exécutez `sql/upgrade7.sql` (après upgrade6). Nouvelle installation : `database-complete.sql`.
2. Fonctions : redéployez `saspay` et `saspay-webhook` ; créez `chat-notify` (Verify JWT activé).
3. Admin > Config. paiements : ajoutez chaque moyen de paiement avec le bouton "Ajouter" (nom, pays, code réseau SasPay, indicatif, mobile ou carte).
4. Admin > Notifications : "Générer les clés" une seule fois (sans cela, aucune notification ne part).
5. Admin > Paramètres : Pixel Meta + token Conversions API + code de test ; Google Analytics + clé secrète API Measurement Protocol ; puis "Tester les événements de vente".
6. Droits : modifier formations et prix exige l'accès "Formations et prix" (super admin par défaut). Les membres déjà créés gardent leurs anciens accès : vérifiez-les dans Équipe et rôles.

## Important : droits d'accès (erreur "permission denied for table ...")
Exécutez `sql/upgrade8.sql` dans Supabase > SQL Editor. Puis lisez `GUIDE-API.md` (où mettre chaque clé) ; l'outil `outils/assistant-api.html` aide à préparer les clés.
