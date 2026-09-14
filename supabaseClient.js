(function initializeSupabaseClient() {
  "use strict";

  const config = window.CLUB_CONFIG || {};
  const url = String(config.SUPABASE_URL || "").trim();
  const key = String(config.SUPABASE_ANON_KEY || "").trim();

  const isPlaceholder =
    !url ||
    !key ||
    url.includes("TU-PROYECTO") ||
    key.includes("PEGA-AQUI");

  window.CLUB_CONFIG_READY = false;
  window.clubSupabase = null;

  if (isPlaceholder) {
    console.warn("Club IMPORTB2B: falta configurar Supabase en assets/js/config.example.js");
    return;
  }

  if (!window.supabase || typeof window.supabase.createClient !== "function") {
    console.error("Club IMPORTB2B: no se pudo cargar la librería oficial de Supabase.");
    return;
  }

  window.clubSupabase = window.supabase.createClient(url, key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  });

  window.CLUB_CONFIG_READY = true;
})();
