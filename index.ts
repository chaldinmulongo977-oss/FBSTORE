// Envoi de notifications push. Réservé à l'équipe ayant l'accès "settings".
// Secrets requis : VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (ex. mailto:contact@exemple.com)
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userSb = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    });
    const { data: { user } } = await userSb.auth.getUser();
    if (!user) return json({ error: "Non connecté." }, 401);
    const { data: allowed } = await userSb.rpc("has_perm", { p: "settings" });
    if (!allowed) return json({ error: "Accès refusé." }, 403);

    const pub = Deno.env.get("VAPID_PUBLIC_KEY"), priv = Deno.env.get("VAPID_PRIVATE_KEY");
    if (!pub || !priv) return json({ error: "Clés VAPID absentes des secrets Supabase." }, 500);
    webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT") || "mailto:contact@example.com", pub, priv);

    const b = await req.json();
    const title = String(b.title || "").trim().slice(0, 60), body = String(b.body || "").trim().slice(0, 180);
    const link = String(b.url || "").trim();
    const audience = ["all", "premium", "free", "me"].includes(b.audience) ? b.audience : "all";
    if (title.length < 3 || body.length < 3) return json({ error: "Titre et message requis." }, 400);
    if (link && !/^(#\/[\w\/-]*|https:\/\/\S+)$/.test(link)) return json({ error: "Lien invalide." }, 400);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    let q = admin.from("push_subscriptions").select("id,endpoint,p256dh,auth,user_id,profiles(status)");
    if (audience === "me") q = q.eq("user_id", user.id);
    const { data: subs, error } = await q;
    if (error) return json({ error: error.message }, 500);
    const list = (subs || []).filter((s: any) =>
      audience === "premium" ? s.profiles?.status === "PREMIUM" : audience === "free" ? s.profiles?.status !== "PREMIUM" : true);

    const payload = JSON.stringify({ title, body, url: link || "./" });
    let sent = 0, failed = 0;
    const dead: string[] = [];
    for (let i = 0; i < list.length; i += 20) {
      const res = await Promise.allSettled(list.slice(i, i + 20).map((s: any) =>
        webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload)));
      res.forEach((r, k) => {
        if (r.status === "fulfilled") sent++;
        else {
          failed++;
          const code = (r.reason as any)?.statusCode;
          if (code === 404 || code === 410) dead.push(list[i + k].id);
        }
      });
    }
    if (dead.length) await admin.from("push_subscriptions").delete().in("id", dead);
    await admin.from("notifications").insert({ title, body, url: link, audience, sent, failed, created_by: user.id });
    return json({ sent, failed, total: list.length });
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
