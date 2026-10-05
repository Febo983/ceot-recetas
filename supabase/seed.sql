-- ---------------------------------------------------------------------------
-- Carga inicial de usuarios con un PIN aleatorio de 6 digitos.
--
-- ANTES DE CORRER: completa en la lista de abajo los profesionales que falten.
-- Despues corre esto UNA vez en el SQL editor de Supabase y guarda la tabla que
-- devuelve: los PIN se guardan hasheados y despues no se pueden recuperar.
--
-- Para cambiar un PIN:  select vc_set_pin('Dr. Daniel Corelich', '482910');
-- ---------------------------------------------------------------------------
with gente (nombre, rol) as (
  values
    ('Dr. Maximiliano Bruni',        'profesional'),
    ('Dr. Daniel Corelich',          'profesional'),
    ('Dr. Cristian Deganutti',       'profesional'),
    ('Dr. Amilcar Trivellini',       'profesional'),
    ('Dr. Juan Pablo de la Colina',  'profesional'),
    ('Dr. Camilo Perlasco',          'profesional'),
    ('Dr. Daniel Labayén',           'profesional'),
    ('Dr. Maximiliano Mazzola',      'profesional'),
    -- >>> faltan 5 profesionales: agregalos aca, con el mismo formato <<<
    -- ('Dr. Nombre Apellido',       'profesional'),
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
