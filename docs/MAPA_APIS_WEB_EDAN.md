# Mapa de APIs EDAN para el equipo Web

**Roles:** RESP (rol **7**) y UGR (rol **6**)
**Última actualización:** 2026-10-19
**Fuente de verdad del contrato:** `https://api.climbat.net/openapi.v2.json` (OpenAPI v2)
**Verificado contra:** código Flutter de la app (`lib/services/...`) y respuestas reales del servidor.

> Este documento responde una sola pregunta: **qué pantalla llama a qué API, para qué, y cómo**.
> No es el contrato completo del servidor (para eso está `PLAN_APIS_V2_EDAN.md`).
> Solo se documentan las APIs que la app **usa realmente** hoy.

---

## 1. Convenciones globales

| Tema | Regla |
|---|---|
| Base URL | `https://api.climbat.net/api/v2` |
| Auth | `POST /auth/login` → `data.access_token`. Luego `Authorization: Bearer <token>` en **todas** las llamadas. |
| Envelope OK | `{ "success": true, "message": "…", "data": …, "total": … }`. Las listas vienen en `data` (a veces `data.items`). |
| Envelope error | `{ "detail": "…" }` (o `{ "detail": [ … ] }` en 422). **No** trae `success`. Ver §10. |
| Barra final | Las colecciones **`/edan/`** y **`/usuarios/`** exigen barra final. Sin ella el servidor responde `307` y el cliente **pierde el header `Authorization` → 401**. `/edan/formularios`, `/edan/sync/pull`, etc. **sí** funcionan sin barra. |
| Roles | **6 = UGR** (municipio), **7 = RESP** (reporte local). El registro público fuerza `id_rol = 7`. El login devuelve `id_rol` y `municipio` para armar el contexto. |
| Fechas | ISO-8601 (`2026-10-19T14:30:00`). El servidor fija `fecha_modificacion`. |
| Concurrencia | **LWW (last-write-wins): no existe `version`**. Gana la última escritura; `fecha_modificacion` la pone el servidor. |
| Idempotencia | `Idempotency-Key: <uuid>` opcional en `POST`/`PUT`. Recomendado en `/edan/formularios/completo`. |
| Identidad | `uuid_edan_localidad` es la clave estable del documento. El `id` numérico (`id_edan_localidad`) lo asigna el servidor en la **primera** creación. |
| Paginación | `skip` + `limit` (+ `todos=true` para "todo", solo donde el endpoint lo permite). Ver §7. |
| Borrado | Lógico por defecto (`DELETE`). El documento se borra en cascada (secciones, viviendas, fotos). |
| Offline-first | La app **lee de SQLite**; la red se usa para login, catálogos, sync, envío, fotos y refresco de un documento. |

### Regla de oro de identidad

- **Crear** (`POST`): se envía el `uuid` que generó el cliente. El servidor responde con el `id` numérico → se guarda como `id_server`.
- **Editar** (`PUT`): se usa ese `uuid` en la ruta. **Nunca** se crea un documento nuevo para editar.
- En `GET` por path, el servidor acepta **uuid o id numérico**. La app usa uuid salvo cuando solo tiene el id.
- El `uuid` se genera **una sola vez** y no se regenera: reintentar con el mismo uuid es un upsert, nunca duplica.

### 1.1. Login (forma exacta)

```http
POST /auth/login
Content-Type: application/json

{ "usuario": "ugrscz", "contrasena": "••••••" }
```

```jsonc
// 200
{ "success": true, "message": "Login exitoso",
  "data": {
    "access_token": "eyJhbGciOi…",
    "token_type": "bearer",
    "user_id": 28,
    "usuario": "UGRSCZ",
    "nombre": "…",
    "id_rol": 6,               // ← 6 UGR / 7 RESP
    "rol": "UGR Municipio",
    "id_municipio": 70101,     // ← contexto del alcance
    "municipio_nombre": "Santa Cruz de la Sierra",
    "permisos": { "EDAN": ["CREATE","READ","UPDATE","DELETE"], "…": [] }
  } }
```

Guardar `access_token` + `id_rol` + `id_municipio` + `permisos`. Sin permiso del módulo **EDAN** → `403`.

---

## 2. Rol 7 — RESP (EDAN local)

### 2.1. Resumen de pantallas

| Pantalla / acción | Qué API usa | Para qué |
|---|---|---|
| Login / registro / recuperación | `POST /auth/login`, `POST /auth/register`, `POST /auth/verificar-identidad`, `POST /auth/cambiar-contrasena` | Autenticación y token. |
| Catálogos del wizard (al abrir) | `GET /edan/tipo-evento`, `GET /edan/tipo-localidad`, `GET /edan/grupo-etario`, `GET /edan/grupo-vulnerable`, `GET /shared/cultivos`, `GET /shared/pecuario` | Poblar selects del formulario. |
| Cascada geográfica (perfil/registro) | `GET /shared/departamentos`, `GET /shared/provincias?id_departamento=`, `GET /shared/municipios?id_provincia=` | Ubicación. |
| Dashboard / lista de EDAN | **SQLite** (local). La red solo entra por el **sync de fondo**. | Sin red la pantalla funciona igual. |
| Wizard EDAN (01–13) | **Ninguna llamada por campo** | Todo se guarda en SQLite. La red aparece al **Enviar**. |
| Botón **Enviar** del wizard / de la tarjeta | `POST /edan/formularios/completo` (1.ª vez) → `PUT /edan/formularios/completo` (ediciones) | Enviar el documento completo al UGR. Ver §5. |
| Fotos (botón de foto) | `POST /upload` (multipart, **legacy**) | Subir la foto inmediatamente. |
| Fotos (carrete) | `POST /upload` (multipart) | `subirFotosCarrete`: 1 foto por request. |
| Fotos del sync (cola V2) | `POST /edan/fotografias` (multipart) | Fotos pendientes del documento ya confirmado. |
| Vista previa / detalle | `GET /edan/formularios/{uuid}/completo` | Refrescar el documento canónico (`EdanEnvioV2.descargar`). |
| Sync de fondo | `GET /edan/formularios/estados?fecha_modificacion_desde=&limit=` → `GET /edan/sync/pull` → `POST /edan/sync/ack` → push `POST/PUT /edan/formularios/completo` → `POST /edan/fotografias` | Ver §2.2. |

### 2.2. Ciclo de sincronización (orden exacto)

```
0. GET  /edan/formularios/estados?fecha_modificacion_desde=<watermark>&limit=200
      → saber qué uuid cambió (tiene_cambios) y qué hay que bajar
1. GET  /edan/sync/pull?desde=<watermark>&limit=<n>
2. aplicar el documento al SQLite local
3. POST /edan/sync/ack   { id_dispositivo, watermark }
4. push de cambios locales:
     POST /edan/formularios/completo   (documento nuevo)
     PUT  /edan/formularios/completo   (documento existente)
5. POST /edan/fotografias             (fotos pendientes)
```

Reglas del motor:

- `POST /edan/formularios/completo` es **solo creación**. Si el uuid ya existe → **409**; el cliente reintenta con `PUT`.
- `PUT /edan/formularios/completo` **no crea**: si el uuid no existe → **404**; el cliente reintenta con `POST`.
- `POST /edan/formularios/completo` **no borra** filas ausentes: los borrados van por `DELETE` de la sección/vivienda.
- Las fotos solo suben cuando su documento padre ya fue confirmado.

### 2.3. Endpoints usados por RESP (detalle)

| Método | Ruta | Notas |
|---|---|---|
| POST | `/edan/formularios/completo` | Crea cabecera + 14 secciones + viviendas en **un** request. |
| PUT | `/edan/formularios/completo` | Edita el documento completo. Mismo JSON que el POST. |
| POST | `/edan/formularios` | Crear solo cabecera (flujo por partes; poco usado). |
| PUT | `/edan/formularios/{uuid}` | Editar solo cabecera. |
| GET | `/edan/formularios/{uuid\|id}` | Solo cabecera + `secciones_resumen` (sin filas). |
| DELETE | `/edan/formularios/{uuid}` | Borrar documento en cascada. |
| GET | `/edan/formularios/{uuid}/completo` | Documento anidado: `cabecera` + 14 secciones + `fotos[]` + `viviendas[]`. |
| GET | `/edan/formularios/estados` | Listado ligero incremental (`fecha_modificacion_desde`, `limit`). |
| GET | `/edan/formularios?...` | Listado por geografía (`id_municipio`, `modo=completo`). Lo llama **UGR** en la descarga por municipio; la app RESP no lo usa. |
| POST/PUT/DELETE | `/edan/formularios/{uuid_loc}/secciones/{tipo}[/{uuid_fila}]` | Upsert/borrado por fila (cola de sync). |
| POST/PUT/DELETE | `/edan/formularios/{uuid_loc}/secciones/danos-vivienda/{uuid_dano}/viviendas[/{uuid_v}]` | Viviendas anidadas 1:N. |
| POST | `/edan/fotografias` | Multipart: `uuid_fotografia`, `tipo_entidad`, `uuid_registro`, `archivo`, `sha256?`. |
| POST | `/upload` | Multipart legacy (`id_edan_localidad`, `id_usuario`, 1 foto por request). Se usa en el botón de foto y en el carrete. |
| GET | `/edan/fotografias/{uuid}` | Metadatos (`ruta_archivo`). |
| DELETE | `/edan/fotografias/{uuid}` | Borrado lógico. |
| GET | `/edan/sync/pull?desde&limit` | Cambios desde watermark. |
| POST | `/edan/sync/ack` | `{ id_dispositivo, watermark }`. |

### 2.4. Formas de respuesta exactas (verificadas en vivo)

**`GET /edan/sync/pull`** — `data` con **7 claves** (nunca viene vacío aunque no haya cambios):

```jsonc
{ "success": true, "message": "Pull generado",
  "data": {
    "watermark": "2026-10-19T16:20:50.344212",   // usar como `desde` la próxima vez
    "formularios": [ { "id_edan_localidad": 325645, "uuid_edan_localidad": "…",
                       "grup_poblacion": true, "imp_impacto_poblacion": true,
                       "id_edan": 79, "localidad": "Zona Los Pinos", "…": "…" } ],  // PLANO, sin nodo `cabecera`
    "secciones":  [ { "tipo_seccion": "impacto_poblacion", "uuid_registro": "…",
                      "uuid_edan_localidad": "…", "id_grupo_etario": 1,
                      "fallecidos": 0, "…": "…" } ],                    // PLANO + discriminador `tipo_seccion`
    "viviendas":  [ { "uuid_registro": "…", "uuid_dano_vivienda": "…", "tipo_dano": "…" } ],
    "fotos":      [ { "uuid_fotografia": "…", "tipo_entidad": "…", "uuid_registro": "…" } ],
    "tombstones": [ { "tabla": "…", "id_registro": "…", "borrado_en": "…" } ],
    "totals":     { "formularios": 1, "secciones": 10, "viviendas": 0, "fotos": 0, "tombstones": 1 }
  } }
```

> **Ojo:** en `pull` los formularios y las secciones vienen **planos** (columnas al
> mismo nivel + `tipo_seccion`/`tipo_entidad`), **no** agrupados por `cabecera` ni
> por `llaveJson`. El agrupado lo hace el cliente.

**`GET /edan/formularios/estados`** — `data` con **`items` + `resumen` + `total`**:

```jsonc
{ "success": true, "data": {
    "items": [ { "uuid_edan_localidad": "…", "id_edan_localidad": 325643,
                 "id_edan_localidad_estado": 3, "id_edan": 79, "id_usuario": 28,
                 "pendiente_actualizacion": true, "pendiente_eliminacion": false,
                 "es_huerfana": false, "tiene_cambios": true,     // ← bool estricto (§20.15 C)
                 "fecha_modificacion": "2026-10-14T21:22:26.940118",
                 "grup_poblacion": true, "grup_salud": false, "…": "9 flags grup_*",
                 "estado_localidad": { "id_edan_localidad_estado": 3, "nombre": "Aprobado UGR", "orden": 5 } } ],
    "resumen": { "por_estado": [ { "id_edan_localidad_estado": 2, "estado": "Enviado UGR", "orden": 4, "cantidad": 1 } ],
                 "por_grupo":  [ { "grupo": "grup_poblacion", "cantidad": 2 }, "…9 grupos…" ] },
    "total": 4 } }
```

`limit=1` basta para el dashboard (solo se usa `resumen`). El listado incremental
usa `fecha_modificacion_desde=<ISO>&limit=200` y `tiene_cambios` para decidir si
re-descargar el documento.

---

## 3. Rol 6 — UGR (EDAN padre y consolidaciones)

### 3.1. Resumen de pantallas

| Pantalla / acción | Qué API usa | Para qué |
|---|---|---|
| Dashboard UGR | `GET /edan/?limit=&id_municipio=` + `GET /edan/consolidar/pendientes?id_municipio=` | Últimos EDAN consolidados y contador de pendientes. |
| Dashboard / pestañas (fondo) | `EdanSyncEngineV2.sincronizar()` = §2.2 completo | El `formularios/estados` que ve la UI viene de **dentro del sync**, no de una llamada directa de la pantalla. |
| Pestaña EDAN (padre) | `GET /edan/?order_by=id_edan&order=desc&skip&limit&id_municipio` | Listar EDAN consolidados. **La respuesta ya trae `localidades[]` completas** (no hace falta un GET por localidad). |
| Detalle EDAN padre | `GET /edan/{uuid_edan|id_edan}` (opcional `?modo=compacto`) | Cabecera + `localidades[]` + `resumen_secciones` + `reportes_rea`; `modo=compacto` añade `sumatorias` y solo secciones con datos. |
| Editar / observaciones del padre | `PUT /edan/{uuid_edan|id_edan}` | Guardar cambios del UGR (sin `version`). |
| Deshacer consolidación | `PUT /edan/{uuid_edan|id_edan}/deshacer` | Revertir el EDAN padre (aplica directo, sin preview). |
| Pestaña Localidades | `GET /edan/localidades/municipio/{id_municipio}` | Listar localidades del municipio con su estado (trae `grupos` + 14 `imp_*` + secciones con datos). |
| Tarjetas / resumen | `GET /edan/localidades/municipio/{id_municipio}/resumen` | Totales agregados (`total`, `huerfanas`, `consolidadas`, `por_estado[]`). |
| Cambiar estado de localidad | `PUT /edan/localidades/{id_localidad}/estado` | `{ id_edan_localidad_estado }`. |
| Catálogo de estados | `GET /edan/localidades-estado` | Estados disponibles (ver §10). |
| Descargar EDAN del municipio | `GET /edan/formularios?id_municipio=&todos=false&modo=completo&limit=200&skip=` | Bajar documentos completos para consolidar/ver. |
| Consolidar seleccionadas | `POST /edan/consolidar` | Ver §3.3. **Canónico:** `{ uuid_edan?, localidades:[uuid…] }`. Legacy aún aceptado: `{ id_municipio, id_tipo_evento, localidad_ids[] }` (deprecated). |
| Consolidar automático | `POST /edan/consolidar/auto?id_municipio=&id_tipo_evento=` | **Query params, no body.** La app no lo usa. |
| Pendientes por consolidar | `GET /edan/consolidar/pendientes?id_municipio&estado=aprobado` | Bandeja de aprobación (grupos + `localidades[]`). |
| Desconsolidar | `PUT /edan/localidades/{id_localidad}/desconsolidar` | Sacar una localidad del padre. |
| Ver EDAN de un RESP | `GET /edan/formularios/{uuid|id}/completo` | Documento completo de una localidad. |
| Usuarios del municipio | `GET /usuarios/?skip=0&limit=50&id_municipio=&id_rol=` | Listar responsables (**barra final**). |
| Crear usuario | `POST /usuarios/` | Alta (rol 7/8 según caso). |
| Editar / detalle usuario | `PUT /usuarios/{id}`, `GET /usuarios/{id}` | Datos del usuario. |
| Repositorio de documentos | `GET /repositorio/tipos`, `GET /repositorio/edan/{id}/documentos`, `POST /repositorio/edan/{id}/documentos`, `GET /repositorio/documentos/filtrar`, `GET /repositorio/documentos/{id}/descargar`, `DELETE /repositorio/documentos/{id}` | Gestión documental del EDAN municipal. |
| Firma digital | `POST /firma-digital/validar-pdf` | Validar PDF firmado. |

> **Alcance (scopes).** El detalle exacto está en **PLAN §19.2**: roles 6 y 7
> escriben solo sobre lo propio (ajeno → `403`); 8 = su municipio; 5/9 = su
> departamento; 1–4 = nacional. `GET /edan/` con rol 6 restringe a
> `id_usuario_ugr` propio; `GET /edan/localidades/municipio/{id}` respeta el
> municipio del usuario.

### 3.2. Endpoints usados por UGR (detalle)

| Método | Ruta | Notas |
|---|---|---|
| GET | `/edan/?order_by=id_edan&order=desc&skip=&limit=&id_municipio=` | Listado del padre. `limit` usado: **500** (máx. servidor 500). Trae `localidades[]` completas. |
| GET | `/edan/{uuid_edan\|id_edan}` | Detalle del padre. `?modo=compacto` → `sumatorias` + solo secciones con datos. |
| PUT | `/edan/{uuid_edan\|id_edan}` | Actualizar padre (LWW, sin `version`). |
| PUT | `/edan/{uuid_edan\|id_edan}/deshacer` | Deshacer consolidación (aplica directo). |
| GET | `/edan/consolidar/pendientes?id_municipio=&estado=` | `estado` por defecto `aprobado`. Cada grupo trae `localidad_ids[]` **y** `localidades[]` con uuid. |
| POST | `/edan/consolidar` | **Canónico:** `{ uuid_edan?, localidades:[uuid…] }` (exactamente una de las dos formas). Legacy aún aceptado: `{ id_municipio, id_tipo_evento, localidad_ids }`. Ver §3.3. |
| POST | `/edan/consolidar/auto?id_municipio=&id_tipo_evento=` | **Query params, no body.** No usado por la app. |
| PUT | `/edan/localidades/{id}/desconsolidar` | — |
| GET | `/edan/localidades/municipio/{id_municipio}` | Sin paginación (ver §7). |
| GET | `/edan/localidades/municipio/{id_municipio}/resumen` | Agregados. |
| PUT | `/edan/localidades/{id}/estado` | `{ id_edan_localidad_estado }`. |
| GET | `/edan/localidades-estado` | Catálogo. |
| GET | `/edan/formularios?...` | Misma familia V2 que RESP. |
| GET | `/edan/formularios/{uuid\|id}/completo` | Documento completo. |
| GET | `/edan/formularios/estados` | Listado ligero / resumen. |
| GET/POST/PUT | `/usuarios/`, `/usuarios/{id}` | `GET` con `skip=0&limit=50` (**barra final**). |
| GET | `/repositorio/tipos` | Tipos de documento. |
| GET | `/repositorio/edan/{id}/documentos` | Documentos de un EDAN. |
| POST | `/repositorio/edan/{id}/documentos` | Multipart (PDF/DOC). |
| GET | `/repositorio/documentos/filtrar?...` | Filtros: depto/prov/municipio/tipo/fechas/nombre. |
| GET | `/repositorio/documentos/{id}/descargar` | Bytes. |
| DELETE | `/repositorio/documentos/{id}[/hard]` | Borrado lógico / físico. |
| POST | `/firma-digital/validar-pdf` | `{ pdfFirmadoBase64, contrasenia }`. |

### 3.3. Consolidar: las dos formas (elegir una)

```jsonc
// ✅ CANÓNICA (uuid) — recomendada para la web
POST /edan/consolidar
{ "uuid_edan": "11111111-2222-4333-8444-555555555555",   // opcional: si falta, lo genera el servidor
  "localidades": [ "25717620-0347-404f-b933-c609d8733ad4",
                   "33cd83e3-b2c2-457c-8353-58e3c0db7251" ] }

// ⚠ LEGACY (ids) — todavía funciona, marcada deprecated
POST /edan/consolidar
{ "id_municipio": 70101, "id_tipo_evento": 2, "localidad_ids": [ 342930, 342931 ] }
```

Reglas (PLAN §20.17 B.3):

- Roles **6/7**; otros → `403`.
- Todas las localidades deben estar **aprobadas (estado 3)**, **sin EDAN** y ser
  del **mismo municipio y tipo de evento**; si no → `400`.
- Idempotencia por `uuid_edan`: mismo uuid + mismo conjunto → `200` (mismo
  `id_edan`); mismo uuid + otro conjunto → `409`.
- Respuesta = EDAN completo (misma forma que `GET /edan/{ref}`).
- `GET /edan/consolidar/pendientes` ya devuelve `localidades[]` con
  `uuid_edan_localidad`; la web puede mandar esos uuid directo sin consultar
  cada localidad.

---

## 4. Sección especial: Wizard EDAN (RESP)

### 4.1. Principio

El wizard **no guarda contra la API campo por campo**. Cada página escribe en SQLite (`formularios`, `filas_seccion`, `viviendas`). La API aparece en tres momentos:

1. **Catálogos** al abrir (una vez, cacheables).
2. **Enviar** (botón): un único documento completo.
3. **Fotos**: después de que el documento fue confirmado.

### 4.2. Secuencia del botón Enviar

```
_guardar(guardarTodasActivas: true)          // consolida todas las páginas en SQLite
marcarEnvioPendiente(uuid, estado = 2)       // intención SIEMPRE (online u offline)
if (online):
    EdanEnvioV2.enviar(...)
      → POST /edan/formularios/completo      // primera vez
      → PUT  /edan/formularios/completo      // si ya tenía id_server
if (servidor confirma):
    marcarEnviado(uuid)                      // estado_local = 'enviado'
else:
    queda pendiente_push = 1                 // el próximo sync reintenta
```

Importante:

- La **intención de envío se registra siempre**. Si no hay red, el reporte queda como pendiente y **no** se envía como borrador.
- No se marca "enviado" hasta que el servidor responde 2xx. Nunca se miente al usuario.
- Las fotos pendientes suben en la fase de fotos del sync, no dentro del `/completo`.

### 4.3. Estructura del JSON de `/edan/formularios/completo`

```jsonc
{
  // ── Cabecera ──
  "uuid_edan_localidad": "8f14e45f-ceea-467f-a1c0-0d5e6d2f9b11",
  "localidad": "Comunidad San José",
  "id_municipio": 70101,
  "id_departamento": 7,
  "id_provincia": 701,
  "id_tipo_evento": 2,
  "id_tipo_localidad": 1,
  "id_edan_localidad_estado": 2,
  "fecha_llenado": "2026-10-19T09:15:00",
  "fecha_evento": "2026-10-18",
  "hora_evento": "16:40",
  "total_poblacion_afectada": 120,
  "total_familias_afectadas": 30,
  "total_familias_damnificadas": 8,

  // ── 14 flags de sección (SIEMPRE las 14, true/false) ──
  "imp_impacto_poblacion": true,
  "imp_salud_establecimientos": false,
  "imp_danos_viales": false,
  "imp_danos_infra_publica": false,
  "imp_servicios_basicos": false,
  "imp_unidades_educativas": false,
  "imp_danos_vivienda": true,
  "imp_danos_agricultura": false,
  "imp_danos_pecuarios": false,
  "imp_infra_productiva": false,
  "imp_primera_respuesta": false,
  "imp_necesidad_salud": false,
  "imp_necesidad_humanitaria": false,
  "imp_proteccion": false,

  // ── Secciones 1:N (solo las activas) ──
  "impacto_poblacion": [
    { "uuid_registro": "...", "id_grupo_etario": 1, "marcado": true, "fallecidos": 0, "heridos": 2, "desaparecidos": 0, "observaciones": "" }
  ],

  // ── Sección 1:1 con hijas ──
  "danos_vivienda": {
    "uuid_registro": "...",
    "total_viviendas_afectadas": 4,
    "viviendas": [
      { "uuid_registro": "...", "tipo_dano": "Parcial", "coordenada_lat": -17.78, "coordenada_lon": -63.18 }
    ]
  }
}
```

**No enviar nunca** en `POST /edan/formularios/completo`:

- `grup_*` (9 flags de grupo): el servidor los deriva de las 14 `imp_*`.
- `id_seccion`, `version`, `fotografia`, `fecha_modificacion`: los maneja el servidor.
- **Todo `id_*` que no sea catálogo.** Único caso en que los ids numéricos se
  pueden mandar es en la **cabecera**: `id_municipio`, `id_departamento`,
  `id_provincia`, `id_tipo_evento`, `id_tipo_localidad`,
  `id_edan_localidad_estado`, `id_usuario`. En las secciones solo:
  `id_grupo_etario`, `id_grupo_vulnerable_catalogo`, `id_cultivo`, `id_especie`.
  Cualquier otro (`id_seccion`, `id_dano_*`, `id_servicio_*`, `id_localidad`…)
  lo rechaza el servidor con **400 «Campo desconocido o no escribible»**.
- `imp_*` que no correspondan a una sección existente (las 14 son obligatorias y deben ser coherentes).

### 4.4. Reglas del servidor que el wizard respeta

1. **Las 14 `imp_*` son obligatorias** en `/completo`. Si falta una → `400`.
2. **`flag = true` exige filas** (enviadas o ya existentes). Si no → `400` atómico (no escribe nada).
3. **Filas existentes fuerzan `flag = true`**.
4. **`POST` es solo creación** (uuid nuevo). Si existe → `409` → reintentar con `PUT`.
5. **`PUT` no crea** (uuid inexistente → `404`) → reintentar con `POST`.
6. **`/completo` no borra**: lo ausente se conserva. Borrar = `DELETE` explícito de la fila.
7. **Sin `version`**: LWW. No enviar `fecha_modificacion`.

### 4.5. Autocorrección del 400 "flag true sin filas"

Si el servidor responde `400` indicando un flag `true` sin filas (dato huérfano de un borrado sin tombstone), el cliente reintenta **una vez** con:

- ese `imp_*` en `false`, y
- su sección eliminada del payload.

No se pierde nada: el upsert no borra y el próximo push de otro dispositivo puede restaurar el dato.

### 4.6. `grup_*` vs `imp_*` — no confundirlos

| Prefijo | Cuántos | Qué representa | ¿Viaja en `/completo`? |
|---|---|---|---|
| `imp_*` | 14 | **Secciones** (una por ruta v2, `-` → `_`) | **Sí** (obligatorias) |
| `grup_*` | 9 | **Grupos** del paso 01 del wizard | **No** (el servidor los deriva) |

#### Matriz grupo → secciones (fuente única)

| Grupo (`grup_*`) | Secciones que activa |
|---|---|
| `grup_poblacion` | `impacto-poblacion`, `primera-respuesta` |
| `grup_salud` | `salud-establecimientos`, `necesidad-salud` |
| `grup_infraestructura` | `danos-viales`, `danos-infra-publica` |
| `grup_servicios` | `servicios-basicos` |
| `grup_educacion` | `unidades-educativas` |
| `grup_vivienda` | `danos-vivienda` |
| `grup_agropecuario` | `danos-agricultura`, `danos-pecuarios`, `infra-productiva` |
| `grup_proteccion` | `proteccion` |
| `grup_necesidades` | `necesidad-humanitaria` |

#### Las 14 secciones

| # | Ruta v2 | Clave JSON | Tipo | Foto | Flag `imp_*` |
|---|---|---|---|---|---|
| 1 | `impacto-poblacion` | `impacto_poblacion` | 1:N | — | `imp_impacto_poblacion` |
| 2 | `salud-establecimientos` | `establecimientos_salud` | 1:N | Sí | `imp_salud_establecimientos` |
| 3 | `danos-viales` | `danos_viales` | 1:N | Sí | `imp_danos_viales` |
| 4 | `danos-infra-publica` | `danos_infra_publica` | 1:N | Sí | `imp_danos_infra_publica` |
| 5 | `servicios-basicos` | `servicios_basicos` | 1:N | Sí | `imp_servicios_basicos` |
| 6 | `unidades-educativas` | `unidades_educativas` | 1:N | Sí | `imp_unidades_educativas` |
| 7 | `danos-vivienda` | `danos_vivienda` | 1:1 (+`viviendas[]`) | Sí | `imp_danos_vivienda` |
| 8 | `danos-agricultura` | `danos_agricultura` | 1:N | Sí | `imp_danos_agricultura` |
| 9 | `danos-pecuarios` | `danos_pecuarios` | 1:N | Sí | `imp_danos_pecuarios` |
| 10 | `infra-productiva` | `infra_productiva` | 1:N | Sí | `imp_infra_productiva` |
| 11 | `proteccion` | `proteccion` | 1:N | — | `imp_proteccion` |
| 12 | `primera-respuesta` | `necesidad_primera_respuesta` | 1:1 | — | `imp_primera_respuesta` |
| 13 | `necesidad-salud` | `necesidad_salud` | 1:1 | — | `imp_necesidad_salud` |
| 14 | `necesidad-humanitaria` | `necesidad_humanitaria` | 1:1 | — | `imp_necesidad_humanitaria` |

> Ojo con los nombres que **no** coinciden: `salud-establecimientos` → `establecimientos_salud` y `primera-respuesta` → `necesidad_primera_respuesta`. La `imp_*` siempre sale de la ruta.

### 4.7. Filas de grupo: regla 4 y regla 8

Dos secciones contienen exactamente los grupos del catálogo:

| Sección | Filas | Regla |
|---|---|---|
| `impacto-poblacion` | **4** grupos etarios (ids 1–4) | Si `imp_impacto_poblacion = true`, enviar **las 4** filas, incluidas las de ceros. |
| `proteccion` | **8** grupos vulnerables (ids 1–8) | Si `imp_proteccion = true`, enviar **las 8** filas, incluidas las de ceros. |

Claves:

- `impacto_poblacion[i].id_grupo_etario` ∈ `{1,2,3,4}`.
- `proteccion[i].id_grupo_vulnerable_catalogo` ∈ `{1..8}`.
- Si hay duplicados por id, gana la fila **con datos**; las vacías se descartan.
- Las filas con contenido nunca se ocultan (los extras se conservan al final).

### 4.8. Páginas del wizard → secciones

| Página | Secciones que escribe |
|---|---|
| 01 Datos generales | `cabecera` |
| 02 Población | `cabecera` |
| 03 Población afectada | `impacto-poblacion`, `primera-respuesta` |
| 04 Salud | `salud-establecimientos`, `necesidad-salud` |
| 05 Infraestructura | `danos-viales`, `danos-infra-publica` |
| 06 Servicios básicos | `servicios-basicos` |
| 07 Educación | `unidades-educativas` |
| 08 Vivienda | `danos-vivienda` |
| 09 Agropecuario | `danos-agricultura`, `danos-pecuarios`, `infra-productiva` |
| 10 Protección | `proteccion` |
| 11 Necesidades | `necesidad-humanitaria` |
| 13 Responsable | `cabecera` |

### 4.9. Fotos

- `POST /edan/fotografias` es **multipart**.
- `tipo_entidad` debe ser el **nombre corto de tabla** (14 nombres) o `vivienda`; **no** la clave JSON.
- Campos: `uuid_fotografia`, `tipo_entidad`, `uuid_registro`, `archivo`, `sha256?`.
- Una foto solo se sube cuando su registro padre está confirmado.
- Reintentos con espera progresiva: 1 min, 5 min, 15 min (tope 3).

---

## 5. uuid vs id — tabla rápida

| Recurso | Clave en ruta/body | Al crear |
|---|---|---|
| Formulario (cabecera) | `uuid_edan_localidad` | `POST /edan/formularios[/completo]` devuelve `id_edan_localidad` → guardar como `id_server`. |
| Sección 1:N | `uuid_registro` de la fila | `POST .../secciones/{tipo}`; devuelve ids de fila. |
| Sección 1:1 | `uuid_registro` del documento | Upsert por uuid. |
| Vivienda | `uuid_registro` de la vivienda | `POST .../danos-vivienda/{uuid_dano}/viviendas`. |
| Foto | `uuid_fotografia` | `POST /edan/fotografias`. |
| EDAN padre (UGR) | **`uuid_edan`** (nuevo) o `id_edan` | Lo crea `POST /edan/consolidar`; si no mandas `uuid_edan` lo genera el servidor. |
| Localidad (UGR) | `id_localidad` numérico en los endpoints viejos; **`uuid_edan_localidad`** en el contrato V2 | Catálogo del servidor. |

**GET por path:** `GET /edan/formularios/{uuid|id}/completo` acepta ambos. Preferir uuid.
**Alias con identidad en la ruta:** `POST /edan/formularios/{uuid_edan_localidad}` existe como variante de `/formularios` (PLAN §20.17 B.6).
**Nunca** enviar ids numéricos de sección (`id_seccion`, `id_dano_*`, etc.) en `POST`: el servidor los rechaza (400 «Campo desconocido o no escribible»).

**Flujo de identidad en la práctica:**

```text
1. cliente: uuid_edan_localidad = 8f14e45f-ceea-…   (se genera 1 vez, nunca se regenera)
2. POST /edan/formularios/completo  { uuid_edan_localidad, … }  → 200, data.id_edan_localidad = 343463
3. guardar  id_server = 343463   y  uuid_edan_localidad = 8f14e45f…
4. PUT /edan/formularios/completo  { uuid_edan_localidad, … }   → 200   (mismo uuid, jamás duplica)
5. GET /edan/formularios/8f14e45f-ceea-…/completo   o   /343463/completo  → mismo documento
```

---

## 6. Endpoints legacy: vivos y muertos

### Vivos (la app todavía los usa)

- `POST /auth/login`, `/auth/register`, `/auth/verificar-identidad`, `/auth/cambiar-contrasena`
- `GET /shared/departamentos`, `/shared/provincias`, `/shared/municipios`, `/shared/municipios/{id}/geojson`, `/shared/cultivos`, `/shared/pecuario`
- `GET /edan/tipo-evento`, `/edan/tipo-localidad`, `/edan/grupo-etario`, `/edan/grupo-vulnerable`, `/edan/estados`, `/edan/localidades-estado`
- `GET /edan/?...`, `GET /edan/{uuid|id}`, `PUT /edan/{uuid|id}`, `PUT /edan/{uuid|id}/deshacer`
- `GET /edan/consolidar/pendientes`, `POST /edan/consolidar`, `POST /edan/consolidar/auto`, `PUT /edan/localidades/{id}/desconsolidar`
- `GET /edan/localidades/municipio/{id}`, `.../resumen`, `PUT /edan/localidades/{id}/estado`
- `GET/POST/PUT /usuarios/`, `GET/PUT /usuarios/{id}`
- `GET /repositorio/...`, `POST /repositorio/edan/{id}/documentos`, `POST /firma-digital/validar-pdf`
- `POST /upload`, `GET /upload/descargar/{path}` (compatibilidad de fotos)

### Muertos (no usar)

- `POST/PUT /edan/localidades/{id}/documento` → reemplazado por `/edan/formularios/completo`.
- `GET /edan/localidades/sync/pull` (legacy de localidades) → reemplazado por `GET /edan/sync/pull` V2.
- `POST /edan/sync/push` → **no se usa**; el push va por `/edan/formularios/completo`.
- `POST /edan/localidades/{id}/{seccion}/con-foto` → reemplazado por `POST /edan/fotografias`.

---

## 7. Límites de GET (para no saturar la BD)

| Endpoint | Límite usado | Estrategia |
|---|---|---|
| `GET /edan/formularios` | `limit=100` por defecto; **200** al descargar un municipio | Paginar con `skip` hasta que devuelva menos de `limit`. |
| `GET /edan/formularios/estados` | `limit=200` | Incremental con `fecha_modificacion_desde`; `limit=1` solo para el resumen. |
| `GET /edan/?...` | `limit=500` | Orden `id_edan desc`; paginar si hace falta. **Con barra final.** |
| `GET /edan/localidades/municipio/{id}` | Sin paginación | Usar `/resumen` para contadores; el listado es por municipio. |
| `GET /usuarios/` | `skip=0&limit=50` | **Barra final obligatoria**; filtrar por `id_municipio` / `id_rol`. |
| `GET /edan/sync/pull` | `limit` configurable | El motor pagina y avanza el watermark. |
| `GET /edan/formularios/{uuid}/completo` | Documento único | No hay paginación; usar `comprimido=true` para badges. |

Regla práctica para la web: **nunca** pedir "todo" sin `limit`; usar el endpoint de estados para listados grandes y traer el detalle por documento.

---

## 8. Pendientes / discrepancias conocidas

1. `prepararPayloadCompleto()` puede arrastrar `id_seccion` y `fecha_modificacion` residuales de `datos_json`; `crearFormularioCompleto()` **no** pasa por `sanitizePostPayload()`. El equipo web debe limpiar ambos campos antes de enviar.
2. `POST /edan/sync/push` está implementado en el cliente pero **no se usa**; no documentarlo como flujo vigente.
3. `GET /edan/estados` devuelve solo los EDAN propios del usuario (comportamiento intencional).
4. `necesidad_humanitaria` existe en localidades pero **no** en la raíz del EDAN padre; no asumir esa clave ahí.
5. El campo del modelo se llama `impPrimeraRespuesta`, pero la clave de API es `imp_primera_respuesta`.
6. `GET /edan` (sin barra) → `401`: el `307` a `/edan/` hace que muchos clientes pierdan el `Authorization`. Usar **`/edan/`**.
7. `GET /formularios` **sin** `modo=completo` devuelve solo las secciones que tienen filas; con `modo=completo` vienen las 14 claves (aunque vacías). No confundir "no vino la clave" con "sección desactivada".
8. La app consolida con la forma **legacy** (`localidad_ids` numéricos); la web nueva debería usar `localidades:[uuid]`. Ambas siguen aceptadas.
9. `POST /edan/consolidar/auto` lee `id_municipio`/`id_tipo_evento` de **query**, pero el cliente Flutter los manda en el body (`consolidarAuto`, sin uso) → devolvería `422`. Si la web lo usa, mandarlos por query.

---

## 9. Catálogos y códigos (verificados)

**Estados de localidad** (`GET /edan/localidades-estado`, `id_edan_localidad_estado`):

| id | nombre | orden | significado |
|---|---|---|---|
| 1 | Borrador | 1 | En construcción en el lugar; aún no enviado. |
| 6 | En revisión UGR | 3 | El UGR lo abrió para verificar. |
| 2 | Enviado UGR | 4 | Completo; pendiente de revisión del UGR. |
| 3 | **Aprobado UGR** | 5 | Validado; **único estado consolidable**. |
| 4 | Rechazado UGR | 6 | Devuelto con observaciones. |
| 5 | Aprobado Ajuste UGR | 7 | Aprobado con ajustes. |

**Estados del EDAN padre** (`GET /edan/estados`, `id_estado`): 1 Pendiente aprobaciones · 2 Rechazado · 3 Aprobado · 4 Observado.

**Grupos** (`grup_*`) y sus 9 claves: `grup_poblacion`, `grup_salud`, `grup_infraestructura`, `grup_servicios`, `grup_educacion`, `grup_vivienda`, `grup_agropecuario`, `grup_proteccion`, `grup_necesidades`. La matriz grupo → secciones está en §4.6.

**Tipo de evento / localidad / grupos etarios y vulnerables**: `GET /edan/tipo-evento`, `/edan/tipo-localidad`, `/edan/grupo-etario`, `/edan/grupo-vulnerable` (catálogos completos, sin paginar).

---

## 10. Prueba rápida (30 segundos, solo lectura)

```bash
BASE=https://api.climbat.net/api/v2
TOKEN=<access_token del login>

# 1) ¿el token y el rol funcionan?
curl -s "$BASE/edan/tipo-evento" -H "Authorization: Bearer $TOKEN" | head -c 200

# 2) dashboard (resumen de estados)
curl -s "$BASE/edan/formularios/estados?limit=1" -H "Authorization: Bearer $TOKEN"

# 3) documentos del municipio (ojo: rol 6 → /edan/ con barra)
curl -s "$BASE/edan/?limit=5&order_by=id_edan&order=desc" -H "Authorization: Bearer $TOKEN"

# 4) un documento completo (uuid o id)
curl -s "$BASE/edan/formularios/<uuid>/completo" -H "Authorization: Bearer $TOKEN"

# 5) sync incremental
curl -s "$BASE/edan/sync/pull?limit=1" -H "Authorization: Bearer $TOKEN"
```

Si `curl` devuelve `401` en los pasos 3 o 4, revisar la **barra final** y el
`Authorization` antes de culpar al endpoint.

---

## 11. Documentos relacionados

| Documento | Uso |
|---|---|
| `PLAN_APIS_V2_EDAN.md` | **Contrato del servidor.** Empezar por su bloque «LÉAME PRIMERO». Detalle: §19 (integración), §20.14 (LWW), §20.15 (POST/PUT completo), §20.16 (ids con JSON), §20.17 (EDAN padre/consolidar), **§20.18 (verificación en vivo 2026-10-19)**, §7 (fotos), §15 (sync). |
| `https://api.climbat.net/openapi.v2.json` | OpenAPI: esquemas y parámetros exactos. |
| `FLUJO_EDAN_UGR.md` | Modelo de datos y flujo funcional (apoyo). |
| `MAPEO_FORMULARIO_EDAN.md` | Correspondencia campo a campo del formulario (apoyo). |
| `ROLE_6_UGR.md` / `ROLE_7_RESP.md` | Referencia por rol (histórico, con banner de vigencia). |
| `DOCUMENTO_V2_SYNC.md` | Histórico; **obsoleto** en el contrato de envío. |
| `APIS_PESTANA_EDAN_UGR.md` | Histórico; parcialmente obsoleto. |

---

**Regla final:** si este documento y el código difieren, manda el **código + OpenAPI**. Este mapa debe actualizarse cuando cambie un endpoint, un límite o una regla de payload.
