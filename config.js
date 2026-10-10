// FBStore Academy : configuration PUBLIQUE (visible par les visiteurs du site).
// Mettez ici UNIQUEMENT des clés publiques. Jamais de clé "secret" ou "service_role".
window.APP_CONFIG = {
  URL: "https://dgprpxmstjqrwfuymcyy.supabase.co",   // Supabase > Project Settings > API > Project URL
  KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRncHJweG1zdGpxcndmdXltY3l5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE0NzQ4MTAsImV4cCI6MjEwNzA1MDgxMH0.SwlAFMhnT7pur47T-qVA-syShoSV1HMAqHYe_MtVPLU",              // Supabase > Project Settings > API > Publishable key (ou anon)
  // Réseaux SasPay proposés au paiement (codes pays/réseaux : GET https://api.saspay.me/api/v1/countries/ et doc "Réseaux").
  // Laissez vide [] pour garder le paiement manuel. Exemple tiré de la doc SasPay :
  // NETWORKS: [{ label: "MTN Bénin", country: "BJ", network: "mtn_bj" }]
  NETWORKS: []
};
