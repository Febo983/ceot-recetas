-- ---------------------------------------------------------------------------
-- Carga inicial de usuarios con un PIN aleatorio de 6 digitos.
--
-- Corre esto UNA vez en el SQL editor de Supabase y guarda la tabla que
-- devuelve: los PIN se guardan hasheados y despues no se pueden recuperar.
--
-- Para cambiar un PIN:     select vc_set_pin('Dr. Daniel Corelich', '482910');
-- Para corregir un nombre:  update vc_usuarios set nombre = 'Dr. Nombre Fisser'
--                             where nombre = 'Dr. Fisser';
-- ---------------------------------------------------------------------------
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
    -- Falta el nombre de pila de estos cinco (y confirmar Dr. / Dra.):
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

-- ---------------------------------------------------------------------------
-- Alta de alguien nuevo mas adelante (elegi vos el PIN, 6 digitos):
--   insert into vc_usuarios (nombre, rol, pin_hash)
--   values ('Dra. Nombre Apellido', 'profesional', crypt('123456', gen_salt('bf', 10)));
--
-- Baja (no borra sus videoconsultas, solo le saca el acceso):
--   update vc_usuarios set activo = false where nombre = 'Dr. Nombre Apellido';
-- ---------------------------------------------------------------------------
