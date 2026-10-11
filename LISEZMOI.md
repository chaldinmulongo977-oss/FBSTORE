# FBStore Academy : déploiement (environ 20 minutes)

## 1. Supabase (base de données et connexion)
1. supabase.com > New project. Notez le Project URL et la clé Publishable (Project Settings > API).
2. SQL Editor : collez et exécutez `database-complete.sql` (nouvelle installation).
   Base déjà existante : exécutez seulement `sql/upgrade.sql`, puis `sql/upgrade2.sql`, puis `sql/upgrade3.sql`, puis `sql/upgrade4.sql`.
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
