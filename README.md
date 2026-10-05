# CEOT — apps web

Dos aplicaciones estáticas de la Clínica de Traumatología Colón (Mar del Plata).

## 1. Solicitud de recetas — `index.html`

Widget de una sola página: el paciente elige a su profesional y va al formulario
de RCTA. Sin backend; cuenta clicks con GoatCounter.

## 2. Videoconsultas — `videoconsulta/`

El profesional crea el turno (día, hora de inicio y de fin), la app genera el
evento con **Google Meet** en el calendario de `traumatologiaccolon@gmail.com`
y devuelve un **link para el paciente** con el Meet, el alias de cobro del
profesional y el monto que él definió. La secretaría ve todos los links y los
reenvía.

```
videoconsulta/index.html   panel de profesionales y secretarias (ingreso por PIN)
videoconsulta/c.html       página que ve el paciente (c.html?t=<token>)
videoconsulta/config.js    URL de la función + clave pública + WhatsApp

supabase/migrations/        tablas, login por PIN
supabase/seed.sql           carga de usuarios y PIN iniciales
supabase/functions/videoconsulta/  única Edge Function (sesiones + Google Calendar)
```

El navegador nunca habla con la base ni con Google: todo pasa por la Edge
Function, que usa la service role key y los secrets del proyecto. Las tablas
tienen RLS activado y ninguna política, así que la clave pública no sirve para
leer datos.

Estado y pasos pendientes: **[`docs/videoconsulta-setup.md`](docs/videoconsulta-setup.md)**.
El SQL que falta correr está en
[`docs/pegar-en-supabase.sql`](docs/pegar-en-supabase.sql).
