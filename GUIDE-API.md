# Guide : où mettre chaque clé API

Il y a **3 endroits**. Un secret ne va qu'à un seul endroit.

| Endroit | Ce qu'on y met | Qui peut le lire |
|---|---|---|
| `config.js` | URL et clé *Publishable* Supabase (publiques) | tout le monde |
| **Admin du site** (stocké en base, table protégée) | clés SasPay, webhook, token Facebook, clé Google, clés notifications | super admin seulement |
| **Supabase > Edge Functions > Secrets** | seulement les clés de secours (facultatif) | personne côté navigateur |

## 1. Ordre d'installation
1. Supabase > SQL Editor : exécutez les scripts dans l'ordre. Base existante : `sql/upgrade5.sql` → `upgrade6` → `upgrade7` → **`upgrade8.sql`** (droits d'accès : corrige « permission denied for table »).
   Nouvelle installation : `database-complete.sql` seul.
2. Supabase > Edge Functions : déployez ces 5 fonctions (copier-coller du fichier `index.ts` de chaque dossier) :

| Fonction (nom exact) | Verify JWT |
|---|---|
| `saspay` | activé |
| `saspay-webhook` | **désactivé** |
| `admin-users` | activé |
| `push-send` | activé |
| `chat-notify` | activé |

3. Connectez-vous avec `chaldinmulongo977@gmail.com` (super admin principal) puis remplissez les formulaires ci-dessous.

## 2. Valeurs à saisir dans l'Admin
| Où | Champ | Où l'obtenir | Obligatoire ? |
|---|---|---|---|
| Config. paiements | Clé de test `sk_test_…` | app.saspay.me > Développeur | non (une seule clé suffit selon le mode) |
| Config. paiements | Clé de production `sk_live_…` | idem | non |
| Config. paiements | Mode test / production | choix | oui |
| Config. paiements | Moyens de paiement (bouton Ajouter) | liste des réseaux de votre compte SasPay | oui pour payer |
| Config. paiements | Secret d'accès du webhook (dans l'adresse) | bouton « Générer un secret » | non |
| Config. paiements | Signature du webhook (secret de signature SasPay) | tableau de bord SasPay > Webhooks, à la création du webhook | non (recommandée) |
| Paramètres | Pixel ID Meta | Events Manager | non |
| Paramètres | Token Conversions API | Events Manager > Paramètres | non |
| Paramètres | Mesure Google `G-…` + clé Measurement Protocol | Google Analytics > Admin | non |
| Notifications | Clés d'envoi (VAPID) | bouton « Générer » | oui pour les notifications |

## 3. Vérifier que tout marche
- Admin > Config. paiements > **Tester la configuration** : chaque ligne doit être verte.
- **Envoyer un paiement de test** en mode test (aucun argent réel, aucun accès Premium activé).
- Admin > Paramètres > **Tester les événements de vente**.

## 4. Problèmes fréquents
- *permission denied for table …* → exécutez `sql/upgrade8.sql`.
- *Clé refusée par SasPay* → mauvais mode (test/production) ou clé copiée avec un espace.
- *Paiement impossible* → ouvrez « Tester la configuration » : le message indique la cause.
- *Fonction indisponible* → elle n'est pas déployée (nom exact et JWT, voir le tableau).
- Ne publiez jamais `secrets.env`, `.env` ni vos clés `sk_…` (GitHub, WhatsApp, captures d'écran).

## 5. Moyens de paiement : pays, opérateurs et carte Visa
- Admin > Config. paiements > **Moyens de paiement** : « Ajouter » (un par un) ou « Importer en masse » (collez vos lignes `Nom|PAYS|code_réseau|indicatif|mobile` ; vos anciens réseaux déjà saisis y sont pré-remplis).
- Pour chaque opérateur (Airtel, M-Pesa, Orange, Vodacom…) : pays (2 lettres), code réseau SasPay, indicatif (ex. 243).
- **Carte Visa / Mastercard** : ajoutez un moyen en cochant « Paiement par carte / page de redirection » avec le code carte indiqué par SasPay.
- L'élève choisit son **pays**, puis son **opérateur ou la carte**. Le numéro est vérifié avant l'envoi (indicatif, 0 en trop, longueur : 9 chiffres après +243).
