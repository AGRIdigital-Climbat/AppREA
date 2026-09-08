# APIs de la pestaña "EDAN" — Rol 6 UGR

Documento técnico con el inventario **exacto** de endpoints que utiliza la pestaña "EDAN" de la pantalla del rol 6 UGR (`UgrScreen` → `UgrEdanTab`).

> Alcance: solo la pestaña **EDAN** (index 1), incluye su sub-tab **Recursos** y las acciones del detalle/preview y sincronización asociadas a EDAN. **No** incluye la pestaña "EDAN Local" (localidades).

---

## Base URL

```
https://api.climbat.net/api/v2
```

Definición en `lib/config/api_config.dart`:

| Constante | Valor |
|---|---|
| `baseUrl` | `https://api.climbat.net/api/v2` |
| `edanEndpoint` | `$baseUrl/edan` |
| `usuariosEndpoint` | `$baseUrl/usuarios` |
| `repositorioEndpoint` | `$baseUrl/repositorio` |

Autenticación: `Authorization: Bearer <token JWT>` (refresco automático vía `_headers` en `api_service.dart`).

---

## 1. Lista de EDANs

**Archivo:** `lib/screens/role_screens/ugr/ugr_edan_tab.dart`

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `listarEdansPorMunicipio(idMunicipio)` | 91 | GET | `/edan/?order_by=id_edan&order=desc&skip=0&limit=500&id_municipio={id_municipio}` |
| `getEdanById(idEdan)` | 317 | GET | `/edan/{id_edan}` |

- La lista consulta el servidor si hay conexión (`ConnectivityService`); si no, cae a SQLite local (`getEdansByMunicipio`).
- Al abrir un EDAN: si tiene `id_local` se lee de SQLite; si no, se hace `getEdanById` y se abre `UgrEdanPreviewScreen`.

## 2. Detalle / Vista previa del EDAN

**Archivo:** `lib/screens/role_screens/ugr/ugr_edan_preview_screen.dart`

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `getUsuarios(idMunicipio, idRol: 8)` | 44 | GET | `/usuarios?id_municipio={id_municipio}&id_rol=8&skip=0&limit=50` |
| `listarDocumentosEdan(idEdan)` | 58 | GET | `/repositorio/edan/{id_edan}/documentos` |
| `getUsuario(id)` | 431 | GET | `/usuarios/{id}` |
| `updateEdan(edanId, {...})` | 524 | PUT | `/edan/{id_edan}` |
| `deshacerEdan(edanId)` | 602 | PUT | `/edan/{id_edan}/deshacer` |
| `descargarDocRepositorio(idDoc)` | 1963 / 1992 | GET | `/repositorio/documentos/{id_documento}/descargar` |
| `eliminarDocRepositorioHard(idDoc)` | 2057 | DELETE | `/repositorio/documentos/{id_documento}/hard` |
| Fotos del EDAN (`_FotosDe`) | 2357-2358 | GET | `/upload/descargar/{path}` (directo con Bearer) |

Detalles:
- `updateEdan` asigna el alcalde responsable: `{ id_usuario_alcalde, nombre_alcalde, fono_alcalde, responsable: { nombre, fono } }`.
- `deshacerEdan` revierte la consolidación liberando las localidades del EDAN.
- Las fotos se cargan vía `Image.network` hacia `/upload/descargar/{path}` con header `Authorization` (NO pasan por `ApiService`).

## 3. Sub-tab Recursos (dentro de la pestaña EDAN)

**Archivo:** `lib/screens/role_screens/ugr/ugr_recurso_tab.dart`

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `filtrarDocumentos()` | 43 | GET | `/repositorio/documentos/filtrar` |
| `descargarDocRepositorio(idDoc)` | 194 / 223 | GET | `/repositorio/documentos/{id_documento}/descargar` |

## 4. Subir documento

**Archivo:** `lib/screens/role_screens/ugr/ugr_recurso_upload_screen.dart`

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `listarTiposRepositorio()` | 56 | GET | `/repositorio/tipos` |
| `subirDocumentoEdan(...)` | 154 | POST (multipart) | `/repositorio/edan/{id_edan}/documentos` |

Campos del multipart en `subirDocumentoEdan`:
`file`, `id_tipo_documento`, `nombre_documento`, `fecha_documento`, `id_departamento`, `id_provincia`, `id_municipio`, `observaciones` (opcional).

## 5. Crear / editar alcalde (usuario rol 8)

**Archivo:** `lib/screens/role_screens/ugr/crear_usuario_screen.dart`

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `createUsuario(...)` | 107 | POST | `/usuarios/` |
| `updateUsuario(id, {...})` | 88 | PUT | `/usuarios/{id}` |

- `createUsuario` envía: `usuario`, `contrasena`, `nombre`, `celular`, `carnet`, `comunidad`, `correo`, `cargo`, `id_departamento`, `id_provincia`, `id_municipio`, `id_rol=8`, `activo=true`.
- `updateUsuario` envía solo los campos no nulos (nombre, celular, comunidad, correo, cargo, departamento, provincia, municipio).

## 6. Sincronización (botón "Sincronizar" del AppBar)

**Archivo:** `lib/services/edan_sync_service.dart` — se dispara desde `ugr_screen.dart` (`_sincronizar`).

| Método (`ApiService`) | Línea | HTTP | Ruta |
|---|---|---|---|
| `pullEdans(idUsuarioUgr)` | 128 | GET | `/edan/?skip=0&limit=100&id_usuario_ugr={id}&es_borrador=false` |
| `getLocalidadesMisReportes(idUsuario, modoComprimido)` | 165 | GET | `/edan/localidades/mis-reportes` |
| `deleteEdan(id, permanente=false)` | 257 | DELETE | `/edan/{id_edan}?permanente=false` |

Flujo del botón **Sincronizar** (`Sincronizar` → `EdanSyncService.sincronizar()`):
1. `_pullEdans` — descarga EDANs del municipio/UGL (`GET /edan/`) y sus localidades con secciones (`GET /edan/localidades/mis-reportes`).
2. `_pushDeletions` — elimina EDANs marcados como pendientes (`DELETE /edan/{id}`).
3. `_pushEdans` — envía EDANs no sincronizados **por localidad** vía `PUT /edan/localidades/{id_localidad}/documento` (contrato Fase 2 del RESP, gestionado por `EdanDocumentoSyncService`).

Nota: el endpoint antiguo `/edan/sync/pull` ya no existe en v2 (404) y fue sustituido por el listado estándar.

---

## Verificación en swagger v2

Inventario confirmado contra `oea_openapi_v2.json` — **todas las rutas existen con el verbo correcto**:

| Ruta | Verbos |
|---|---|
| `/edan/` | `get, post` |
| `/edan/{id}` | `get, put, delete` |
| `/edan/{id}/deshacer` | `put` |
| `/edan/{id}/estado` | `put` |
| `/edan/localidades/mis-reportes` | `get` |
| `/edan/localidades/{id_localidad}/documento` | `get, put, delete` |
| `/edan/localidades/{id_localidad}/estado` | `put` |
| `/usuarios/` | `get, post` |
| `/usuarios/{id}` | `get, put, delete` |
| `/repositorio/edan/{id_edan}/documentos` | `post, get` |
| `/repositorio/documentos/filtrar` | `get` |
| `/repositorio/documentos/{id_documento}` | `get, put, delete` |
| `/repositorio/documentos/{id_documento}/descargar` | `get` |
| `/repositorio/documentos/{id_documento}/hard` | `delete` |
| `/repositorio/tipos` | `get, post` |
| `/upload/descargar/{path}` | `get` |

Rutas probadas en vivo (auditoría previa, respuesta 200 OK): `GET /edan/`, `GET /edan/78`, `GET /repositorio/tipos`, `GET /edan/localidades/mis-reportes`.

---

## Notas

- **Regeneración del documento**: el inventario de rutas/métodos debe revisarse al tocar `ugr_edan_tab.dart`, `ugr_edan_preview_screen.dart`, `ugr_recurso_tab.dart`, `ugr_recurso_upload_screen.dart`, `crear_usuario_screen.dart` y `edan_sync_service.dart`.
- La asignación de alcalde y el alta de usuarios son acciones de escritura que requieren permisos de UGR; el resto son de lectura.
- Fotos y documentos siguen el patrón `Autorization: Bearer` en todo momento.