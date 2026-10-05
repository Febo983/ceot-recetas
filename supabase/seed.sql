-- ---------------------------------------------------------------------------
-- Carga inicial de usuarios con un PIN aleatorio de 6 digitos.
-- Corre esto UNA vez en el SQL editor de Supabase y guarda la tabla que
-- devuelve: los PIN se guardan hasheados y despues no se pueden recuperar.
-- Para cambiar uno: select vc_set_pin('Dr. Daniel Corelich', '482910');
-- ---------------------------------------------------------------------------
with gente (nombre, rol) as (
  values
    ('Dr. Maximiliano Bruni',        'profesional'),
    ('Dr. Daniel Corelich',          'profesional'),
    ('Dr. Cristian Deganutti',       'profesional'),
    ('Dr. Amilcar Trivellini',       'profesional'),
    ('Dr. Juan Pablo de la Colina',  'profesional'),
    ('Dr. Camilo Perlasco',          'profesional'),
    ('Dr. Daniel Labayen',           'profesional'),
    ('Dr. Maximiliano Mazzola',      'profesional'),
    ('Secretaria 1',                 'secretaria'),
    ('Secretaria 2',                 'secretaria')
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

-- Chequeo: ningun PIN quedo repetido entre dos usuarios.
-- (si devuelve filas, cambia uno con vc_set_pin)
-- select a.nombre, b.nombre
--   from vc_usuarios a join vc_usuarios b
--     on a.id < b.id and b.pin_hash = crypt('<pin de a>', b.pin_hash);
