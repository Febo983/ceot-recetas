# Videoconsultas CEOT — qué está hecho y qué falta

## Ya está hecho

- **Proyecto Supabase** `CEOT Videoconsultas` (ref `guodzzlgomklcslgvzkk`, región São Paulo).
- **Tablas e índices** creados, con RLS activado y sin políticas: la clave
  pública no sirve para leer ni escribir nada.
- **Edge Function** `videoconsulta` desplegada en
  `https://guodzzlgomklcslgvzkk.supabase.co/functions/v1/videoconsulta`.
- **`videoconsulta/config.js`** apuntando a ese proyecto.

## Falta (en este orden)

### 1. Correr el SQL

SQL Editor de Supabase → **New query** → pegar entero
[`docs/pegar-en-supabase.sql`](pegar-en-supabase.sql) → **Run**.

Crea las dos funciones (`vc_login` y `vc_set_pin`) y carga a los 13
profesionales y las 2 secretarías con un **PIN aleatorio de 6 dígitos cada uno**.
La última tabla que devuelve trae los PIN: **copiala y guardala antes de cerrar
la pestaña**, quedan hasheados y no se pueden recuperar.

Para cambiar un PIN más adelante:

```sql
select vc_set_pin('Dr. Daniel Corelich', '482910');
```

Para corregir un nombre (a los cinco nuevos les falta el nombre de pila):

```sql
update vc_usuarios set nombre = 'Dr. Nombre Fisser' where nombre = 'Dr. Fisser';
```

### 2. El permiso de Google

Autoriza, **una sola vez**, a que la app cree los Meet en el calendario de la
clínica. Hay que estar logueado con `traumatologiaccolon@gmail.com`.

1. [console.cloud.google.com](https://console.cloud.google.com) → crear un
   proyecto `CEOT Videoconsultas`.
2. **APIs y servicios → Biblioteca** → **Google Calendar API** → **Habilitar**.
3. **APIs y servicios → Pantalla de consentimiento de OAuth**:
   - Tipo de usuario: **Externo**.
   - Nombre: `Videoconsultas CEOT`. Mails de soporte y contacto:
     `traumatologiaccolon@gmail.com`.
   - En **Permisos**, agregar el scope `https://www.googleapis.com/auth/calendar.events`.
   - ⚠️ **Al terminar, tocar "Publicar la app"**: tiene que quedar en estado
     *En producción*, no *Prueba*. Si queda en *Prueba*, el permiso **se vence
     cada 7 días** y la app deja de crear Meet. Google va a avisar que la app
     "no está verificada": está bien, la autoriza una sola cuenta.
4. **APIs y servicios → Credenciales → Crear credenciales → ID de cliente de OAuth**:
   - Tipo: **Aplicación web**, nombre `CEOT`.
   - En **URIs de redireccionamiento autorizados**, exactamente:
     `https://developers.google.com/oauthplayground`
   - Anotar el **ID de cliente** y el **Secreto del cliente**.
5. [developers.google.com/oauthplayground](https://developers.google.com/oauthplayground):
   - Engranaje → **Use your own OAuth credentials** → pegar ID y secreto.
   - En el campo de scopes de la izquierda:
     `https://www.googleapis.com/auth/calendar.events` → **Authorize APIs**.
   - Elegir `traumatologiaccolon@gmail.com` y aceptar (si aparece el aviso de
     app no verificada: *Configuración avanzada → Ir a Videoconsultas CEOT*).
   - **Exchange authorization code for tokens** → copiar el **Refresh token**
     (empieza con `1//`).

> El refresh token da permiso para crear y borrar eventos en el calendario de la
> clínica. Va solo a los secrets de Supabase, nunca al repositorio ni a un chat.

### 3. Cargar los secrets

Supabase → **Edge Functions → videoconsulta → Secrets** (o Project Settings →
Edge Functions → Secrets):

| Nombre | Valor |
|---|---|
| `GOOGLE_CLIENT_ID` | el del paso 2.4 |
| `GOOGLE_CLIENT_SECRET` | el del paso 2.4 |
| `GOOGLE_REFRESH_TOKEN` | el del paso 2.5 |
| `GOOGLE_CALENDAR_ID` | `traumatologiaccolon@gmail.com` |
| `LINK_BASE` | `https://febo983.github.io/ceot-recetas/videoconsulta/c.html?t=` |

`LINK_BASE` es la dirección pública de `videoconsulta/c.html` terminada en `?t=`
— es el link que reciben los pacientes. Si después se usa un dominio propio,
hay que cambiarlo acá.

### 4. Publicar la web

GitHub → **Settings → Pages** → Deploy from branch → `main` / root. Queda:

- Panel de profesionales y secretarías → `…/videoconsulta/`
- Página del paciente → `…/videoconsulta/c.html?t=<token>` (la genera la app)

### 5. Probar

1. Abrir `…/videoconsulta/` y entrar con el PIN de un profesional.
2. Cargar alias y monto en **Mis datos de cobro**.
3. Crear una videoconsulta para hoy.
4. Verificar que el evento aparezca en el calendario de
   `traumatologiaccolon@gmail.com` **con el Meet adentro**.
5. Abrir el link del paciente en el celular: día y horario, monto, alias con
   botón de copiar, y el botón para entrar al Meet.
6. Entrar con el PIN de una secretaría: tiene que ver esa videoconsulta.
7. Cancelarla desde el panel del profesional y confirmar que el evento
   desapareció del calendario y que el link ya no funciona.

Repartir los PIN uno por uno, no en un grupo. Son personales.

---

## Cómo se usa, día a día

**Profesional**
1. La secretaría le avisa que hay un pedido de videoconsulta.
2. Abre `…/videoconsulta/` y entra con su PIN.
3. Elige día, hora de inicio y de fin. Alias y monto vienen precargados y los
   puede cambiar en esa consulta.
4. **Crear videoconsulta** → aparece el link. **Pasar por WhatsApp** abre
   WhatsApp con el mensaje ya armado para mandárselo a la secretaría, o
   **Copiar link**.

**Secretaría**
1. Recibe el link del profesional.
2. Lo reenvía al paciente, o entra con su PIN y lo copia desde la lista.

**Paciente**: abre el link, transfiere al alias y el día de la consulta entra al Meet.

---

## Si algo falla

| Síntoma | Causa más probable |
|---|---|
| "No pudimos entrar al calendario de la clínica" | El refresh token venció porque la app de Google quedó en estado *Prueba*. Publicarla (paso 2.3) y volver a generar el token (paso 2.5). |
| "Google no pudo crear el Meet" | Corte momentáneo de Google: reintentar. Si sigue, revisar que la Calendar API esté habilitada. |
| "No pudimos validar el PIN" | No se corrió el SQL del paso 1, o falló `vc_login`. |
| "PIN incorrecto" con el PIN correcto | El usuario está `activo = false`, o el PIN se reasignó a otra persona. |
| "Demasiados intentos" | 10 PIN fallidos desde la misma conexión: espera 15 minutos. |
| El link del paciente da "Link inválido" | La consulta se canceló, o `LINK_BASE` no coincide con la dirección publicada. |

Logs de la función: Supabase → **Edge Functions → videoconsulta → Logs**.
