# FBStore Academy : mise en route (15 min)
1. supabase.com > New project. Notez l'URL et la clé Publishable (Project Settings > API).
2. SQL Editor : collez tout `schema.sql` et exécutez. Puis, AVANT de créer votre compte, exécutez :
   insert into super_admins values ('votre@email.com');
3. Authentication > Providers > Email : laissez "Confirm email" activé.
4. Authentication > URL Configuration : mettez votre adresse en ligne dans Site URL et Redirect URLs.
5. Ouvrez `config.js` : collez l'URL et la clé Publishable (clés publiques uniquement).
6. Hébergez le dossier (Netlify : glisser-déposer ; ou Vercel). HTTPS obligatoire pour la PWA.
7. Créez votre compte avec l'email super admin, confirmez-le, connectez-vous : l'onglet Admin apparaît.
8. Admin > Formations : renseignez le prix et les "Instructions de paiement" (ex. numéro Mobile Money).
   Admin > Modules : collez les liens vidéo (YouTube : https://www.youtube.com/embed/ID).
Paiement : l'élève envoie sa référence, vous cliquez "Valider" dans Admin > Paiements, il passe Premium.
Google : Authentication > Providers > Google (clés Google Cloud nécessaires). Webhook automatique : dossier supabase-webhook.

## Paiement SasPay (optionnel, remplace le paiement manuel)
1. Exécutez `saspay.sql` (ou `schema.sql` si vous partez de zéro).
2. supabase functions deploy saspay
3. supabase secrets set SASPAY_API_KEY=sk_test_...   (testez en sk_test_, puis sk_live_)
4. Dans `config.js`, remplissez NETWORKS avec les pays/réseaux acceptés par votre compte SasPay.
L'accès Premium n'est activé que si SasPay renvoie SUCCESS à la vérification faite par le serveur.

## Mise à jour complète (votre base actuelle)
1. SQL Editor : exécutez `upgrade.sql` (idempotent). Il active la sécurité RLS sur `coupons` et `site_settings`, ajoute codes promo, paramètres, paiements manuels, témoignages et SasPay.
2. Redéployez la fonction : supabase functions deploy saspay
3. Double authentification : activée par défaut côté Supabase (Authentication > Multi-Factor, TOTP). Activez-la ensuite dans Profil > Sécurité.
   Dès que le super admin l'active, la base exige le code pour toute action admin.
4. Admin > Paramètres : Pixel Meta, Google Analytics, WhatsApp. Admin > Codes promo : créez vos codes.

## Envoi de vidéos et d'images depuis votre ordinateur
1. SQL Editor : exécutez `upgrade2.sql` (après `upgrade.sql`).
2. Admin > Modules > Nouveau module : choisissez la vidéo avec le sélecteur de fichiers, une barre de progression s'affiche. Même chose pour l'image de la formation (Formations et prix).
3. Les vidéos sont privées : seuls les élèves ayant accès au module (gratuit ou Premium) peuvent les lire.
4. Taille maximale d'un fichier : réglée dans Supabase (Storage > Settings). Le plan gratuit limite à 50 Mo par fichier.
## Paiement par téléphone
Admin > Paramètres > Réseaux de paiement SasPay : une ligne par réseau, format  Nom|PAYS|code_réseau|indicatif
(les codes viennent de https://api.saspay.me/api/v1/countries/ ). L'élève saisit son numéro, reçoit la demande sur son téléphone, la valide, puis voit « Paiement réussi ».

## Paiement carte + Mobile Money (SasPay)
Dans Admin > Paramètres > Réseaux, ajoutez une ligne par moyen : Nom|PAYS|code_réseau|indicatif|mobile  ou  ...|card
(exemple carte : Carte bancaire|CD|code_fourni_par_SasPay||card). L'élève saisit email et téléphone ; Mobile Money = demande sur le téléphone, carte = redirection sécurisée.
Après un paiement par carte, le site vérifie automatiquement le paiement quand l'élève revient. Redéployez la fonction : supabase functions deploy saspay
