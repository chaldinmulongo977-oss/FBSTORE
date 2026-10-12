// Fonction serveur "saspay" : paiement (softpay), vérification, test, catalogue réseaux, configuration admin.
// Déploiement : supabase functions deploy saspay
// Secret : SASPAY_API_KEY (voir .env.example). Les clés peuvent aussi être saisies dans Admin > Paiements > Configuration.
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  api, cors, finalize, getSecrets, hint, json, resolveCfg, serviceClient, updateAttempt, verifyAttempt,
} from "../_shared/saspay.ts";

const MAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function parseNetworks(txt: string) {
  return (txt || "").split("\n").map((l) => l.trim().split("|").map((x) => x.trim()))
    .filter((a) => a.length >= 3 && a[1] && a[2]).map((a) => ({ country: a[1].toUpperCase(), network: a[2] }));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const userSb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    });
    const { data: { user } } = await userSb.auth.getUser();
    if (!user) return json({ error: "Non connecté." }, 401);

    const b = await req.json().catch(() => ({}));
    const action = String(b.action || "");
    const db = serviceClient();
    const sec = await getSecrets(db);
    const cfg = resolveCfg(sec);
    const can = async (fn: string, args?: Record<string, unknown>) => (await userSb.rpc(fn, args)).data === true;

    /* ---------- Configuration (super admin) ---------- */
    if (action === "config_status") {
      if (!await can("is_admin")) return json({ error: "Réservé au super administrateur." }, 403);
      const env = (Deno.env.get("SASPAY_API_KEY") || "").trim();
      return json({
        mode: ["live", "test"].includes(sec.mode) ? sec.mode : "auto",
        effective: cfg.error ? null : cfg.mode, source: cfg.source, problem: cfg.error || null,
        key_live: hint(sec.key_live), key_test: hint(sec.key_test), env_key: hint(env),
        webhook_secret: !!sec.webhook_secret, base_url: sec.base_url || "", currency: sec.currency || "", rate: sec.rate || "",
        webhook_url: `${Deno.env.get("SUPABASE_URL")}/functions/v1/saspay-webhook`,
      });
    }
    if (action === "save_config") {
      if (!await can("is_admin")) return json({ error: "Réservé au super administrateur." }, 403);
      const rules: Record<string, (v: string) => string | null> = {
        key_live: (v) => (/^sk_live_[\w-]{16,}$/.test(v) ? null : "La clé live doit commencer par sk_live_."),
        key_test: (v) => (/^sk_test_[\w-]{16,}$/.test(v) ? null : "La clé test doit commencer par sk_test_."),
        mode: (v) => (["auto", "live", "test"].includes(v) ? null : "Mode invalide."),
        webhook_secret: (v) => (v.length >= 8 && v.length <= 200 ? null : "Secret webhook : 8 à 200 caractères."),
        base_url: (v) => (/^https:\/\/[\w.\-]+(:\d+)?(\/[\w.\-\/]*)?$/.test(v) ? null : "URL de l'API invalide (https://…)."),
        currency: (v) => (/^[A-Z]{3}$/.test(v) ? null : "Devise : 3 lettres majuscules (ex. XOF)."),
        rate: (v) => (Number(v) > 0 && Number(v) < 1e7 ? null : "Taux de conversion invalide."),
      };
      for (const k of Object.keys(rules)) {
        if (!(k in b) || typeof b[k] !== "string") continue;
        const v = b[k].trim();
        if (v === "") { await db.from("payment_secrets").delete().eq("key", k); continue; }
        const bad = rules[k](v);
        if (bad) return json({ error: bad }, 400);
        await db.from("payment_secrets").upsert({ key: k, value: v, updated_at: new Date().toISOString() }, { onConflict: "key" });
      }
      return json({ ok: true });
    }

    /* ---------- Outils admin (accès « Paiements ») ---------- */
    if (action === "ping" || action === "catalog") {
      if (!await can("has_perm", { p: "payments" })) return json({ error: "Accès refusé." }, 403);
      if (cfg.error) return json({ error: cfg.error });
      if (action === "ping") {
        const r = await api(cfg, "GET", "/transactions/?page_size=1");
        const rejected = r.status === 401 || r.status === 403;
        return json({
          ok: !rejected && r.status > 0 && r.status < 500, status: r.status, mode: cfg.mode, source: cfg.source,
          error: rejected ? "Clé API refusée par SasPay (vérifiez-la dans app.saspay.me > Développeur)." : r.status === 0 ? r.msg : r.status >= 500 ? "SasPay a répondu par une erreur serveur." : null,
        });
      }
      const [c, n] = await Promise.all([api(cfg, "GET", "/countries/", undefined, undefined, false), api(cfg, "GET", "/networks/")]);
      return json({
        countries: JSON.stringify(c.json ?? c.text, null, 1).slice(0, 20000),
        networks: JSON.stringify(n.json ?? n.text, null, 1).slice(0, 20000), networks_status: n.status,
      });
    }

    /* ---------- Paiement (élève ou test admin) ---------- */
    if (action === "softpay") {
      const test = b.test === true;
      if (test && !await can("has_perm", { p: "payments" })) return json({ error: "Accès refusé." }, 403);
      if (cfg.error) return json({ error: cfg.error });

      const name = String(b.name || "").trim().replace(/\s+/g, " ");
      const email = String(b.email || "").trim().toLowerCase();
      const phone = String(b.phone || "").trim();
      const country = String(b.country || "").trim().toUpperCase();
      const network = String(b.network || "").trim();
      if (name.length < 2 || name.length > 80) return json({ error: "Entrez votre nom complet." });
      if (!MAIL.test(email)) return json({ error: "Email invalide." });
      if (!/^\+\d{8,15}$/.test(phone)) return json({ error: "Numéro de téléphone invalide." });
      if (!/^[A-Z]{2}$/.test(country) || !/^[\w-]{2,40}$/.test(network)) return json({ error: "Réseau de paiement invalide." });

      const { data: ss } = await db.from("site_settings").select("value").eq("key", "saspay_networks").maybeSingle();
      const allowed = parseNetworks(ss?.value || "");
      if (allowed.length && !allowed.some((x) => x.country === country && x.network === network)) return json({ error: "Réseau non autorisé." });

      const { data: prof } = await db.from("profiles").select("status").eq("id", user.id).single();
      if (!test && prof?.status === "PREMIUM") return json({ error: "Votre compte est déjà Premium." });

      const since = new Date(Date.now() - 10 * 60_000).toISOString();
      const { count } = await db.from("saspay_attempts").select("id", { count: "exact", head: true }).eq("user_id", user.id).gte("created_at", since);
      if ((count || 0) >= 6) return json({ error: "Trop de tentatives. Patientez quelques minutes avant de réessayer." });

      const { data: q } = await db.rpc("quote", { p_code: b.coupon || null });
      if (!q || !(Number(q.final) > 0)) return json({ error: "Montant à payer invalide ou nul. Contactez le support." });
      let amount = Number(q.final);
      if (test && Number(b.amount) > 0 && Number(b.amount) < 1e7) amount = Number(b.amount);
      const courseCur = String(q.currency || "USD");

      // Conversion optionnelle (réglage admin) si la devise du réseau diffère de celle du prix.
      const sentCur = sec.currency || courseCur;
      const rate = sec.currency ? Number(sec.rate || 1) : 1;
      const sentAmount = Math.round(amount * rate * 100) / 100;

      const { data: att, error: ie } = await db.from("saspay_attempts").insert({
        user_id: user.id, amount, currency: courseCur, status: "PENDING", full_name: name, phone, email, country, network,
        is_test: test, mode: cfg.mode, coupon_id: test ? null : (q.valid ? q.coupon_id : null), sent_amount: sentAmount, sent_currency: sentCur,
      }).select("*").single();
      if (ie || !att) return json({ error: "Impossible d'enregistrer la tentative de paiement." });

      const parts = name.split(" ");
      const first = parts[0], last = parts.slice(1).join(" ") || parts[0];
      const r = await api(cfg, "POST", "/payments/softpay/", {
        amount: sentAmount.toFixed(2), currency: sentCur, country, network,
        description: test ? "Test FBStore Academy" : "Formation FBStore Academy",
        customer: { email, first_name: first, last_name: last, phone },
      }, att.idempotency_key);

      const id = r.data?.id;
      if (!r.ok || !id) {
        await updateAttempt(db, att.id, { status: "FAILED", error: (r.msg || "Réponse SasPay sans identifiant de paiement.").slice(0, 300) });
        return json({ error: r.msg || "Paiement impossible pour le moment." });
      }
      const status = String(r.data.status || "PENDING").toUpperCase();
      await updateAttempt(db, att.id, { payment_id: String(id), status, checkout_url: r.data.checkout_url || null });
      if (status === "SUCCESS") await finalize(db, { ...att, payment_id: String(id) });
      return json({
        payment_id: String(id), status, checkout_url: r.data.checkout_url || "", instructions: r.data.instructions || "", test, mode: cfg.mode,
      });
    }

    /* ---------- Vérification du statut ---------- */
    if (action === "verify") {
      if (cfg.error) return json({ error: cfg.error });
      const staff = await can("has_perm", { p: "payments" });
      if (b.payment_id) {
        const { data: a } = await db.from("saspay_attempts").select("*").eq("payment_id", String(b.payment_id)).maybeSingle();
        if (!a || (a.user_id !== user.id && !staff)) return json({ status: "NONE" });
        const v = await verifyAttempt(db, cfg, a);
        return json({ ...v, payment_id: a.payment_id });
      }
      // Sans identifiant : revérifie les tentatives récentes de l'élève (bouton « Actualiser mon accès »).
      const { data: list } = await db.from("saspay_attempts").select("*").eq("user_id", user.id).eq("is_test", false)
        .order("created_at", { ascending: false }).limit(5);
      let last: any = null;
      for (const a of list || []) {
        if (a.payment_id && ["PENDING", "SUCCESS"].includes(String(a.status).toUpperCase())) {
          const v = await verifyAttempt(db, cfg, a);
          if (v.status === "SUCCESS") return json({ status: "SUCCESS", payment_id: a.payment_id });
          last = last || { ...v, payment_id: a.payment_id };
        }
      }
      return json(last || { status: "NONE" });
    }

    return json({ error: "Action inconnue." }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
