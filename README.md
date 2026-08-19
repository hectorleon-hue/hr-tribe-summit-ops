# Centro de Control — 3er HR Tribe Summit 2026 · HUMAN FIRST

Tablero operativo del Summit del **26 de agosto de 2026**, Club Casino Monterrey.
137 actividades en 13 tracks, con responsable, entregable, fecha límite y semáforo de criticidad.

## Contenido

| Archivo | Qué es |
|---|---|
| `index.html` | La aplicación completa (un solo archivo, sin build). Dashboard, plan maestro editable, foco a 7 días y run of show del día del evento. |
| `schema.sql` | Esquema de Supabase: tablas, trigger de `updated_at`, bitácora de cambios, vistas de dashboard, RLS, realtime y la carga inicial de las 137 actividades. |

## Puesta en marcha

1. **Supabase** — abre el *SQL Editor* de tu proyecto, pega `schema.sql` completo y ejecútalo. Es idempotente: puedes volver a correrlo sin duplicar filas y sin pisar el avance que el comité ya haya capturado.
2. **Credenciales** — en `index.html`, dentro del bloque `<script type="module">`, llena:

   ```js
   let SUPABASE_URL      = 'https://TU-PROYECTO.supabase.co';
   let SUPABASE_ANON_KEY = 'eyJhbGciOi...';
   ```

   También puedes pegarlas en caliente desde la pestaña **Conexión & SQL** (no quedan guardadas).
3. **GitHub Pages** — Settings → Pages → Branch `main` / carpeta `/ (root)`. La URL queda publicada en un par de minutos.

## Cómo se actualiza solo

- **Realtime.** La app se suscribe a los cambios de `summit_ops_actividades`; si alguien del comité cambia un estado, todas las pantallas abiertas se refrescan sin recargar.
- **Respaldo por polling.** Relee la tabla cada 60 segundos por si la conexión realtime se cae.
- **Edición en línea.** Estado, responsable, fecha, criticidad y notas se guardan al momento.
- **Alta de actividades.** El botón *+ Agregar actividad* genera el código correlativo del track y lo inserta en Supabase.
- **Modo local.** Sin credenciales el tablero corre con los datos precargados: sirve para revisar, no para trabajar en equipo.

## Modelo de datos

`summit_ops_actividades` — `codigo` (único, p. ej. `PRG-004`), `track`, `actividad`, `entregable`, `responsable`, `fecha_limite`, `criticidad` (Crítica/Alta/Media), `estado` (No iniciada/En curso/Bloqueada/Lista), `notas`, `evidencia_url`.

Vistas listas para consultar: `summit_ops_v_actividades`, `summit_ops_v_dashboard`, `summit_ops_v_carga_responsable`.

## Seguridad

Las políticas RLS permiten lectura y escritura al rol `anon` porque el tablero es una página estática compartida con el comité. Si más adelante quieres cerrar la escritura, cambia `anon` por `authenticated` en las políticas de insert/update/delete de `schema.sql` y agrega login de Supabase.

---

HR TRIBE A.C. · Convivir • Aprender • Trascender
