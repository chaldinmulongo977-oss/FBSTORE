// Utilitaires partagés par les fonctions "saspay" et "saspay-webhook".
// Doc SasPay : https://docs.saspay.me (Base URL https://api.saspay.me/api/v1, Authorization: Bearer sk_...)
import { createClient } from "npm:@supabase/supabase-js@2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
export const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const serviceClient = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

export async function getSecrets(db: any): Promise<Record<string, string>> {
  const { data } = await db.from("payment_secrets").select("key,value");
  return Object.fromEntries((data || []).map((r: any) => [r.key, r.value || ""]));
}

export const hint = (k: string) => (k ? k.slice(0, 8) + "…" + k.slice(-4) : "");

export type Cfg = { key: string; mode: "test" | "live"; base: string; source: string; error?: string };

// Choix de la clé. Priorité : réglage "mode" de l'admin, puis variable d'environnement SASPAY_API_KEY (fichier .env / secrets Supabase).
//  mode "auto" (défaut) : .env d'abord, sinon clé live, sinon clé test (le mode est déduit du préfixe sk_live_ / sk_test_)
//  mode "live"          : clé live saisie dans l'admin, sinon .env
//  mode "test"          : clé test saisie dans l'admin, sinon .env
export function resolveCfg(sec: Record<string, string>): Cfg {
  const env = (Deno.env.get("SASPAY_API_KEY") || "").trim();
  const base = (sec.base_url || Deno.env.get("SASPAY_BASE_URL") || "https://api.saspay.me/api/v1").trim().replace(/\/+$/, "");
  const want = ["live", "test"].includes(sec.mode) ? sec.mode : "auto";
  let key = "", source = "";
  if (want === "test") { key = sec.key_test || env; source = sec.key_test ? "admin" : "env"; }
  else if (want === "live") { key = sec.key_live || env; source = sec.key_live ? "admin" : "env"; }
  else if (env) { key = env; source = "env"; }
  else if (sec.key_live) { key = sec.key_live; source = "admin"; }
  else { key = sec.key_test; source = "admin"; }
  if (!key) return { key: "", mode: "test", base, source: "", error: "Aucune clé API SasPay configurée (Admin > Paiements > Configuration, ou secret SASPAY_API_KEY)." };
  const mode = key.startsWith("sk_live_") ? "live" : key.startsWith("sk_test_") ? "test" : null;
  if (!mode) return { key, mode: "test", base, source, error: "La clé SasPay doit commencer par sk_test_ ou sk_live_." };
  if (want !== "auto" && mode !== want) return { key, mode, base, source, error: `Le mode ${want} est choisi mais la clé trouvée est une clé ${mode}.` };
  return { key, mode, base, source };
}

export function errText(j: any, fallback: string): string {
  const e = j?.error;
  const c = [j?.message, e?.message, typeof e === "string" ? e : null, j?.detail, j?.data?.message,
    j?.errors && typeof j.errors === "object" ? JSON.stringify(j.errors).slice(0, 300) : null]
    .filter((x) => typeof x === "string" && x);
  return (c[0] as string) || fallback;
}

export async function api(cfg: Cfg, method: string, path: string, body?: unknown, idem?: string, auth = true) {
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json" };
  if (auth) headers.Authorization = `Bearer ${cfg.key}`;
  if (idem) headers["Idempotency-Key"] = idem;
  let res: Response;
  try {
    res = await fetch(cfg.base + path, { method, headers, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(25000) });
  } catch (e) {
    return { status: 0, ok: false, json: null as any, text: "", data: {} as any, msg: "SasPay injoignable : " + String((e as Error).message || e) };
  }
  const text = await res.text();
  let j: any = null;
  try { j = JSON.parse(text); } catch { /* réponse non JSON */ }
  const ok = res.ok && j?.success !== false;
  return { status: res.status, ok, json: j, text, data: (j?.data ?? j ?? {}) as any, msg: ok ? "" : errText(j, `Erreur SasPay (HTTP ${res.status}).`) };
}

export async function updateAttempt(db: any, id: string, patch: Record<string, unknown>) {
  await db.from("saspay_attempts").update({ ...patch, updated_at: new Date().toISOString() }).eq("id", id);
}

// Active l'accès Premium. Idempotent : la contrainte unique payments.transaction_id empêche tout doublon
// (le polling du navigateur et le webhook peuvent arriver en même temps).
export async function finalize(db: any, a: any) {
  if (a.is_test) return;
  const { error } = await db.from("payments").insert({
    user_id: a.user_id, amount: a.amount, currency: a.currency, status: "paid",
    transaction_id: a.payment_id, coupon_id: a.coupon_id || null,
  });
  if (!error && a.coupon_id) await db.rpc("bump_coupon", { p_id: a.coupon_id });
  if (error && error.code !== "23505") throw new Error(error.message);
  await db.from("profiles").update({ status: "PREMIUM" }).eq("id", a.user_id);
}

// Source de vérité = l'API SasPay (GET /payments/{id}/verify/). Un webhook ne sert que de déclencheur.
export async function verifyAttempt(db: any, cfg: Cfg, a: any) {
  if (!a.payment_id) return { status: a.status as string };
  const r = await api(cfg, "GET", `/payments/${encodeURIComponent(a.payment_id)}/verify/`);
  if (!r.ok) {
    await updateAttempt(db, a.id, { error: r.msg });
    return { status: String(a.status || "PENDING").toUpperCase(), warning: r.msg };
  }
  const status = String(r.data.status || "PENDING").toUpperCase();
  const patch: Record<string, unknown> = { status };
  if (status === "SUCCESS" || status === "PENDING") patch.error = null;
  else patch.error = String(r.data.message || r.data.failure_reason || r.data.reason || "").slice(0, 300) || null;
  await updateAttempt(db, a.id, patch);
  if (status === "SUCCESS") await finalize(db, { ...a, status });
  return { status };
}
