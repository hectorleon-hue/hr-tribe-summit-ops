# P&L en Vivo — 3er HR Tribe Summit 2026

Tablero financiero del Summit, conectado a Supabase. Vive junto al
[Centro de Control operativo](https://hectorleon-hue.github.io/hr-tribe-summit-ops/)
en este mismo repo.

**En vivo:** https://hectorleon-hue.github.io/hr-tribe-summit-ops/pnl.html

| Archivo | Qué es |
|---|---|
| `pnl.html` | La app completa en un solo archivo. Funciona sin conexión; Supabase solo la sincroniza. |
| `schema_pnl.sql` | Tablas, vistas y función de snapshot. Se ejecuta una vez en el SQL Editor. |

---

## Puesta en marcha (5 minutos)

**1. Crear el esquema.** Supabase → *SQL Editor* → *New query* → pega `schema_pnl.sql` completo → **Run**.
Es idempotente: puedes volver a correrlo sin perder los supuestos ni los cortes guardados.

**2. Copiar las credenciales.** Supabase → *Project Settings* → *API*:
la **Project URL** y la **anon public** key.

**3. Conectar.** Abre `pnl.html`, botón **⚙ Conexión**, pega ambas y dale *Conectar*.
Quedan guardadas en ese navegador; la próxima vez entra solo.

> Van en el **mismo proyecto Supabase** que `summit_ops_`. El prefijo `summit_pnl_`
> evita cualquier choque entre los dos tableros.

---

## Cómo se usa

- **Edita cualquier campo amarillo** y todo recalcula al instante: KPIs, los cuatro escenarios,
  el punto de equilibrio y la gráfica. Con Supabase conectado se guarda solo (~0.7 s después
  de dejar de teclear) y el resto del comité lo ve en tiempo real.
- **⛳ Congelar corte de hoy** guarda una foto del P&L en `summit_pnl_snapshots`.
  Hazlo cada semana: la sección *Evolución corte a corte* dibuja la tendencia.
  Repetirlo el mismo día sobrescribe el corte, no lo duplica.
- **↺ Restaurar valores originales** vuelve a los supuestos del corte del 20 de agosto.

---

## Modelo de datos

**`summit_pnl_supuestos`** — una fila (`id = 'base'`) con los 17 supuestos editables.
Un trigger sella `actualizado_en` en cada cambio.

**`summit_pnl_snapshots`** — histórico. Único por `(corte, escenario)`; guarda además los
supuestos completos en `jsonb`, así que cada corte es auditable.

**Vistas** (el cálculo vive en la base, no solo en el navegador):

| Vista | Devuelve |
|---|---|
| `summit_pnl_v_unitario` | Economía unitaria: margen de contribución, costo variable por persona, costo fijo total |
| `summit_pnl_v_escenarios` | P&L completo para Hoy / 150 / 180 / 200 personas |
| `summit_pnl_v_breakeven` | Punto de equilibrio con y sin patrocinios, colchón de costo fijo |
| `summit_pnl_v_tendencia` | Cortes con delta contra el anterior |

`select summit_pnl_snapshot('nota')` congela el corte del día desde SQL.

**RLS** abierta a `anon`, igual que `summit_ops_`, porque la página es estática y se comparte
con el comité. Para cerrarla: cambia `anon` por `authenticated` en las cuatro políticas del
script y activa Magic Link en Supabase Auth.

---

## Supuestos del modelo (corte 20 ago 2026)

Base: **flujo con IVA**, no base fiscal.

| Concepto | Valor | Origen |
|---|---|---|
| Boletos pagados | 57 | 62 registros − 5 cortesías |
| Ingreso bruto cobrado | $191,235 | Hoja *Ventas de Evento*, 44 transacciones |
| Comisión efectiva | 6.16% | $11,780.54 ÷ $191,235 (Stripe + MSI + IVA) |
| Precio del boleto incremental | $2,805 | $3,300 con cupón 15% |
| Patrocinios en efectivo | $131,320 | Humand, Yuhu, Eyenovation, FINSUS |
| Venue + A&B por persona | $1,622.77 | $324,554 ÷ 200 pax, con IVA y 13% de servicio |
| Propina | 10% sobre A&B | Hoja *Gastos* |
| Costos fijos | $44,918 | Kit $35,000 + gafetes $638 + WeChamber $9,280 |

**Economía unitaria:** margen de contribución de **$847 por boleto extra**
(neto $2,632 − costo variable $1,785).

| Escenario | Ingreso | Costo | Utilidad | Margen |
|---|---|---|---|---|
| Hoy (62) | $310,775 | $155,591 | $155,184 | 49.9% |
| 150 pax | $542,410 | $312,675 | $229,735 | 42.4% |
| 180 pax | $621,376 | $366,226 | $255,149 | 41.1% |
| 200 pax | $674,020 | $401,927 | $272,093 | 40.4% |

Break-even con patrocinios: **ya superado**. Solo taquilla: **34 asistentes**, también superado.

---

## Tres advertencias que hay que leer antes de presentar esto

**1. La hoja `Gastos` está incompleta.** Solo trae cuatro líneas. No incluye audio/video
(~$33,500, cotización Mix Eventos), marketing e impresos, honorarios de speakers, fotógrafo
ni staff. Mientras no se carguen en *Otros costos FIJOS*, el punto de equilibrio está
subestimado. Prueba de estrés: con $120,000 de costos faltantes, el equilibrio solo con
taquilla salta de 34 a **176 asistentes** y el margen a 200 personas cae de 40% a 23%.

**2. El conteo de boletos no cuadra.** Los 62 registros incluyen 5 cortesías (57 pagados),
pero el desglose de montos de la hoja de ventas suma exactamente 62 boletos pagados
($2,805 = 1, $5,610 = 2, $8,415 = 3, $13,200 = 4). Reconciliar con WeChamber.

**3. Falta el IVA de tres patrocinios.** Yuhu, Eyenovation y FINSUS están cotizados
"más IVA": ~$16,000 de flujo adicional que el modelo no cuenta.

Los patrocinios en especie (Kali, My MOTTION, Great Place to Work, Cerveza Rrey, Pfitzer y
el intercambio del Hotel Presidente) **no** entran como ingreso: se tratan como costo evitado.

---

*Grow2GetherMx · PMO Héctor León · Desaprende y transfórmate*
