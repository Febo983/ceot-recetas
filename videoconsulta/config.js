// Configuracion de la app de videoconsultas.
// Reemplazar los dos valores despues de crear el proyecto en Supabase
// (ver docs/videoconsulta-setup.md).
window.VC_CONFIG = {
  // URL de la Edge Function
  FN_URL: "https://TU-PROYECTO.supabase.co/functions/v1/videoconsulta",
  // Clave publica (anon / publishable). No es secreta: las tablas estan cerradas
  // con RLS y todo pasa por la Edge Function.
  ANON_KEY: "TU_ANON_KEY"
};
