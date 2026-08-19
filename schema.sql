-- ════════════════════════════════════════════════════════════════
-- 3er HR TRIBE SUMMIT 2026 · HUMAN FIRST
-- Centro de Control Operativo — esquema Supabase
-- Evento: 26 de agosto de 2026 · Club Casino Monterrey
-- Ejecutar completo en el SQL Editor de Supabase (una sola vez).
-- Es idempotente: se puede volver a correr sin duplicar datos.
-- ════════════════════════════════════════════════════════════════

-- ─── 1. CATÁLOGO DE TRACKS ──────────────────────────────────────
create table if not exists public.summit_ops_tracks (
  clave       text primary key,
  nombre      text not null,
  color       text not null default '#33B4D2',
  orden       int  not null default 0
);

insert into public.summit_ops_tracks (clave, nombre, color, orden) values
  ('PMO', 'Dirección & PMO', '#E8C547', 1),
  ('SEDE', 'Sede & Logística', '#33B4D2', 2),
  ('AYB', 'Alimentos & Bebidas', '#F4A261', 3),
  ('REG', 'Registro, Gafetes & Experiencia', '#7CD3E8', 4),
  ('PRG', 'Programa & Speakers', '#B47FE0', 5),
  ('TLL', 'Talleres Simultáneos', '#4CC65C', 6),
  ('AV', 'Producción & AV', '#FF6B9D', 7),
  ('PAT', 'Patrocinadores & Aliados', '#C9A227', 8),
  ('MKT', 'Marketing & Comunicación', '#3AEBFF', 9),
  ('VTA', 'Ventas & Boletaje', '#FF8A5B', 10),
  ('FIN', 'Finanzas & Administración', '#8FA6C4', 11),
  ('RSK', 'Riesgos & Contingencias', '#E5484D', 12),
  ('POST', 'Post-Evento', '#5EEAD4', 13)
on conflict (clave) do update
  set nombre = excluded.nombre, color = excluded.color, orden = excluded.orden;

-- ─── 2. TABLA PRINCIPAL DE ACTIVIDADES ──────────────────────────
create table if not exists public.summit_ops_actividades (
  id            bigint generated always as identity primary key,
  codigo        text not null unique,
  track         text not null references public.summit_ops_tracks(clave) on update cascade,
  actividad     text not null,
  entregable    text not null default 'Por definir',
  responsable   text not null default 'Por asignar',
  fecha_limite  date not null,
  criticidad    text not null default 'Alta'
                check (criticidad in ('Crítica','Alta','Media')),
  estado        text not null default 'No iniciada'
                check (estado in ('No iniciada','En curso','Bloqueada','Lista')),
  notas         text default '',
  evidencia_url text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_summit_ops_track  on public.summit_ops_actividades (track);
create index if not exists idx_summit_ops_fecha  on public.summit_ops_actividades (fecha_limite);
create index if not exists idx_summit_ops_estado on public.summit_ops_actividades (estado);
create index if not exists idx_summit_ops_resp   on public.summit_ops_actividades (responsable);

-- ─── 3. TRIGGER updated_at ──────────────────────────────────────
create or replace function public.summit_ops_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_summit_ops_touch on public.summit_ops_actividades;
create trigger trg_summit_ops_touch
  before update on public.summit_ops_actividades
  for each row execute function public.summit_ops_touch();

-- ─── 4. BITÁCORA DE CAMBIOS (auditoría del comité) ──────────────
create table if not exists public.summit_ops_bitacora (
  id          bigint generated always as identity primary key,
  codigo      text not null,
  campo       text not null,
  valor_ant   text,
  valor_nuevo text,
  ts          timestamptz not null default now()
);

create or replace function public.summit_ops_log()
returns trigger language plpgsql as $$
begin
  if new.estado is distinct from old.estado then
    insert into public.summit_ops_bitacora (codigo, campo, valor_ant, valor_nuevo)
    values (new.codigo, 'estado', old.estado, new.estado);
  end if;
  if new.responsable is distinct from old.responsable then
    insert into public.summit_ops_bitacora (codigo, campo, valor_ant, valor_nuevo)
    values (new.codigo, 'responsable', old.responsable, new.responsable);
  end if;
  if new.fecha_limite is distinct from old.fecha_limite then
    insert into public.summit_ops_bitacora (codigo, campo, valor_ant, valor_nuevo)
    values (new.codigo, 'fecha_limite', old.fecha_limite::text, new.fecha_limite::text);
  end if;
  return new;
end $$;

drop trigger if exists trg_summit_ops_log on public.summit_ops_actividades;
create trigger trg_summit_ops_log
  after update on public.summit_ops_actividades
  for each row execute function public.summit_ops_log();

-- ─── 5. VISTAS PARA EL DASHBOARD ────────────────────────────────
create or replace view public.summit_ops_v_actividades as
select a.*,
       t.nombre as track_nombre,
       t.color  as track_color,
       (a.estado <> 'Lista' and a.fecha_limite <  current_date) as vencida,
       (a.estado <> 'Lista' and a.fecha_limite =  current_date) as vence_hoy,
       (a.fecha_limite - current_date)                          as dias_restantes,
       case a.estado when 'Lista' then 100 when 'En curso' then 50
                     when 'Bloqueada' then 10 else 0 end        as avance_pct
from public.summit_ops_actividades a
join public.summit_ops_tracks t on t.clave = a.track;

create or replace view public.summit_ops_v_dashboard as
select t.clave                                              as track,
       t.nombre                                             as track_nombre,
       t.color                                              as track_color,
       count(*)                                             as total,
       count(*) filter (where a.estado = 'Lista')           as listas,
       count(*) filter (where a.estado = 'En curso')        as en_curso,
       count(*) filter (where a.estado = 'Bloqueada')       as bloqueadas,
       count(*) filter (where a.estado = 'No iniciada')     as no_iniciadas,
       count(*) filter (where a.estado <> 'Lista'
                          and a.fecha_limite < current_date) as vencidas,
       count(*) filter (where a.criticidad = 'Crítica'
                          and a.estado <> 'Lista')           as criticas_abiertas,
       round(avg(case a.estado when 'Lista' then 100 when 'En curso' then 50
                               when 'Bloqueada' then 10 else 0 end))::int as avance_pct
from public.summit_ops_tracks t
join public.summit_ops_actividades a on a.track = t.clave
group by t.clave, t.nombre, t.color, t.orden
order by t.orden;

create or replace view public.summit_ops_v_carga_responsable as
select responsable,
       count(*) filter (where estado <> 'Lista')                          as abiertas,
       count(*) filter (where estado <> 'Lista' and criticidad='Crítica') as criticas,
       count(*) filter (where estado <> 'Lista'
                          and fecha_limite < current_date)                as vencidas,
       count(*)                                                          as total
from public.summit_ops_actividades
group by responsable
order by abiertas desc;

-- ─── 6. RLS Y POLÍTICAS ─────────────────────────────────────────
-- El tablero es una página estática con anon key: el comité lee y edita.
-- Si más adelante quieres restringir la escritura, cambia 'anon' por
-- 'authenticated' en las tres políticas de escritura.
alter table public.summit_ops_actividades enable row level security;
alter table public.summit_ops_tracks      enable row level security;
alter table public.summit_ops_bitacora    enable row level security;

drop policy if exists p_act_select on public.summit_ops_actividades;
drop policy if exists p_act_insert on public.summit_ops_actividades;
drop policy if exists p_act_update on public.summit_ops_actividades;
drop policy if exists p_act_delete on public.summit_ops_actividades;
create policy p_act_select on public.summit_ops_actividades for select to anon, authenticated using (true);
create policy p_act_insert on public.summit_ops_actividades for insert to anon, authenticated with check (true);
create policy p_act_update on public.summit_ops_actividades for update to anon, authenticated using (true) with check (true);
create policy p_act_delete on public.summit_ops_actividades for delete to anon, authenticated using (true);

drop policy if exists p_trk_select on public.summit_ops_tracks;
create policy p_trk_select on public.summit_ops_tracks for select to anon, authenticated using (true);

drop policy if exists p_bit_select on public.summit_ops_bitacora;
drop policy if exists p_bit_insert on public.summit_ops_bitacora;
create policy p_bit_select on public.summit_ops_bitacora for select to anon, authenticated using (true);
create policy p_bit_insert on public.summit_ops_bitacora for insert to anon, authenticated with check (true);

-- ─── 7. REALTIME (actualización automática del tablero) ─────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'summit_ops_actividades'
  ) then
    alter publication supabase_realtime add table public.summit_ops_actividades;
  end if;
end $$;

-- ─── 8. CARGA INICIAL: 137 ACTIVIDADES ─────────────────────────
insert into public.summit_ops_actividades
  (codigo, track, actividad, entregable, responsable, fecha_limite, criticidad, estado, notas)
values
  ('PMO-001', 'PMO', 'Cierre y congelamiento de la agenda final', 'Agenda final aprobada (PDF v.final) sin cambios de contenido', 'Héctor León', '2026-08-17'::date, 'Crítica', 'Lista', 'Ya generada y distribuida. A partir de aquí solo correcciones tipográficas.'),
  ('PMO-002', 'PMO', 'Reunión de comité T-7: arranque del sprint final', 'Minuta con dueño y fecha por cada pendiente abierto', 'Héctor León', '2026-08-19'::date, 'Crítica', 'En curso', 'Es la junta que dispara todo el plan de esta semana.'),
  ('PMO-003', 'PMO', 'Publicar el tablero de control operativo y dar accesos al comité', 'URL del tablero + 20 accesos confirmados', 'Héctor León', '2026-08-19'::date, 'Crítica', 'En curso', 'Este tablero. Fuente única de verdad para los 13 tracks.'),
  ('PMO-004', 'PMO', 'Stand-up diario de 15 min (20–25 ago, 8:30 a.m.)', 'Bitácora diaria de avance y bloqueos', 'Héctor León', '2026-08-20'::date, 'Alta', 'No iniciada', 'Formato: qué cerré ayer / qué cierro hoy / qué me bloquea.'),
  ('PMO-005', 'PMO', 'Walkthrough físico de sede con checklist de montaje', 'Reporte de recorrido con fotos, medidas y ajustes', 'Héctor León', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Ir con el plano de plenaria y el de las 7 salas de talleres.'),
  ('PMO-006', 'PMO', 'Documento maestro Run of Show minuto a minuto', 'Run of Show v.final firmado por cada track', 'Héctor León', '2026-08-22'::date, 'Crítica', 'No iniciada', 'Debe incluir transiciones, quién habla, quién entrega micrófono y tiempos de colchón.'),
  ('PMO-007', 'PMO', 'Asignación de staff y voluntarios por estación', 'Organigrama del día D con nombre, estación, turno y radio', 'Elsa Reynoso', '2026-08-22'::date, 'Alta', 'No iniciada', 'Estimado: 18–22 personas entre staff, voluntarios y anfitriones de taller.'),
  ('PMO-008', 'PMO', 'Briefing general de staff y voluntarios', 'Staff capacitado + manual de estación de una página c/u', 'Elsa Reynoso', '2026-08-25'::date, 'Crítica', 'No iniciada', 'Presencial en sede la tarde del montaje.'),
  ('PMO-009', 'PMO', 'Junta de cierre T-1: go / no-go por track', 'Acta go/no-go firmada por los 13 líderes de track', 'Héctor León', '2026-08-25'::date, 'Crítica', 'No iniciada', 'Si un track está en no-go, se activa su plan B esa misma noche.'),
  ('PMO-010', 'PMO', 'Sala de control, radios y canal de coordinación del día D', 'Grupo operativo activo + 8 radios entregados con pilas de repuesto', 'Sergio Morales', '2026-08-25'::date, 'Alta', 'No iniciada', 'WhatsApp se satura: los radios son para producción, registro y A&B.'),
  ('SEDE-001', 'SEDE', 'Contrato y confirmación de salones (plenaria + breakouts)', 'Contrato firmado y layout general aprobado por la sede', 'Héctor León', '2026-08-10'::date, 'Crítica', 'Lista', 'Club Casino Monterrey, 7:30 a.m. – 8:00 p.m.'),
  ('SEDE-002', 'SEDE', 'Layout de montaje de plenaria para 200 pax', 'Plano de montaje aprobado por sede y proveedor', 'Sergio Morales', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Recomendado media luna en mesas redondas: la agenda tiene experiencia colaborativa y LEGO.'),
  ('SEDE-003', 'SEDE', 'Layout y validación de las 7 salas de talleres simultáneos', 'Matriz sala/capacidad/aforo confirmada con la sede', 'Sergio Morales', '2026-08-20'::date, 'Crítica', 'No iniciada', 'RIESGO: la agenda anuncia 7 talleres en paralelo. Si la sede no tiene 7 espacios aislados, hay que fusionar o rotar.'),
  ('SEDE-004', 'SEDE', 'Mobiliario: sillas, mesas redondas, cocktail tables y lounge', 'Orden de mobiliario confirmada con proveedor y horario de entrega', 'Sergio Morales', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Incluir 25 mesas redondas para el bloque de LEGO Serious Play.'),
  ('SEDE-005', 'SEDE', 'Mobiliario y montaje de zona de registro', 'Confirmación de 3 mesas, backdrop, portagafetes y bancos', 'Adriana Obregón', '2026-08-21'::date, 'Alta', 'No iniciada', 'La fila de 7:30 a 9:00 es el primer momento de verdad del evento.'),
  ('SEDE-006', 'SEDE', 'Señalética: rutas, salones, talleres, baños y patrocinadores', 'Artes a imprenta + plano de colocación', 'Claudia Landeros', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Con 7 talleres simultáneos, la señalética evita 20 min de caos a las 3:00 p.m.'),
  ('SEDE-007', 'SEDE', 'Backdrop / photo opportunity con logos de patrocinadores', 'Backdrop impreso, montado y fotografiado', 'Claudia Landeros', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Es entregable contractual de varios patrocinios.'),
  ('SEDE-008', 'SEDE', 'Plan de estacionamiento, valet y accesos', 'Instructivo de llegada enviado a asistentes', 'Sergio Morales', '2026-08-22'::date, 'Alta', 'No iniciada', '200 personas llegando entre 7:30 y 9:00 saturan el acceso.'),
  ('SEDE-009', 'SEDE', 'Cronograma de montaje y desmontaje con la sede', 'Calendario de acceso: montaje 25 ago p.m. / desmontaje 26 ago 8:00 p.m.', 'Sergio Morales', '2026-08-22'::date, 'Crítica', 'No iniciada', 'Confirmar por escrito la hora de acceso de proveedores.'),
  ('SEDE-010', 'SEDE', 'Guardarropa y guarda-objetos', 'Estación habilitada con fichas numeradas', 'Mónica Sánchez', '2026-08-25'::date, 'Media', 'No iniciada', ''),
  ('SEDE-011', 'SEDE', 'Climatización, iluminación y prueba de acústica de sala', 'Checklist de sala firmado por la sede', 'Sergio Morales', '2026-08-25'::date, 'Alta', 'No iniciada', 'Sala llena a 200 pax sube 4-5 °C: pedir clima 2 °C abajo desde las 7:00 a.m.'),
  ('SEDE-012', 'SEDE', 'Montaje general y sellado de sala la noche previa', 'Sala montada, fotografiada y bajo llave', 'Sergio Morales', '2026-08-25'::date, 'Crítica', 'No iniciada', 'Nada de montaje la mañana del evento: el registro abre a las 7:30.'),
  ('AYB-001', 'AYB', 'Cierre del número de garantía de comensales con banquete', 'Confirmación escrita de garantía y política de penalización', 'Carolina Paredes', '2026-08-21'::date, 'Crítica', 'No iniciada', 'El corte suele ser 72 h antes. Con 7 boletos vendidos hoy, garantizar de más es la fuga financiera #1.'),
  ('AYB-002', 'AYB', 'Menú de desayuno 7:30–9:00 (estaciones + café)', 'Menú confirmado y firmado con la sede', 'Carolina Paredes', '2026-08-20'::date, 'Alta', 'No iniciada', 'Formato de pie / estaciones para favorecer el networking.'),
  ('AYB-003', 'AYB', 'Coffee breaks: 10:50–11:20 y 4:40–5:00', 'Servicio confirmado con horarios exactos y puntos de montaje', 'Carolina Paredes', '2026-08-20'::date, 'Alta', 'No iniciada', 'Montar en foyer, no en plenaria, para forzar el movimiento.'),
  ('AYB-004', 'AYB', 'Comida 1:40–3:00: menú, montaje y tiempos de servicio', 'Menú + compromiso de servicio completo en 25 min', 'Carolina Paredes', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Solo hay 80 min y a las 3:00 arrancan 7 talleres. Si la comida se alarga, se cae el bloque.'),
  ('AYB-005', 'AYB', 'Cocktail 6:15–8:00: canapés y barra', 'Menú de cocktail y barra confirmados', 'Carolina Paredes', '2026-08-21'::date, 'Alta', 'No iniciada', 'Coincide con FuckUp Nights: servicio silencioso durante las historias.'),
  ('AYB-006', 'AYB', 'Activación de la barra Kali Coffee (patrocinada)', 'Espacio, tomas eléctricas y horario acordados con la marca', 'Carolina Paredes', '2026-08-22'::date, 'Alta', 'No iniciada', 'Beneficio prometido a las primeras 100 personas: hay que poder cumplirlo todo el día.'),
  ('AYB-007', 'AYB', 'Activación Fitzer y Vinos RGMX en el cocktail', 'Producto en sede, hieleras, cristalería y personal de barra', 'Juan Bernal', '2026-08-24'::date, 'Alta', 'No iniciada', 'Confirmar quién surte, quién sirve y a qué hora entra el producto.'),
  ('AYB-008', 'AYB', 'Requerimientos alimenticios especiales (vegano, celíaco, alergias)', 'Lista final de menús especiales entregada al banquete', 'Mónica Sánchez', '2026-08-24'::date, 'Alta', 'No iniciada', 'Hoy el formulario de registro no lo pregunta: agregarlo YA al correo de confirmación.'),
  ('AYB-009', 'AYB', 'Alimentos de staff, voluntarios, speakers y proveedores', 'Cortesías confirmadas (aprox. 35 pax) y zona de consumo', 'Carolina Paredes', '2026-08-24'::date, 'Media', 'No iniciada', ''),
  ('AYB-010', 'AYB', 'Green room de speakers con snacks, agua y espejo', 'Sala habilitada desde las 8:00 a.m. con anfitrión', 'Mariel Esquivel', '2026-08-26'::date, 'Alta', 'No iniciada', '21 ponentes rotando: sin green room se meten a la plenaria y distraen.'),
  ('REG-001', 'REG', 'Diseño del gafete (credencial) con branding y QR', 'Arte final aprobado, listo para impresión', 'Claudia Landeros', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Nombre en tipografía grande legible a 2 metros: es una herramienta de networking, no un trámite.'),
  ('REG-002', 'REG', 'Categorías y colores de gafete (asistente, speaker, staff, patrocinador, prensa, VIP)', 'Matriz de acreditación aprobada', 'Adriana Obregón', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Define quién entra al green room y a las zonas de patrocinador.'),
  ('REG-003', 'REG', 'Base final de asistentes desde WeChamber para impresión', 'CSV depurado con nombre, empresa y puesto', 'Elsie', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Corte de impresión. Los registros posteriores se imprimen en sitio.'),
  ('REG-004', 'REG', 'Impresión de gafetes preimpresos + 60 en blanco para walk-ins', 'Gafetes impresos, alfabetizados y en cajas por letra', 'Adriana Obregón', '2026-08-25'::date, 'Crítica', 'No iniciada', 'Alfabetizar por apellido y separar en 3 filas (A-G / H-P / Q-Z).'),
  ('REG-005', 'REG', 'Portagafetes, lanyards y clips', '250 piezas en sede', 'Adriana Obregón', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('REG-006', 'REG', 'Sistema de check-in (QR / lista digital) con plan B en papel', 'App probada con 20 registros de prueba + listas impresas por duplicado', 'Elsie', '2026-08-25'::date, 'Crítica', 'No iniciada', 'El plan B en papel no es opcional: el wifi de un hotel lleno siempre falla.'),
  ('REG-007', 'REG', 'Guion y capacitación del equipo de registro', '6 personas capacitadas + script de bienvenida de 15 segundos', 'Adriana Obregón', '2026-08-25'::date, 'Alta', 'No iniciada', ''),
  ('REG-008', 'REG', 'Kit del asistente (libreta, pluma, agenda, insertos de patrocinador)', '220 kits armados, contados y en cajas', 'Ana María Quintanilla', '2026-08-24'::date, 'Alta', 'No iniciada', 'Armarlos el 24-25, no la mañana del evento.'),
  ('REG-009', 'REG', 'Agenda impresa de bolsillo con talleres y QR de evaluación', 'Arte enviado a imprenta', 'Claudia Landeros', '2026-08-21'::date, 'Alta', 'No iniciada', 'Debe traer el mapa de las 7 salas de talleres.'),
  ('REG-010', 'REG', 'Preinscripción a talleres simultáneos para evitar sobrecupo', 'Formulario enviado + reporte de cupos por taller', 'Elsie', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Sin esto, 3 talleres se saturan y 4 quedan vacíos. Es el riesgo de experiencia #1 de la tarde.'),
  ('REG-011', 'REG', 'Operación del retrato profesional (cortesía Great Place to Work)', 'Set fotográfico, agenda de turnos y lista de los primeros 100', 'Mónica Sánchez', '2026-08-24'::date, 'Alta', 'No iniciada', 'Beneficio publicado: hay que tener el control de quién califica y en qué horarios se toma.'),
  ('REG-012', 'REG', 'Mecánica de networking (mesas temáticas, pines o app)', 'Dinámica definida y materiales listos', 'Mónica Sánchez', '2026-08-22'::date, 'Media', 'No iniciada', 'El evento promete conversaciones: hay que provocarlas, no esperarlas.'),
  ('REG-013', 'REG', 'Mesa de atención, lost & found y soporte al asistente', 'Estación con responsable por turnos', 'Mónica Sánchez', '2026-08-25'::date, 'Media', 'No iniciada', ''),
  ('PRG-001', 'PRG', 'Confirmación por escrito de los 21 ponentes, moderadores y panelistas', 'Correo de confirmación de cada uno con horario y formato', 'Mariel Esquivel', '2026-08-14'::date, 'Crítica', 'Lista', 'Keynote, caso de éxito, debate, panel, experiencia, 7 talleres, recap y 6 FuckUp.'),
  ('PRG-002', 'PRG', 'Recepción de presentaciones de keynote y caso de éxito', 'Archivos 16:9 de Brenda Hernández y Jennifer Jassely en el servidor', 'Mariel Esquivel', '2026-08-22'::date, 'Crítica', 'No iniciada', 'Deadline duro: sin material no hay ensayo técnico el 25.'),
  ('PRG-003', 'PRG', 'Recepción de materiales de los 7 talleres', 'Presentación + lista de materiales por taller', 'Kata Molina', '2026-08-22'::date, 'Crítica', 'No iniciada', ''),
  ('PRG-004', 'PRG', 'Briefing individual con cada speaker (tiempo, formato, mensaje clave)', 'Bitácora de briefings 21/21 completada', 'Mariel Esquivel', '2026-08-23'::date, 'Crítica', 'No iniciada', 'Incluir la regla de tiempo: el reloj en pantalla manda.'),
  ('PRG-005', 'PRG', 'Guion de preguntas del Debate Ejecutivo', 'Guion aprobado por Dora Valdez (moderadora)', 'Mariel Esquivel', '2026-08-22'::date, 'Alta', 'No iniciada', 'Panelistas: Pato Bichara (Collective Academy), Consuelo Ordaz (GPTW), Rodrigo Carretero (FRISA).'),
  ('PRG-006', 'PRG', 'Guion del Panel de Empleabilidad', 'Guion aprobado por Osval Orduña (moderador)', 'Mariel Esquivel', '2026-08-22'::date, 'Alta', 'No iniciada', 'Panelistas: Yoani Aceves (Talenca), Miguel Mendoza (Viva Aerobus).'),
  ('PRG-007', 'PRG', 'Curaduría y ensayo de FuckUp Nights (6 historias de 7 min)', 'Escaleta con orden de aparición + coaching a los 6 ponentes', 'Juan Bernal', '2026-08-23'::date, 'Alta', 'No iniciada', 'Es el cierre emocional del día. Sin cronómetro se convierte en 2 horas y la gente se va.'),
  ('PRG-008', 'PRG', 'Bios, fotos y semblanzas finales de los 21 participantes', 'Carpeta con bios de 40 palabras y fotos en alta', 'Marela Islas', '2026-08-20'::date, 'Alta', 'No iniciada', 'Sirve al MC, a redes y a la agenda impresa.'),
  ('PRG-009', 'PRG', 'Guion del maestro de ceremonias con presentaciones y transiciones', 'Guion del MC v.final impreso y en teleprompter', 'Héctor León', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Incluir menciones de patrocinadores y avisos de logística.'),
  ('PRG-010', 'PRG', 'Video de apertura (bloque 9:00–9:20) editado y aprobado', 'MP4 1080p entregado a producción AV', 'Claudia Landeros', '2026-08-22'::date, 'Crítica', 'No iniciada', 'Marca el tono de HUMAN FIRST. Entregarlo a AV 4 días antes, no la misma mañana.'),
  ('PRG-011', 'PRG', 'Video de cierre y agradecimientos', 'MP4 final entregado a producción AV', 'Claudia Landeros', '2026-08-24'::date, 'Media', 'No iniciada', ''),
  ('PRG-012', 'PRG', 'Ensayo técnico con MC, moderadores y talleristas clave', 'Ensayo realizado en sede con audio y proyección reales', 'Mariel Esquivel', '2026-08-25'::date, 'Crítica', 'No iniciada', ''),
  ('PRG-013', 'PRG', 'Traslados y hospedaje de ponentes foráneos', 'Itinerarios confirmados por escrito con cada ponente', 'Mariel Esquivel', '2026-08-22'::date, 'Alta', 'No iniciada', ''),
  ('PRG-014', 'PRG', 'Reconocimiento para ponentes, moderadores y talleristas', '21 reconocimientos personalizados en sede', 'Ana María Quintanilla', '2026-08-24'::date, 'Media', 'No iniciada', 'Revisar ortografía de cada nombre: es el error clásico.'),
  ('PRG-015', 'PRG', 'Cartas de liberación de derechos de imagen y grabación', 'Formatos firmados por los 21 participantes', 'Mariel Esquivel', '2026-08-25'::date, 'Alta', 'No iniciada', 'Sin esto no se puede usar el video para promover el Summit 2027.'),
  ('TLL-001', 'TLL', 'Matriz taller ↔ sala ↔ cupo (7 talleres, 3:00–4:40)', 'Matriz publicada y comunicada a asistentes', 'Kata Molina', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Talleres: IA para HR, Violencia laboral, Diseño de comportamientos, Conversaciones cruciales, Productividad y bienestar, Valor humano frente a la IA.'),
  ('TLL-002', 'TLL', 'Materiales del taller Herramientas de IA para HR (Selene Rayas)', 'Wi-Fi reforzado, extensiones, lista de herramientas y plan sin internet', 'Kata Molina', '2026-08-24'::date, 'Alta', 'No iniciada', 'Es el único taller que depende críticamente de conectividad.'),
  ('TLL-003', 'TLL', 'Materiales del taller Violencia en Espacios Laborales (Alejandro Caro y Omar Méndez)', 'Handout legal + casos impresos', 'Alex Caro', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('TLL-004', 'TLL', 'Materiales del taller Diseño de Comportamientos (Francisco Zepeda, dmX)', 'Kit de trabajo por mesa', 'Kata Molina', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('TLL-005', 'TLL', 'Materiales del taller Conversaciones Cruciales (Adriana Ochoa)', 'Tarjetas de práctica y guías de rol', 'Kata Molina', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('TLL-006', 'TLL', 'Materiales del taller Productividad y Bienestar (Caro Cuauro)', 'Material impreso y dinámica montada', 'Kata Molina', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('TLL-007', 'TLL', 'Materiales del taller Valor Humano frente a la IA (Oscar Ramírez)', 'Material y soporte AV confirmados', 'Kata Molina', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('TLL-008', 'TLL', 'Sets de LEGO® Serious Play® para el recap de 200 personas', 'Sets contados, embolsados por participante y transportados a sede', 'Kata Molina', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Riesgo logístico #1 del cierre: una bolsa por persona y 25 mesas. Contar y embolsar toma horas, no minutos.'),
  ('TLL-009', 'TLL', 'Anfitrión por sala de taller (tiempo, micrófono, conteo)', '7 anfitriones asignados y briefeados', 'Elsa Reynoso', '2026-08-25'::date, 'Alta', 'No iniciada', 'El anfitrión avisa a los 10 min de cierre y recoge las evaluaciones.'),
  ('TLL-010', 'TLL', 'Señalización y ruteo de asistentes al bloque de talleres', 'Señalética montada + anuncio desde plenaria a las 2:50 p.m.', 'Claudia Landeros', '2026-08-25'::date, 'Alta', 'No iniciada', ''),
  ('TLL-011', 'TLL', 'Encuesta de salida por taller (Kirkpatrick nivel 1)', 'QR de evaluación impreso por sala', 'Susana González', '2026-08-24'::date, 'Media', 'No iniciada', 'Dato clave para vender los talleres del Summit 2027.'),
  ('AV-001', 'AV', 'Contrato del proveedor de audio, video e iluminación', 'Contrato firmado y cotización cerrada', 'Alex Caro', '2026-08-12'::date, 'Crítica', 'Lista', ''),
  ('AV-002', 'AV', 'Rider técnico por bloque (micrófonos, clickers, pantallas)', 'Rider del evento entregado al proveedor', 'Alex Caro', '2026-08-20'::date, 'Crítica', 'No iniciada', 'El debate y el panel necesitan 4-5 micrófonos de solapa simultáneos + 2 inalámbricos de piso.'),
  ('AV-003', 'AV', 'Audio para las 7 salas simultáneas de talleres', 'Confirmación de bocina + micrófono por sala', 'Alex Caro', '2026-08-21'::date, 'Crítica', 'No iniciada', 'Es costo que suele olvidarse hasta el día del montaje.'),
  ('AV-004', 'AV', 'Proyección: pantallas, resolución y plantilla 16:9', 'Plantilla de presentación enviada a los 21 ponentes', 'Claudia Landeros', '2026-08-20'::date, 'Alta', 'No iniciada', ''),
  ('AV-005', 'AV', 'Consolidación de todas las presentaciones en la laptop maestra', 'Carpeta única probada y respaldada en 2 USB', 'Alex Caro', '2026-08-25'::date, 'Crítica', 'No iniciada', 'Prohibido conectar laptops personales entre bloques: cada cambio cuesta 4 minutos.'),
  ('AV-006', 'AV', 'Fotografía y video profesional del evento', 'Contrato firmado + brief de tomas obligadas', 'Marela Islas', '2026-08-21'::date, 'Alta', 'No iniciada', 'Tomas obligadas: sala llena, cada speaker, patrocinadores, LEGO, cocktail.'),
  ('AV-007', 'AV', 'Plan de contenido en vivo (reels, stories, cobertura)', 'Calendario de publicaciones del día D con responsable por bloque', 'Marela Islas', '2026-08-24'::date, 'Media', 'No iniciada', ''),
  ('AV-008', 'AV', 'Música ambiental, cortinillas y playlist por bloque', 'Playlist y cortinillas entregadas a AV', 'Alex Caro', '2026-08-24'::date, 'Media', 'No iniciada', ''),
  ('AV-009', 'AV', 'Reloj de cuenta regresiva en pantalla para speakers', 'Timer configurado y probado en ensayo', 'Alex Caro', '2026-08-25'::date, 'Alta', 'No iniciada', 'Única herramienta que salva la agenda: la jornada tiene solo 10 min de colchón entre bloques.'),
  ('AV-010', 'AV', 'Wi-Fi: ancho de banda, red dedicada de AV y red de invitados', 'Prueba de velocidad documentada + credenciales impresas', 'Alex Caro', '2026-08-25'::date, 'Crítica', 'No iniciada', ''),
  ('AV-011', 'AV', 'Prueba general de audio, video y proyección en sede', 'Acta de prueba técnica firmada', 'Alex Caro', '2026-08-25'::date, 'Crítica', 'No iniciada', ''),
  ('AV-012', 'AV', 'Plan de respaldo AV (bocina, proyector y laptop redundantes)', 'Equipo de respaldo en sitio y probado', 'Alex Caro', '2026-08-25'::date, 'Alta', 'No iniciada', ''),
  ('PAT-001', 'PAT', 'Cierre de convenios con los 13 patrocinadores y aliados', 'Convenios firmados con entregables documentados por marca', 'Juan Bernal', '2026-08-15'::date, 'Crítica', 'Lista', 'DHR Global, Eyenovation, Empresa Contigo, Finsus, Fitzer, Fuckup Nights, GPTW México, InterContinental Presidente, Humand, Kali Coffee, MyMottion, Vinos RGMX, Yuhu.'),
  ('PAT-002', 'PAT', 'Matriz de entregables por patrocinador (logo, stand, menciones, inserto, leads)', 'Matriz validada marca por marca', 'Juan Bernal', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Es el documento que evita reclamos post-evento. Uno por marca, firmado.'),
  ('PAT-003', 'PAT', 'Recepción de logotipos vectoriales y artes de activación', 'Carpeta de logos en alta resolución completa (13/13)', 'Claudia Landeros', '2026-08-20'::date, 'Alta', 'No iniciada', 'Bloquea backdrop, señalética, pantalla y agenda impresa.'),
  ('PAT-004', 'PAT', 'Asignación de espacios de activación y stands en foyer', 'Plano de stands + horario de montaje por marca', 'Sergio Morales', '2026-08-21'::date, 'Alta', 'No iniciada', ''),
  ('PAT-005', 'PAT', 'Guion de menciones de patrocinadores desde el escenario', 'Menciones integradas al guion del MC con hora exacta', 'Héctor León', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('PAT-006', 'PAT', 'Coordinación con Fuckup Nights (licencia de marca y formato)', 'Confirmación de uso de marca + kit de la franquicia', 'Juan Bernal', '2026-08-21'::date, 'Crítica', 'No iniciada', 'La marca tiene reglas de formato: confirmarlas antes de promocionarlo más.'),
  ('PAT-007', 'PAT', 'Coordinación con Great Place to Work para el retrato profesional', 'Fotógrafo, set, iluminación y horarios confirmados', 'Juan Bernal', '2026-08-22'::date, 'Alta', 'No iniciada', 'Beneficio prometido a las primeras 100 personas: es promesa pública.'),
  ('PAT-008', 'PAT', 'Cortesías y accesos de patrocinadores', 'Lista de cortesías cargada en el sistema de registro', 'Elsie', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('PAT-009', 'PAT', 'Cierre de facturación y cobranza de patrocinios', 'Estado de cuenta de patrocinios cobrado al 100%', 'Juan Bernal', '2026-08-25'::date, 'Alta', 'No iniciada', 'Cobrar antes del evento, no después. Después baja la urgencia.'),
  ('PAT-010', 'PAT', 'Reconocimiento en sitio a patrocinadores', 'Placas o menciones listas y entregadas', 'Ana María Quintanilla', '2026-08-25'::date, 'Media', 'No iniciada', ''),
  ('MKT-001', 'MKT', 'Campaña de urgencia: la preventa cierra el 20 de agosto', '6 piezas publicadas + secuencia de WhatsApp al comité', 'Marela Islas', '2026-08-19'::date, 'Crítica', 'En curso', 'Palanca de conversión más fuerte de la semana. Quedan menos de 48 horas de tarifa $3,300.'),
  ('MKT-002', 'MKT', 'Publicación del programa completo y menú de talleres', 'Carrusel de agenda publicado en LinkedIn e Instagram', 'Marela Islas', '2026-08-20'::date, 'Alta', 'No iniciada', 'La agenda final ya existe: es el mejor argumento de venta que no se ha usado.'),
  ('MKT-003', 'MKT', 'Campaña de speakers: una pieza por ponente', '21 piezas diseñadas y programadas', 'Claudia Landeros', '2026-08-21'::date, 'Alta', 'No iniciada', 'Etiquetar a cada ponente para que amplifiquen: 21 redes multiplicando el alcance orgánico.'),
  ('MKT-004', 'MKT', 'Cápsula de podcast promocional del Summit', 'Episodio publicado y distribuido', 'Héctor León', '2026-08-21'::date, 'Media', 'No iniciada', '+200 episodios de audiencia: es el activo orgánico más grande de la marca.'),
  ('MKT-005', 'MKT', 'Boletín de prensa y convocatoria a medios', 'Boletín enviado + 3 medios confirmados', 'Cecilia Ochoa', '2026-08-21'::date, 'Media', 'No iniciada', 'Factor Capital Humano, El Financiero MTY, medios de negocios de NL.'),
  ('MKT-006', 'MKT', 'Correo ''todo lo que necesitas saber'' a inscritos', 'Correo enviado al 100% de inscritos (logística, acceso, dress code, agenda, talleres)', 'Elsie', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Reduce llamadas el día del evento y sube la tasa de asistencia real.'),
  ('MKT-007', 'MKT', 'Recordatorio final T-1 con instrucciones de llegada', 'WhatsApp + correo enviados la tarde del 25', 'Elsie', '2026-08-25'::date, 'Crítica', 'No iniciada', ''),
  ('MKT-008', 'MKT', 'Difusión institucional con ERIAC, AMEDIRH, COPARMEX, CAINTRA, Tec y UDEM', 'Confirmación de envío en cada canal', 'Cecilia Ochoa', '2026-08-20'::date, 'Alta', 'No iniciada', 'ERIAC es la asociación de capital humano #1 de NL: es el canal de mayor conversión disponible.'),
  ('MKT-009', 'MKT', 'Kit de difusión para comité y patrocinadores', 'Carpeta compartida con artes, textos y links', 'Claudia Landeros', '2026-08-20'::date, 'Alta', 'No iniciada', 'Que nadie tenga que inventar el texto: eso es lo que frena al comité.'),
  ('MKT-010', 'MKT', 'Hashtag oficial, marco de foto y muro social', '#HumanFirst2026 activado con marco descargable', 'Marela Islas', '2026-08-22'::date, 'Media', 'No iniciada', ''),
  ('VTA-001', 'VTA', 'Activar a los 15 miembros del comité que están en cero contactos', 'Reporte diario de contactos trabajados por miembro', 'Héctor León', '2026-08-19'::date, 'Crítica', 'En curso', 'Al 18 ago: 7 ventas de meta 200 y ~415 contactos sin trabajar. Es la brecha crítica del proyecto.'),
  ('VTA-002', 'VTA', 'Trabajar los lotes de contactos pendientes con nombre (215)', '100% de los lotes 1 a 4 contactados con el guion de 4 mensajes', 'Elias Celis', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Respetar el ritmo anti-ban: 40-50 nuevos por día, bloques de 15 con pausa.'),
  ('VTA-003', 'VTA', 'Cierre corporativo: propuestas de mesa o paquete a empresas ancla', '10 propuestas corporativas enviadas y seguidas', 'Juan Bernal', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Una venta corporativa de 10 boletos vale lo que 10 ventas individuales. Es la palanca de mayor apalancamiento a 7 días.'),
  ('VTA-004', 'VTA', 'Cierre de preventa y cambio a tarifa regular en el micrositio', 'Precio actualizado a $3,900 en WeChamber el 21 ago a las 00:01', 'Elsie', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Si no se sube el precio, se pierde la palanca de urgencia y la credibilidad de la escalera.'),
  ('VTA-005', 'VTA', 'Conciliación diaria de boletos vendidos vs. pagados', 'Reporte de corte diario compartido con el comité', 'Elsie', '2026-08-25'::date, 'Crítica', 'No iniciada', 'El número de garantía de banquete depende de este corte.'),
  ('VTA-006', 'VTA', 'Política de walk-ins y cobro en sitio', 'Procedimiento escrito + terminal bancaria probada', 'Elsie', '2026-08-25'::date, 'Alta', 'No iniciada', 'Siempre llega gente sin boleto: hay que poder cobrarles en 90 segundos.'),
  ('VTA-007', 'VTA', 'Lista final de asistentes segmentada por perfil', 'Base final con segmento (CEO, CHRO, patrocinador, prensa) para networking', 'Elsie', '2026-08-25'::date, 'Alta', 'No iniciada', 'Alimenta gafetes, mesas temáticas y reporte a patrocinadores.'),
  ('FIN-001', 'FIN', 'Presupuesto maestro actualizado: comprometido vs. ejercido vs. proyectado', 'Presupuesto v.final con punto de equilibrio en número de boletos', 'Héctor León', '2026-08-20'::date, 'Crítica', 'No iniciada', 'Con la venta actual hay que conocer el punto de equilibrio exacto antes de garantizar banquete.'),
  ('FIN-002', 'FIN', 'Anticipos y pagos a sede, banquete, AV y proveedores', 'Comprobantes de pago al 100% de los anticipos comprometidos', 'Héctor León', '2026-08-24'::date, 'Crítica', 'No iniciada', 'Un proveedor sin anticipo no monta.'),
  ('FIN-003', 'FIN', 'Caja chica y fondo de contingencia del día D', 'Efectivo asignado con responsable y formato de comprobación', 'Héctor León', '2026-08-25'::date, 'Alta', 'No iniciada', ''),
  ('FIN-004', 'FIN', 'Facturación a asistentes y patrocinadores', 'CFDI emitidos y enviados', 'Héctor León', '2026-08-25'::date, 'Media', 'No iniciada', ''),
  ('FIN-005', 'FIN', 'Liquidación con proveedores post-evento', 'Pagos finales cerrados y conciliados', 'Héctor León', '2026-08-31'::date, 'Media', 'No iniciada', ''),
  ('RSK-001', 'RSK', 'Póliza de responsabilidad civil del evento', 'Póliza vigente para el 26 de agosto', 'Sergio Morales', '2026-08-21'::date, 'Alta', 'No iniciada', 'Varias sedes la exigen como condición de acceso.'),
  ('RSK-002', 'RSK', 'Servicio médico / paramédico en sitio y botiquín', 'Proveedor confirmado de 7:00 a.m. a 8:00 p.m.', 'Sergio Morales', '2026-08-24'::date, 'Alta', 'No iniciada', '200 personas 12 horas: la probabilidad de un incidente no es cero.'),
  ('RSK-003', 'RSK', 'Plan de evacuación, rutas y brigada con la sede', 'Plan documentado + brigadistas identificados con chaleco', 'Sergio Morales', '2026-08-24'::date, 'Alta', 'No iniciada', ''),
  ('RSK-004', 'RSK', 'Plan B por ausencia de speaker', 'Matriz de suplencias y relleno de agenda por bloque', 'Mariel Esquivel', '2026-08-24'::date, 'Alta', 'No iniciada', 'Con 21 participantes, la probabilidad de una baja de último minuto es alta.'),
  ('RSK-005', 'RSK', 'Plan B por falla eléctrica o de internet', 'Planta de respaldo o hotspot 5G confirmado y probado', 'Alex Caro', '2026-08-25'::date, 'Alta', 'No iniciada', ''),
  ('RSK-006', 'RSK', 'Escenario de baja asistencia vs. garantía de banquete', 'Documento de escenarios con impacto financiero y fecha límite de ajuste', 'Carolina Paredes', '2026-08-22'::date, 'Alta', 'No iniciada', 'Definir hoy hasta qué número se puede bajar la garantía y hasta cuándo.'),
  ('RSK-007', 'RSK', 'Protocolo de manejo de crisis y vocería', 'Vocero designado + mensajes clave por escenario', 'Héctor León', '2026-08-24'::date, 'Media', 'No iniciada', ''),
  ('POST-001', 'POST', 'Encuesta de satisfacción y NPS del Summit', 'QR en sala + correo automático programado a las 6:30 p.m.', 'Susana González', '2026-08-25'::date, 'Alta', 'No iniciada', 'Se responde el mismo día o no se responde. Dejarla lista antes del evento.'),
  ('POST-002', 'POST', 'Agradecimiento a asistentes con memorias y fotos', 'Correo enviado con galería y materiales', 'Susana González', '2026-08-28'::date, 'Alta', 'No iniciada', ''),
  ('POST-003', 'POST', 'Reporte de resultados a patrocinadores', 'Reporte por marca con alcance, leads, fotos y menciones', 'Juan Bernal', '2026-08-31'::date, 'Alta', 'No iniciada', 'Es lo que renueva el patrocinio 2027 sin volver a vender.'),
  ('POST-004', 'POST', 'Memoria audiovisual: video resumen y galería', 'Video de 90 s + galería publicada', 'Marela Islas', '2026-08-31'::date, 'Media', 'No iniciada', 'Es el principal activo de venta de la preventa 2027.'),
  ('POST-005', 'POST', 'Cierre financiero y P&L del evento', 'P&L final con margen real por línea', 'Héctor León', '2026-08-31'::date, 'Alta', 'No iniciada', ''),
  ('POST-006', 'POST', 'Retrospectiva del comité: qué funcionó y qué no', 'Minuta de lecciones aprendidas para el Summit 2027', 'Héctor León', '2026-08-31'::date, 'Alta', 'No iniciada', 'Hacerla dentro de los 5 días: después se olvida el detalle.'),
  ('POST-007', 'POST', 'Nurturing de base de datos y arranque de preventa 2027', 'Secuencia de correos activada + preventa 2027 abierta', 'Elsie', '2026-08-31'::date, 'Media', 'No iniciada', 'El mejor momento para vender 2027 es la semana posterior al evento.'),
  ('PMO-011', 'PMO', 'Líder designado por cada uno de los 13 tracks', 'Matriz track → líder con nombre y correo, comunicada al comité', 'Héctor León', '2026-08-12'::date, 'Crítica', 'No iniciada', 'VERIFICAR. Sin dueño por track no hay rendición de cuentas; el PMO termina ejecutando todo.'),
  ('FIN-006', 'FIN', 'Punto de equilibrio del evento calculado y comunicado', 'Número exacto de boletos para cubrir costos fijos + variables', 'Héctor León', '2026-08-12'::date, 'Crítica', 'No iniciada', 'VERIFICAR. Sin este número no se puede decidir la garantía de banquete ni cuándo detener el gasto.'),
  ('VTA-008', 'VTA', 'Alcanzar el 70% de la meta de boletos a T-7 (140 de 200)', '140 boletos vendidos y pagados', 'Héctor León', '2026-08-12'::date, 'Crítica', 'Bloqueada', 'Al 18 ago van 7 boletos de 200. Brecha de 133. Es el riesgo mayor del proyecto: condiciona banquete, mobiliario, punto de equilibrio y percepción de sala llena.'),
  ('AYB-011', 'AYB', 'Contrato de banquete firmado con menús y política de garantía', 'Contrato firmado con fecha límite de ajuste de garantía por escrito', 'Carolina Paredes', '2026-08-12'::date, 'Crítica', 'No iniciada', 'VERIFICAR con la sede. Es el compromiso económico más grande después del salón.'),
  ('PAT-011', 'PAT', 'Cobro de anticipos de patrocinio (50%)', 'Estado de cuenta con anticipos cobrados marca por marca', 'Juan Bernal', '2026-08-14'::date, 'Alta', 'No iniciada', 'VERIFICAR. Son 13 marcas: el flujo de patrocinio financia el montaje.'),
  ('REG-014', 'REG', 'Formulario de registro que capture puesto, empresa y restricciones alimenticias', 'Formulario actualizado en WeChamber + reenvío a los ya inscritos', 'Elsie', '2026-08-10'::date, 'Alta', 'No iniciada', 'VERIFICAR. Sin esos campos no se pueden imprimir gafetes útiles ni pedir menús especiales.'),
  ('MKT-011', 'MKT', 'Calendario editorial de agosto publicado y en ejecución', 'Calendario con piezas publicadas vs. planeadas', 'Marela Islas', '2026-08-05'::date, 'Alta', 'No iniciada', 'VERIFICAR. El presupuesto de medios es 100% orgánico: el alcance depende del ritmo de publicación, no del dinero.'),
  ('AV-013', 'AV', 'Levantamiento técnico en sitio con el proveedor de AV', 'Reporte de levantamiento con puntos de energía, alturas y colgado', 'Alex Caro', '2026-08-14'::date, 'Alta', 'No iniciada', 'VERIFICAR. Sin levantamiento el rider se arma a ciegas y aparecen costos el día del montaje.')
on conflict (codigo) do update set
  track        = excluded.track,
  actividad    = excluded.actividad,
  entregable   = excluded.entregable,
  fecha_limite = excluded.fecha_limite,
  criticidad   = excluded.criticidad,
  notas        = excluded.notas;
-- Nota: el ON CONFLICT NO sobrescribe 'estado' ni 'responsable' para no
-- pisar el avance que el comité ya haya capturado si vuelves a correr el script.

-- ─── 9. VERIFICACIÓN ────────────────────────────────────────────
select * from public.summit_ops_v_dashboard;
