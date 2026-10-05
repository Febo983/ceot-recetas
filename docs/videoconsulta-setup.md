# Videoconsultas CEOT — guía de instalación

Son 4 pasos. El único que requiere atención es el 2 (permiso de Google), y hay
que hacerlo **desde la cuenta `traumatologiaccolon@gmail.com`**.

| Paso | Qué se hace | Quién |
|---|---|---|
| 1 | Base de datos en Supabase | administrador |
| 2 | Permiso de Google Calendar | desde `traumatologiaccolon@gmail.com` |
| 3 | Publicar la función y la web | administrador |
| 4 | Prueba y entrega de PINs | administrador |

---

## Paso 1 — Base de datos (Supabase)

1. Entrá a [supabase.com](https://supabase.com) y abrí el proyecto de CEOT
   (o creá uno nuevo, región **South America (São Paulo)**).
2. Andá a **SQL Editor** → **New query**, pegá todo el contenido de
   `supabase/migrations/20261005120000_videoconsulta.sql` y dale **Run**.
3. Nueva query, pegá `supabase/seed.sql` y **Run**. Devuelve una tabla con el
   **PIN de cada profesional y secretaria**: copiala y guardala ahora, los PIN
   quedan hasheados y después no se pueden recuperar.
   - Para cambiar un PIN: `select vc_set_pin('Dr. Daniel Corelich', '482910');`
   - Para dar de alta a alguien nuevo:
     ```sql
     insert into vc_usuarios (nombre, rol, pin_hash)
     values ('Dra. Nombre Apellido', 'profesional', crypt('123456', gen_salt('bf', 10)));
     ```
   - Para dar de baja: `update vc_usuarios set activo = false where nombre = '...';`
4. En **Project Settings → API** anotá:
   - **Project URL** → `https://xxxx.supabase.co`
   - **anon public key** → la clave pública (no es secreta: las tablas están
     cerradas con RLS y todo pasa por la función).

---

## Paso 2 — Permiso de Google Calendar

Esto autoriza, **una sola vez**, a que la app cree los Meet en el calendario de
la clínica. Hay que estar logueado con `traumatologiaccolon@gmail.com`.

1. Entrá a [console.cloud.google.com](https://console.cloud.google.com) con esa
   cuenta y creá un proyecto llamado `CEOT Videoconsultas`.
2. **APIs y servicios → Biblioteca** → buscá **Google Calendar API** → **Habilitar**.
3. **APIs y servicios → Pantalla de consentimiento de OAuth**:
   - Tipo de usuario: **Externo**.
   - Nombre de la app: `Videoconsultas CEOT`. Mail de soporte y de contacto:
     `traumatologiaccolon@gmail.com`.
   - En **Permisos** agregá el scope `https://www.googleapis.com/auth/calendar.events`.
   - ⚠️ **Importante**: cuando termines, en esa misma pantalla tocá
     **Publicar la app** (que quede en estado *En producción*, no *Prueba*).
     Si queda en *Prueba*, el permiso **se vence cada 7 días** y la app deja de
     crear Meet. Google va a decir que la app "no está verificada": está bien,
     la autoriza una sola cuenta, la de la clínica.
4. **APIs y servicios → Credenciales → Crear credenciales → ID de cliente de OAuth**:
   - Tipo: **Aplicación web**. Nombre: `CEOT`.
   - En **URIs de redireccionamiento autorizados** agregá exactamente:
     `https://developers.google.com/oauthplayground`
   - Guardá y copiá el **ID de cliente** y el **Secreto del cliente**.
5. Ahora el permiso de larga duración. Abrí
   [developers.google.com/oauthplayground](https://developers.google.com/oauthplayground):
   - Tocá el **engranaje** (arriba a la derecha) → marcá
     **Use your own OAuth credentials** → pegá el ID y el secreto del paso anterior.
   - En el panel izquierdo, en el campo de scopes escribí
     `https://www.googleapis.com/auth/calendar.events` → **Authorize APIs**.
   - Elegí la cuenta `traumatologiaccolon@gmail.com` y aceptá (si aparece el
     aviso de app no verificada: **Configuración avanzada → Ir a Videoconsultas CEOT**).
   - Tocá **Exchange authorization code for tokens** y copiá el **Refresh token**
     (empieza con `1//`). Ese valor es el que hay que guardar.

> El *refresh token* da permiso para crear y borrar eventos en el calendario de
> la clínica. Tratalo como una contraseña: va solo en los secrets de Supabase,
> nunca en el repositorio.

---

## Paso 3 — Publicar la función y la web

Con el [CLI de Supabase](https://supabase.com/docs/guides/local-development/cli/getting-started)
instalado, desde la raíz del repo:

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF

# secrets (el valor va entre comillas)
supabase secrets set GOOGLE_CLIENT_ID="...apps.googleusercontent.com"
supabase secrets set GOOGLE_CLIENT_SECRET="..."
supabase secrets set GOOGLE_REFRESH_TOKEN="1//..."
supabase secrets set GOOGLE_CALENDAR_ID="traumatologiaccolon@gmail.com"
supabase secrets set LINK_BASE="https://febo983.github.io/ceot-recetas/videoconsulta/c.html?t="

supabase functions deploy videoconsulta
```

`LINK_BASE` es la dirección pública de `videoconsulta/c.html` terminada en
`?t=` — es el link que reciben los pacientes. Si después usás un dominio
propio, volvé a correr ese `secrets set` con la dirección nueva.

Después editá `videoconsulta/config.js` con los datos del paso 1:

```js
window.VC_CONFIG = {
  FN_URL: "https://xxxx.supabase.co/functions/v1/videoconsulta",
  ANON_KEY: "eyJ...",
  WA_SECRETARIA: "5492235823068"
};
```

Commiteá ese cambio y publicá el repo con **GitHub Pages**
(Settings → Pages → Deploy from branch → `main` / root). Queda:

- Panel de profesionales y secretarias → `…/videoconsulta/`
- Página del paciente → `…/videoconsulta/c.html?t=<token>` (la genera la app)

---

## Paso 4 — Prueba

1. Abrí `…/videoconsulta/` y entrá con el PIN de un profesional.
2. Cargá alias y monto en **Mis datos de cobro**.
3. Creá una videoconsulta para hoy.
4. Verificá que el evento aparezca en el calendario de
   `traumatologiaccolon@gmail.com` **con el Meet adentro**.
5. Abrí el link del paciente en el celular: tiene que mostrar día y horario,
   monto, alias con botón de copiar, y el botón para entrar al Meet.
6. Entrá con el PIN de una secretaria: tiene que ver la videoconsulta en la
   lista, con el botón para copiar o pasar el link.
7. Cancelá la prueba desde el panel del profesional y confirmá que el evento
   desapareció del calendario y que el link ya no funciona.

Repartí los PIN uno por uno (no en un grupo). Son personales.

---

## Cómo se usa, día a día

**Profesional**
1. La secretaria le avisa que hay un pedido de videoconsulta.
2. Abre `…/videoconsulta/`, entra con su PIN.
3. Elige día, hora de inicio y de fin. Alias y monto vienen precargados, los
   puede cambiar en esa consulta.
4. **Crear videoconsulta** → aparece el link. Toca **Enviar a la secretaria**
   (se abre WhatsApp con el mensaje armado) o **Copiar link**.

**Secretaria**
1. Recibe el link del profesional.
2. Lo reenvía al paciente, o entra con su PIN a `…/videoconsulta/` y lo copia
   desde la lista.

**Paciente**: abre el link, transfiere al alias y el día de la consulta entra al Meet.

---

## Si algo falla

| Síntoma | Causa más probable |
|---|---|
| "No pudimos entrar al calendario de la clínica" | El refresh token venció porque la app de Google quedó en estado *Prueba*. Publicala (paso 2.3) y volvé a generar el token (paso 2.5). |
| "Google no pudo crear el Meet" | Corte momentáneo de Google: reintentar. Si sigue, revisar que la Calendar API esté habilitada. |
| "Falta configurar la app" | `videoconsulta/config.js` quedó con los valores de ejemplo. |
| "PIN incorrecto" con el PIN correcto | El usuario está `activo = false`, o el PIN se reasignó a otra persona. |
| "Demasiados intentos" | 10 PIN fallidos desde la misma conexión: espera 15 minutos. |
| El link del paciente da "Link inválido" | La consulta se canceló, o `LINK_BASE` no coincide con la dirección publicada. |

Logs de la función: Supabase → **Edge Functions → videoconsulta → Logs**.
