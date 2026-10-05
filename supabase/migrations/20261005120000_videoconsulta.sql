-- ---------------------------------------------------------------------------
-- Videoconsultas CEOT
-- Profesionales crean el turno (dia + hora inicio + hora fin), la app crea el
-- evento con Google Meet en el calendario de la clinica y devuelve un link
-- para el paciente con el Meet, el alias de cobro y el monto.
-- ---------------------------------------------------------------------------

create extension if not exists pgcrypto;

-- Usuarios internos: profesionales y secretarias. Entran con un PIN.
create table if not exists vc_usuarios (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null unique,
  rol           text not null check (rol in ('profesional', 'secretaria')),
  pin_hash      text not null,
  activo        boolean not null default true,
  -- datos de cobro, solo para profesionales (editables desde la app)
  alias         text,
  alias_titular text,
  monto         numeric(12, 2),
  created_at    timestamptz not null default now()
);

-- Una videoconsulta = un evento de Google Calendar con Meet + datos de cobro.
create table if not exists vc_consultas (
  id              uuid primary key default gen_random_uuid(),
  token           text not null unique,          -- va en el link del paciente
  profesional_id  uuid not null references vc_usuarios (id) on delete restrict,
  paciente_nombre text,
  fecha           date not null,
  hora_inicio     time not null,
  hora_fin        time not null,
  monto           numeric(12, 2) not null,
  alias           text not null,
  alias_titular   text,
  meet_url        text,
  evento_id       text,                          -- id del evento en Calendar
  estado          text not null default 'activa' check (estado in ('activa', 'cancelada')),
  created_at      timestamptz not null default now(),
  constraint vc_consultas_horario check (hora_fin > hora_inicio)
);

create index if not exists vc_consultas_prof_fecha_idx
  on vc_consultas (profesional_id, fecha desc, hora_inicio desc);
create index if not exists vc_consultas_fecha_idx
  on vc_consultas (fecha desc, hora_inicio desc);

-- Sesiones de la app (12 hs). El PIN nunca se guarda del lado del navegador.
create table if not exists vc_sesiones (
  token      text primary key,
  usuario_id uuid not null references vc_usuarios (id) on delete cascade,
  expira_en  timestamptz not null,
  created_at timestamptz not null default now()
);

-- Intentos de login, para frenar fuerza bruta sobre el PIN.
create table if not exists vc_intentos (
  id         bigserial primary key,
  ip         text,
  exito      boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists vc_intentos_ip_idx on vc_intentos (ip, created_at desc);

-- Nadie entra directo con la clave publica: todo pasa por la Edge Function,
-- que usa la service role key y valida PIN, sesion y permisos.
alter table vc_usuarios  enable row level security;
alter table vc_consultas enable row level security;
alter table vc_sesiones  enable row level security;
alter table vc_intentos  enable row level security;

-- ---------------------------------------------------------------------------
-- Login por PIN: compara contra el hash bcrypt y abre la sesion.
-- ---------------------------------------------------------------------------
create or replace function vc_login(p_pin text, p_ip text default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fallidos int;
  v_usuario  vc_usuarios;
  v_token    text;
begin
  if p_pin is null or length(trim(p_pin)) < 4 then
    return json_build_object('ok', false, 'error', 'pin_invalido');
  end if;

  select count(*) into v_fallidos
    from vc_intentos
   where exito = false
     and ip = p_ip
     and created_at > now() - interval '15 minutes';

  if p_ip is not null and v_fallidos >= 10 then
    return json_build_object('ok', false, 'error', 'bloqueado');
  end if;

  select * into v_usuario
    from vc_usuarios
   where activo
     and pin_hash = crypt(trim(p_pin), pin_hash)
   limit 1;

  if not found then
    insert into vc_intentos (ip, exito) values (p_ip, false);
    return json_build_object('ok', false, 'error', 'pin_invalido');
  end if;

  insert into vc_intentos (ip, exito) values (p_ip, true);
  delete from vc_sesiones where expira_en < now();
  delete from vc_intentos where created_at < now() - interval '7 days';

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into vc_sesiones (token, usuario_id, expira_en)
  values (v_token, v_usuario.id, now() + interval '12 hours');

  return json_build_object(
    'ok', true,
    'token', v_token,
    'usuario', json_build_object(
      'id', v_usuario.id,
      'nombre', v_usuario.nombre,
      'rol', v_usuario.rol,
      'alias', v_usuario.alias,
      'alias_titular', v_usuario.alias_titular,
      'monto', v_usuario.monto
    )
  );
end;
$$;

revoke all on function vc_login(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Alta / cambio de PIN. Se usa desde el SQL editor de Supabase.
--   select vc_set_pin('Dr. Juan Perez', '123456');
-- ---------------------------------------------------------------------------
create or replace function vc_set_pin(p_nombre text, p_pin text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  if length(trim(p_pin)) < 4 then
    raise exception 'El PIN tiene que tener al menos 4 digitos';
  end if;

  update vc_usuarios
     set pin_hash = crypt(trim(p_pin), gen_salt('bf', 10))
   where nombre = p_nombre;

  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'No existe el usuario %', p_nombre;
  end if;

  -- un mismo PIN no puede quedar en dos usuarios
  if (select count(*) from vc_usuarios where activo and pin_hash = crypt(trim(p_pin), pin_hash)) > 1 then
    raise exception 'Ese PIN ya lo usa otro usuario, elegi otro';
  end if;

  return 'PIN actualizado para ' || p_nombre;
end;
$$;

revoke all on function vc_set_pin(text, text) from public, anon, authenticated;
