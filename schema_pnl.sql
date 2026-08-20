-- =====================================================================
--  P&L 3er HR TRIBE SUMMIT 2026  ·  Esquema Supabase
--  Grow2GetherMx · PMO Héctor León
--  Prefijo: summit_pnl_   (convive con summit_ops_ en el mismo proyecto)
--
--  Ejecutar completo en: Supabase → SQL Editor → New query → Run
--  Es idempotente: se puede re-ejecutar sin perder los supuestos guardados.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. SUPUESTOS  (una fila por configuración; 'base' es la activa)
-- ---------------------------------------------------------------------
create table if not exists summit_pnl_supuestos (
  id                  text primary key,
  nombre              text        not null default 'Escenario base',

  -- Ingresos · boletos
  boletos_pagados     integer     not null default 57,
  cortesias           integer     not null default 5,
  ingreso_bruto       numeric(14,2) not null default 191235,
  comision_pct        numeric(6,4)  not null default 0.0616,
  precio_incremental  numeric(14,2) not null default 2805,

  -- Ingresos · patrocinios en efectivo
  patro_humand        numeric(14,2) not null default 31320,
  patro_yuhu          numeric(14,2) not null default 15000,
  patro_eyenovation   numeric(14,2) not null default 35000,
  patro_finsus        numeric(14,2) not null default 50000,
  patro_otros         numeric(14,2) not null default 0,

  -- Costos variables (por persona)
  costo_ayb_pp        numeric(14,2) not null default 1622.77,
  propina_pct         numeric(6,4)  not null default 0.10,
  costo_var_otros_pp  numeric(14,2) not null default 0,

  -- Costos fijos
  costo_kit           numeric(14,2) not null default 35000,
  costo_gafetes       numeric(14,2) not null default 638,
  costo_plataforma    numeric(14,2) not null default 9280,
  costo_fijo_otros    numeric(14,2) not null default 0,

  -- Referencia
  meta_ingreso        numeric(14,2) not null default 709920,

  actualizado_en      timestamptz not null default now(),
  actualizado_por     text        not null default 'PMO',

  constraint summit_pnl_chk_comision check (comision_pct >= 0 and comision_pct < 1),
  constraint summit_pnl_chk_propina  check (propina_pct  >= 0 and propina_pct  < 1),
  constraint summit_pnl_chk_boletos  check (boletos_pagados >= 0 and cortesias >= 0)
);

comment on table  summit_pnl_supuestos is 'Supuestos editables del P&L del Summit 2026. La fila id=''base'' es la que lee el tablero.';
comment on column summit_pnl_supuestos.cortesias is 'Generan costo de A&B pero no ingreso.';
comment on column summit_pnl_supuestos.costo_fijo_otros is 'ATENCION: cargar aqui audio/video (~33500), marketing, speakers, fotografo y staff. La hoja Gastos original NO los incluye.';
comment on column summit_pnl_supuestos.comision_pct is 'Comision efectiva de cobro: Stripe + MSI + IVA sobre comision. 11780.54 / 191235 = 6.16%.';

-- seed (no pisa valores existentes al re-ejecutar)
insert into summit_pnl_supuestos (id, nombre) values ('base', 'Escenario base · corte 20 ago 2026')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. SNAPSHOTS  (histórico de cortes para ver la evolución)
-- ---------------------------------------------------------------------
create table if not exists summit_pnl_snapshots (
  id                bigint generated always as identity primary key,
  corte             date        not null default current_date,
  escenario         text        not null,
  asistentes        integer     not null,
  boletos_pagados   integer,
  cortesias         integer,
  ingreso_total     numeric(14,2),
  costo_total       numeric(14,2),
  utilidad          numeric(14,2),
  margen            numeric(6,4),
  breakeven_patro   integer,
  breakeven_taquilla integer,
  supuestos         jsonb,
  nota              text,
  creado_en         timestamptz not null default now()
);

create unique index if not exists summit_pnl_snapshots_uk
  on summit_pnl_snapshots (corte, escenario);

create index if not exists summit_pnl_snapshots_corte_idx
  on summit_pnl_snapshots (corte desc);

comment on table summit_pnl_snapshots is 'Un corte por dia y escenario. Permite graficar como evoluciona la utilidad rumbo al 26 ago.';

-- ---------------------------------------------------------------------
-- 3. VISTA: métricas derivadas de la economía unitaria
-- ---------------------------------------------------------------------
create or replace view summit_pnl_v_unitario as
select
  s.id,
  s.nombre,
  s.boletos_pagados + s.cortesias                                    as asistentes_hoy,
  s.ingreso_bruto * (1 - s.comision_pct)                             as ingreso_neto_realizado,
  s.precio_incremental * (1 - s.comision_pct)                        as neto_por_boleto,
  s.costo_ayb_pp * (1 + s.propina_pct) + s.costo_var_otros_pp        as costo_variable_pp,
  s.costo_kit + s.costo_gafetes + s.costo_plataforma
    + s.costo_fijo_otros                                             as costo_fijo_total,
  s.patro_humand + s.patro_yuhu + s.patro_eyenovation
    + s.patro_finsus + s.patro_otros                                 as patrocinios,
  s.precio_incremental * (1 - s.comision_pct)
    - (s.costo_ayb_pp * (1 + s.propina_pct) + s.costo_var_otros_pp)  as margen_contribucion,
  s.meta_ingreso,
  s.actualizado_en
from summit_pnl_supuestos s;

comment on view summit_pnl_v_unitario is 'Economia unitaria: margen de contribucion por boleto, costo variable por persona y costo fijo total.';

-- ---------------------------------------------------------------------
-- 4. VISTA: P&L completo por escenario (Hoy / 150 / 180 / 200)
-- ---------------------------------------------------------------------
create or replace view summit_pnl_v_escenarios as
with u as (
  select s.*, v.asistentes_hoy, v.ingreso_neto_realizado, v.neto_por_boleto,
         v.costo_variable_pp, v.costo_fijo_total, v.patrocinios, v.margen_contribucion
  from summit_pnl_supuestos s
  join summit_pnl_v_unitario v on v.id = s.id
),
esc as (
  select u.*, e.orden, e.escenario, e.n
  from u
  cross join lateral (
    values
      (0, 'Hoy',          u.asistentes_hoy),
      (1, '150 personas', 150),
      (2, '180 personas', 180),
      (3, '200 personas', 200)
  ) as e(orden, escenario, n)
),
calc as (
  select
    id, nombre, orden, escenario, n as asistentes,
    greatest(0, n - asistentes_hoy)                          as boletos_por_vender,
    ingreso_neto_realizado                                   as ing_realizado,
    greatest(0, n - asistentes_hoy) * neto_por_boleto        as ing_incremental,
    patrocinios                                              as ing_patrocinios,
    n * costo_ayb_pp                                         as costo_ayb,
    n * costo_ayb_pp * propina_pct                           as costo_propina,
    n * costo_var_otros_pp                                   as costo_var_otros,
    costo_fijo_total                                         as costo_fijo,
    meta_ingreso
  from esc
)
select
  id, nombre, orden, escenario, asistentes, boletos_por_vender,
  round(ing_realizado, 2)                                    as ingreso_realizado,
  round(ing_incremental, 2)                                  as ingreso_incremental,
  round(ing_patrocinios, 2)                                  as ingreso_patrocinios,
  round(ing_realizado + ing_incremental + ing_patrocinios, 2) as ingreso_total,
  round(costo_ayb, 2)                                        as costo_ayb,
  round(costo_propina, 2)                                    as costo_propina,
  round(costo_var_otros, 2)                                  as costo_variable_otros,
  round(costo_fijo, 2)                                       as costo_fijo,
  round(costo_ayb + costo_propina + costo_var_otros + costo_fijo, 2) as costo_total,
  round(ing_realizado + ing_incremental + ing_patrocinios
        - (costo_ayb + costo_propina + costo_var_otros + costo_fijo), 2) as utilidad,
  round(
    case when (ing_realizado + ing_incremental + ing_patrocinios) = 0 then 0
    else (ing_realizado + ing_incremental + ing_patrocinios
          - (costo_ayb + costo_propina + costo_var_otros + costo_fijo))
         / (ing_realizado + ing_incremental + ing_patrocinios) end, 4)   as margen,
  round(
    case when asistentes = 0 then 0
    else (ing_realizado + ing_incremental + ing_patrocinios
          - (costo_ayb + costo_propina + costo_var_otros + costo_fijo))
         / asistentes end, 2)                                            as utilidad_por_asistente,
  round(meta_ingreso - (ing_realizado + ing_incremental + ing_patrocinios), 2) as brecha_vs_meta
from calc
order by orden;

comment on view summit_pnl_v_escenarios is 'Estado de resultados completo para Hoy, 150, 180 y 200 personas. Es la vista que consume el tablero.';

-- ---------------------------------------------------------------------
-- 5. VISTA: punto de equilibrio
-- ---------------------------------------------------------------------
create or replace view summit_pnl_v_breakeven as
select
  v.id,
  v.margen_contribucion,
  v.asistentes_hoy,
  case when v.margen_contribucion <= 0 then null
       else greatest(0, ceil((v.costo_fijo_total + v.asistentes_hoy * v.neto_por_boleto
                              - v.ingreso_neto_realizado - v.patrocinios)
                             / v.margen_contribucion))::integer
  end as breakeven_con_patrocinios,
  case when v.margen_contribucion <= 0 then null
       else greatest(0, ceil((v.costo_fijo_total + v.asistentes_hoy * v.neto_por_boleto
                              - v.ingreso_neto_realizado)
                             / v.margen_contribucion))::integer
  end as breakeven_solo_taquilla,
  (select round(e.utilidad + v.costo_fijo_total, 2)
     from summit_pnl_v_escenarios e
    where e.id = v.id and e.escenario = '150 personas') as costo_fijo_max_absorbible_150,
  (select e.utilidad from summit_pnl_v_escenarios e
    where e.id = v.id and e.escenario = 'Hoy')          as utilidad_hoy
from summit_pnl_v_unitario v;

comment on view summit_pnl_v_breakeven is 'Asistentes necesarios para utilidad cero, con y sin patrocinios, y colchon de costo fijo.';

-- ---------------------------------------------------------------------
-- 6. VISTA: tendencia (último corte por escenario + delta contra el anterior)
-- ---------------------------------------------------------------------
create or replace view summit_pnl_v_tendencia as
select
  s.corte,
  s.escenario,
  s.asistentes,
  s.boletos_pagados,
  s.ingreso_total,
  s.costo_total,
  s.utilidad,
  s.margen,
  s.breakeven_patro,
  s.utilidad - lag(s.utilidad) over (partition by s.escenario order by s.corte) as delta_utilidad,
  s.asistentes - lag(s.asistentes) over (partition by s.escenario order by s.corte) as delta_asistentes,
  s.nota
from summit_pnl_snapshots s
order by s.corte desc, s.escenario;

comment on view summit_pnl_v_tendencia is 'Evolucion de la utilidad y la asistencia corte a corte.';

-- ---------------------------------------------------------------------
-- 7. FUNCIÓN: guardar el corte del día desde los supuestos vigentes
-- ---------------------------------------------------------------------
create or replace function summit_pnl_snapshot(p_nota text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_filas integer;
begin
  insert into summit_pnl_snapshots
    (corte, escenario, asistentes, boletos_pagados, cortesias,
     ingreso_total, costo_total, utilidad, margen,
     breakeven_patro, breakeven_taquilla, supuestos, nota)
  select
    current_date, e.escenario, e.asistentes, s.boletos_pagados, s.cortesias,
    e.ingreso_total, e.costo_total, e.utilidad, e.margen,
    b.breakeven_con_patrocinios, b.breakeven_solo_taquilla,
    to_jsonb(s) - 'actualizado_en', p_nota
  from summit_pnl_v_escenarios e
  join summit_pnl_supuestos    s on s.id = e.id
  join summit_pnl_v_breakeven  b on b.id = e.id
  where e.id = 'base'
  on conflict (corte, escenario) do update set
    asistentes      = excluded.asistentes,
    boletos_pagados = excluded.boletos_pagados,
    cortesias       = excluded.cortesias,
    ingreso_total   = excluded.ingreso_total,
    costo_total     = excluded.costo_total,
    utilidad        = excluded.utilidad,
    margen          = excluded.margen,
    breakeven_patro = excluded.breakeven_patro,
    breakeven_taquilla = excluded.breakeven_taquilla,
    supuestos       = excluded.supuestos,
    nota            = coalesce(excluded.nota, summit_pnl_snapshots.nota),
    creado_en       = now();

  get diagnostics v_filas = row_count;
  return v_filas;
end;
$$;

comment on function summit_pnl_snapshot(text) is 'Congela el P&L de hoy en summit_pnl_snapshots. Re-ejecutar el mismo dia sobrescribe el corte.';

-- ---------------------------------------------------------------------
-- 8. Trigger de auditoría del timestamp
-- ---------------------------------------------------------------------
create or replace function summit_pnl_touch()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

drop trigger if exists summit_pnl_supuestos_touch on summit_pnl_supuestos;
create trigger summit_pnl_supuestos_touch
  before update on summit_pnl_supuestos
  for each row execute function summit_pnl_touch();

-- ---------------------------------------------------------------------
-- 9. RLS  (misma convención que summit_ops_: abierta a anon,
--          porque el tablero es estático y se comparte con el comité)
--    Si prefieres cerrarlo, cambia 'anon' por 'authenticated' en las
--    cuatro políticas y usa Magic Link en Supabase Auth.
-- ---------------------------------------------------------------------
alter table summit_pnl_supuestos  enable row level security;
alter table summit_pnl_snapshots  enable row level security;

drop policy if exists summit_pnl_sup_read  on summit_pnl_supuestos;
drop policy if exists summit_pnl_sup_write on summit_pnl_supuestos;
drop policy if exists summit_pnl_snap_read on summit_pnl_snapshots;
drop policy if exists summit_pnl_snap_write on summit_pnl_snapshots;

create policy summit_pnl_sup_read   on summit_pnl_supuestos for select using (true);
create policy summit_pnl_sup_write  on summit_pnl_supuestos for update using (true) with check (true);
create policy summit_pnl_snap_read  on summit_pnl_snapshots for select using (true);
create policy summit_pnl_snap_write on summit_pnl_snapshots for insert with check (true);

-- Realtime: el tablero se actualiza solo cuando otro miembro del comité edita
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table summit_pnl_supuestos;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 10. Comprobación rápida (debe devolver las cifras del tablero)
-- ---------------------------------------------------------------------
-- select escenario, asistentes, ingreso_total, costo_total, utilidad, margen
--   from summit_pnl_v_escenarios where id = 'base';
-- select * from summit_pnl_v_breakeven where id = 'base';
-- select summit_pnl_snapshot('corte inicial');
