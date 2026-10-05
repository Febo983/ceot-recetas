// Videoconsultas CEOT - unica Edge Function del sistema.
//
// El navegador manda POST {accion, ...} con la clave publica (anon).
// Todo el acceso a la base pasa por aca con la service role key, asi que las
// tablas quedan cerradas con RLS y sin politicas.
//
// Secrets que necesita (supabase secrets set ...):
//   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN
//   GOOGLE_CALENDAR_ID   -> traumatologiaccolon@gmail.com
//   LINK_BASE            -> https://.../videoconsulta/c.html?t=

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const TZ = "America/Argentina/Buenos_Aires";
const DURACION_MAX_MIN = 240;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const env = (k: string) => Deno.env.get(k) ?? "";

const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

type Usuario = {
  id: string;
  nombre: string;
  rol: "profesional" | "secretaria";
  alias: string | null;
  alias_titular: string | null;
  monto: number | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

const error = (msg: string, status = 400) => json({ ok: false, error: msg }, status);

// --- helpers ---------------------------------------------------------------

const esFecha = (v: unknown) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
const esHora = (v: unknown) => typeof v === "string" && /^\d{2}:\d{2}$/.test(v);
const minutos = (h: string) => Number(h.slice(0, 2)) * 60 + Number(h.slice(3, 5));
const limpiar = (v: unknown, max = 120) =>
  typeof v === "string" ? v.replace(/\s+/g, " ").trim().slice(0, max) : "";

function ipDe(req: Request) {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  return fwd.split(",")[0].trim() || null;
}

// Hoy en Argentina, como YYYY-MM-DD (el server corre en UTC).
function hoyArg() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

async function sesionDe(token: unknown): Promise<Usuario | null> {
  if (typeof token !== "string" || token.length < 32) return null;
  const { data } = await db
    .from("vc_sesiones")
    .select("expira_en, usuario:vc_usuarios(id, nombre, rol, alias, alias_titular, monto, activo)")
    .eq("token", token)
    .maybeSingle();

  if (!data?.usuario) return null;
  if (new Date(data.expira_en).getTime() < Date.now()) return null;
  const u = data.usuario as Usuario & { activo: boolean };
  if (!u.activo) return null;
  return u;
}

// --- Google Calendar -------------------------------------------------------

async function googleAccessToken(): Promise<string> {
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("GOOGLE_CLIENT_ID"),
      client_secret: env("GOOGLE_CLIENT_SECRET"),
      refresh_token: env("GOOGLE_REFRESH_TOKEN"),
      grant_type: "refresh_token",
    }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data.access_token) {
    console.error("google token", r.status, JSON.stringify(data));
    throw new Error("google_auth");
  }
  return data.access_token as string;
}

async function crearEventoConMeet(args: {
  titulo: string;
  descripcion: string;
  fecha: string;
  horaInicio: string;
  horaFin: string;
}) {
  const token = await googleAccessToken();
  const cal = encodeURIComponent(env("GOOGLE_CALENDAR_ID"));
  const r = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/${cal}/events?conferenceDataVersion=1`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({
        summary: args.titulo,
        description: args.descripcion,
        start: { dateTime: `${args.fecha}T${args.horaInicio}:00`, timeZone: TZ },
        end: { dateTime: `${args.fecha}T${args.horaFin}:00`, timeZone: TZ },
        conferenceData: {
          createRequest: {
            requestId: crypto.randomUUID(),
            conferenceSolutionKey: { type: "hangoutsMeet" },
          },
        },
        reminders: { useDefault: true },
      }),
    },
  );

  const ev = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error("google event", r.status, JSON.stringify(ev));
    throw new Error("google_evento");
  }

  const meet: string | undefined =
    ev.hangoutLink ??
    ev.conferenceData?.entryPoints?.find((e: { entryPointType?: string }) =>
      e.entryPointType === "video"
    )?.uri;

  if (!meet) throw new Error("google_sin_meet");
  return { meet, eventoId: ev.id as string };
}

async function borrarEvento(eventoId: string | null) {
  if (!eventoId) return;
  try {
    const token = await googleAccessToken();
    const cal = encodeURIComponent(env("GOOGLE_CALENDAR_ID"));
    await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/${cal}/events/${encodeURIComponent(eventoId)}`,
      { method: "DELETE", headers: { authorization: `Bearer ${token}` } },
    );
  } catch (e) {
    // La consulta se marca cancelada igual; el evento se limpia a mano si hace falta.
    console.error("borrarEvento", e);
  }
}

// --- acciones --------------------------------------------------------------

const COLUMNAS_CONSULTA =
  "id, token, fecha, hora_inicio, hora_fin, monto, alias, alias_titular, meet_url, estado, paciente_nombre, created_at, profesional:vc_usuarios(nombre)";

function linkDe(token: string) {
  return env("LINK_BASE") + token;
}

function salidaConsulta(c: Record<string, any>) {
  return {
    id: c.id,
    token: c.token,
    fecha: c.fecha,
    hora_inicio: String(c.hora_inicio).slice(0, 5),
    hora_fin: String(c.hora_fin).slice(0, 5),
    monto: Number(c.monto),
    alias: c.alias,
    alias_titular: c.alias_titular,
    meet_url: c.meet_url,
    estado: c.estado,
    paciente_nombre: c.paciente_nombre,
    profesional: c.profesional?.nombre ?? "",
    link: linkDe(c.token),
  };
}

async function accionLogin(req: Request, body: Record<string, unknown>) {
  const { data, error: e } = await db.rpc("vc_login", {
    p_pin: String(body.pin ?? ""),
    p_ip: ipDe(req),
  });
  if (e) {
    console.error("vc_login", e);
    return error("No pudimos validar el PIN. Intentá de nuevo.", 500);
  }
  const r = data as { ok: boolean; error?: string; token?: string; usuario?: Usuario };
  if (!r.ok) {
    if (r.error === "bloqueado") {
      return error("Demasiados intentos. Esperá 15 minutos.", 429);
    }
    return error("PIN incorrecto.", 401);
  }
  return json({ ok: true, token: r.token, usuario: r.usuario });
}

async function accionPerfil(u: Usuario, body: Record<string, unknown>) {
  const alias = limpiar(body.alias, 60);
  const titular = limpiar(body.alias_titular, 80);
  const monto = Number(body.monto);

  if (!alias) return error("Escribí tu alias para cobrar.");
  if (!Number.isFinite(monto) || monto < 0 || monto > 99999999) {
    return error("El monto no es válido.");
  }

  const { error: e } = await db
    .from("vc_usuarios")
    .update({ alias, alias_titular: titular || null, monto })
    .eq("id", u.id);

  if (e) {
    console.error("perfil", e);
    return error("No pudimos guardar tus datos.", 500);
  }
  return json({ ok: true, usuario: { ...u, alias, alias_titular: titular || null, monto } });
}

async function accionCrear(u: Usuario, body: Record<string, unknown>) {
  const fecha = body.fecha;
  const horaInicio = body.hora_inicio;
  const horaFin = body.hora_fin;

  if (!esFecha(fecha)) return error("Elegí el día de la consulta.");
  if (!esHora(horaInicio) || !esHora(horaFin)) return error("Elegí el horario de inicio y de fin.");
  if (fecha < hoyArg()) return error("Esa fecha ya pasó.");

  const dur = minutos(horaFin as string) - minutos(horaInicio as string);
  if (dur <= 0) return error("La hora de fin tiene que ser posterior a la de inicio.");
  if (dur > DURACION_MAX_MIN) return error("La consulta no puede durar más de 4 horas.");

  const alias = limpiar(body.alias, 60) || (u.alias ?? "");
  const titular = limpiar(body.alias_titular, 80) || (u.alias_titular ?? "");
  const monto = Number(body.monto ?? u.monto);
  const paciente = limpiar(body.paciente_nombre, 80);

  if (!alias) return error("Falta el alias para cobrar. Cargalo en Mis datos de cobro.");
  if (!Number.isFinite(monto) || monto < 0 || monto > 99999999) {
    return error("Falta el monto de la consulta.");
  }

  const token = crypto.randomUUID().replace(/-/g, "").slice(0, 20);
  const link = linkDe(token);

  let meet: string, eventoId: string;
  try {
    const ev = await crearEventoConMeet({
      titulo: `Videoconsulta - ${u.nombre}${paciente ? ` - ${paciente}` : ""}`,
      descripcion: [
        `Videoconsulta de ${u.nombre}.`,
        paciente ? `Paciente: ${paciente}` : null,
        `Monto: $${monto}`,
        `Alias para transferir: ${alias}${titular ? ` (${titular})` : ""}`,
        ``,
        `Link para el paciente: ${link}`,
      ].filter(Boolean).join("\n"),
      fecha: fecha as string,
      horaInicio: horaInicio as string,
      horaFin: horaFin as string,
    });
    meet = ev.meet;
    eventoId = ev.eventoId;
  } catch (e) {
    const msg = e instanceof Error ? e.message : "google";
    return error(
      msg === "google_auth"
        ? "No pudimos entrar al calendario de la clínica. Avisale al administrador."
        : "Google no pudo crear el Meet. Probá de nuevo en un minuto.",
      502,
    );
  }

  const { data, error: e } = await db
    .from("vc_consultas")
    .insert({
      token,
      profesional_id: u.id,
      paciente_nombre: paciente || null,
      fecha,
      hora_inicio: horaInicio,
      hora_fin: horaFin,
      monto,
      alias,
      alias_titular: titular || null,
      meet_url: meet,
      evento_id: eventoId,
    })
    .select(COLUMNAS_CONSULTA)
    .single();

  if (e) {
    console.error("crear", e);
    await borrarEvento(eventoId);
    return error("Creamos el Meet pero no pudimos guardar la consulta. Probá de nuevo.", 500);
  }

  // Si el profesional todavia no tenia alias/monto guardados, los dejamos listos.
  if (!u.alias || u.monto === null) {
    await db.from("vc_usuarios")
      .update({ alias, alias_titular: titular || null, monto })
      .eq("id", u.id);
  }

  return json({ ok: true, consulta: salidaConsulta(data) });
}

async function accionListar(u: Usuario, body: Record<string, unknown>) {
  const desde = body.desde === "todas"
    ? "2000-01-01"
    : new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);

  let q = db.from("vc_consultas").select(COLUMNAS_CONSULTA).gte("fecha", desde);
  if (u.rol === "profesional") q = q.eq("profesional_id", u.id);

  const { data, error: e } = await q
    .order("fecha", { ascending: true })
    .order("hora_inicio", { ascending: true })
    .limit(200);

  if (e) {
    console.error("listar", e);
    return error("No pudimos traer las videoconsultas.", 500);
  }
  return json({ ok: true, consultas: (data ?? []).map(salidaConsulta) });
}

async function accionCancelar(u: Usuario, body: Record<string, unknown>) {
  const id = String(body.id ?? "");
  if (!id) return error("Falta la consulta a cancelar.");

  let q = db.from("vc_consultas").select("id, evento_id, profesional_id").eq("id", id);
  if (u.rol === "profesional") q = q.eq("profesional_id", u.id);

  const { data: c } = await q.maybeSingle();
  if (!c) return error("No encontramos esa videoconsulta.", 404);

  await borrarEvento(c.evento_id);
  const { error: e } = await db.from("vc_consultas")
    .update({ estado: "cancelada", meet_url: null })
    .eq("id", c.id);

  if (e) {
    console.error("cancelar", e);
    return error("No pudimos cancelarla.", 500);
  }
  return json({ ok: true });
}

// Publica: la ve el paciente con el token del link.
async function accionConsultaPublica(body: Record<string, unknown>) {
  const token = String(body.token ?? "");
  if (!/^[a-f0-9]{20}$/.test(token)) return error("Link inválido.", 404);

  const { data, error: e } = await db
    .from("vc_consultas")
    .select(COLUMNAS_CONSULTA)
    .eq("token", token)
    .maybeSingle();

  if (e) {
    console.error("consulta publica", e);
    return error("No pudimos abrir el link.", 500);
  }
  if (!data) return error("Link inválido.", 404);

  const c = salidaConsulta(data);
  return json({
    ok: true,
    consulta: {
      profesional: c.profesional,
      paciente_nombre: c.paciente_nombre,
      fecha: c.fecha,
      hora_inicio: c.hora_inicio,
      hora_fin: c.hora_fin,
      monto: c.monto,
      alias: c.alias,
      alias_titular: c.alias_titular,
      meet_url: c.meet_url,
      estado: c.estado,
    },
  });
}

async function accionSalir(body: Record<string, unknown>) {
  const token = String(body.sesion ?? "");
  if (token) await db.from("vc_sesiones").delete().eq("token", token);
  return json({ ok: true });
}

// --- router ----------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return error("Método no permitido.", 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return error("Pedido inválido.");
  }

  const accion = String(body.accion ?? "");

  try {
    if (accion === "login") return await accionLogin(req, body);
    if (accion === "consulta") return await accionConsultaPublica(body);
    if (accion === "salir") return await accionSalir(body);

    const u = await sesionDe(body.sesion);
    if (!u) return error("Tu sesión venció. Volvé a entrar con tu PIN.", 401);

    if (accion === "yo") return json({ ok: true, usuario: u });
    if (accion === "listar") return await accionListar(u, body);

    if (u.rol !== "profesional") {
      return error("Esta acción es solo para profesionales.", 403);
    }
    if (accion === "perfil") return await accionPerfil(u, body);
    if (accion === "crear") return await accionCrear(u, body);
    if (accion === "cancelar") return await accionCancelar(u, body);

    return error("Acción desconocida.");
  } catch (e) {
    console.error("fallo", e);
    return error("Hubo un error inesperado. Probá de nuevo.", 500);
  }
});
