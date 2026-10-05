-- ===========================================================================
-- VIDEOCONSULTAS CEOT - pegar entero en el SQL Editor de Supabase y dar Run.
-- Proyecto: "CEOT Videoconsultas" (guodzzlgomklcslgvzkk)
--
-- Las tablas ya estan creadas. Esto agrega las dos funciones, limpia unas
-- pruebas y carga a los 13 profesionales y las 2 secretarias con un PIN
-- aleatorio cada uno.
--
-- AL TERMINAR: la ultima tabla que devuelve trae los PIN. Copiala y guardala
-- ANTES de cerrar la pestana: quedan hasheados y no se pueden recuperar.
-- ===========================================================================

-- 1. Limpieza de funciones de prueba -----------------------------------------
drop function if exists vc_ping();
drop function if exists vc_t1();
drop function if exists vc_t2();
drop function if exists vc_t3();
drop function if exists vc_t4();
drop function if exists vc_t5(text);
drop function if exists vc_t6();
drop function if exists vc_t7();

-- 2. Login por PIN -----------------------------------------------------------
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

-- Que nadie pueda llamarla desde afuera con la clave publica: solo la
-- Edge Function, que usa la service role key.
revoke all on function vc_login(text, text) from public, anon, authenticated;

-- 3. Cambio de PIN -----------------------------------------------------------
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

  if (select count(*) from vc_usuarios where activo and pin_hash = crypt(trim(p_pin), pin_hash)) > 1 then
    raise exception 'Ese PIN ya lo usa otro usuario, elegi otro';
  end if;

  return 'PIN actualizado para ' || p_nombre;
end;
$$;

revoke all on function vc_set_pin(text, text) from public, anon, authenticated;

-- 4. Carga de usuarios con PIN aleatorio -------------------------------------
with gente (nombre, rol) as (
  values
    ('Dr. Maximiliano Bruni',        'profesional'),
    ('Dr. Daniel Corelich',          'profesional'),
    ('Dr. Cristian Deganutti',       'profesional'),
    ('Dr. Juan Pablo de la Colina',  'profesional'),
    ('Dr. Daniel Labayén',           'profesional'),
    ('Dr. Maximiliano Mazzola',      'profesional'),
    ('Dr. Camilo Perlasco',          'profesional'),
    ('Dr. Amilcar Trivellini',       'profesional'),
    ('Dr. Fisser',                   'profesional'),
    ('Dr. Garmendia',                'profesional'),
    ('Dr. Guilera',                  'profesional'),
    ('Dr. León',                     'profesional'),
    ('Dr. Soulé',                    'profesional'),
    ('Secretaría 14',                'secretaria'),
    ('Secretaría 11',                'secretaria')
),
con_pin as (
  select nombre,
         rol,
         lpad((floor(random() * 900000) + 100000)::int::text, 6, '0') as pin
    from gente
),
insertados as (
  insert into vc_usuarios (nombre, rol, pin_hash)
  select nombre, rol, crypt(pin, gen_salt('bf', 10)) from con_pin
  on conflict (nombre) do nothing
  returning nombre
)
select nombre,
       rol,
       pin as "PIN -- anotalo ahora, no se puede recuperar",
       case when nombre in (select nombre from insertados)
            then 'creado'
            else 'ya existia: el PIN de arriba NO aplica' end as resultado
  from con_pin
 order by rol, nombre;
