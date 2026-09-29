# CORRECCIONES EXHAUSTIVAS - App EDAN (SINAGER-SAT)

> Referencia rápida: estructura, flujos clave, reglas de UI y problemas corregidos/pendientes del wizard EDAN. Fecha: 2026-09-17.

---

## 1. ESTRUCTURA GENERAL

```
lib/
├── main.dart                        # Entry + MultiProvider
├── config/    api_config, modules, role_router (rol6→Ugr, rol7→Resp), theme
├── providers/ auth_provider, reporte_provider (catálogos), connectivity_provider, asistente_ia_provider
├── services/  auth_service, api_service (1785L), database_helper (SQLite v29, 3470L), sync_manager
│   ├── ai/                              # ★ Asistente IA RAG con voz
│   │   ├── asistente_ia_service.dart   # API /chat con SSE, documentoIds, _voiceHint
│   │   └── asistente_voz_service.dart  # TTS/STT, awaitSpeakCompletion, permisos
│   ├── edan_secciones_registry.dart        # Registry declarativo 14 secciones v2
│   ├── edan_sync_service.dart / localidad_sync_service.dart   # Sync legado
│   └── edan/                               # ★ Flujo v2 RESP
│       ├── edan_sync_respo_service.dart    # Sync unificado 3 fases
│       ├── edan_documento_sync_service.dart# Envío documento completo
│       ├── edan_documento_service.dart     # Serialización JSON simétrico
│       ├── edan_localidades_envio_v2_service.dart # Persistencia SQLite
│       ├── edan_secciones_envio_factory.dart / edan_seccion_envio_base.dart
│       └── edan_*_service.dart             # 14 servicios por sección
├── models/    edan.dart (3356L), usuario.dart, id_seccion_helper, ugr_models (enum estado)
├── screens/   splash, login, register, forgot_password
│   ├── resp/  resp_screen (5 tabs), resp_dashboard_tab (Inicio), resp_edan_localidad_tab (Reportes),
│   │          resp_mapa_tab, resp_guia_tab, resp_edan_form_screen (legado)
│   │   └── edan/  # ★★ WIZARD
│   │       edan_form_wizard (1128L), edan_wizard_service, edan_page01..11+13, edan_resumen_page,
│   │       edan_navigation_bar, edan_step_indicator, edan_section_page, edan_section_instruction,
│   │       edan_seccion_estado, edan_subsection_header, edan_item_card, edan_dialog_helper,
│   │       edan_boton_sacar_foto, edan_aviso, edan_preview_resp_screen
│   └── ugr/   ugr_edan_tab, ugr_localidades_tab, ugr_edan_preview_screen, ugr_edan_preview_v2_screen, ugr_edan_form_screen
└── widgets/   custom_text_field, custom_button, edan_seccion_badges, edan_json_preview_dialog, asistente_ia, asistente_ia_bottom_sheet, asistente_ia_fab, tutorial_guide
```

---

## 2. AUTENTICACIÓN

**Flujo:** `main → MaterialApp(es_BO) → Splash → AuthProvider.initialize() → AuthService.initialize() → _autoLogin()` (lee token/credenciales de FlutterSecureStorage → `_verificarToken()` → `_loadUserProfile()`; fallback re-login con credenciales). Autenticado → `homeForRole` (6→Ugr, 7→Resp). No autenticado → `LoginScreen → POST /auth/login`. Éxito → `_dispararCargaEdansMunicipio()` (6→`EdanSyncService.recargarEdansMunicipio`, 7→`EdanSyncRespoService.recargarLocalidades`).

| Archivo | Ruta | Función |
|---|---|---|
| auth_service | `lib/services/auth_service.dart` | Singleton: login, register, logout, auto-login, verificar token |
| auth_provider | `lib/providers/auth_provider.dart` | Estado auth, permisos, disparo carga EDANs |
| splash_screen | `lib/screens/splash_screen.dart` | Animación + initialize + redirección |
| login_screen | `lib/screens/login_screen.dart` | Formulario UI |
| role_router | `lib/config/role_router.dart` | `homeForRole()` rol→pantalla |

**Problemas:** token rol6 expira a 3 días (línea 99; rol7 nunca); contraseña en texto plano en SecureStorage (línea 213); `cargarCatalogos()` nunca se llama; delay fijo 800ms en splash; `_autoLogin()` sin manejo de errores (falla silenciosa).

---

## 3. CARGA DE DATOS INICIALES

**Flujo:** `Splash._initializeApp → authProvider.initialize → _dispararCargaEdansMunicipio → EdanSyncRespoService.recargarLocalidades` (rol7). `RespScreen → ReporteProvider.initialize()` → `loadReportes` (SQLite), `loadCatalogsLocal` (cache), `loadGeography` (API deptos), `fetchAndCacheCatalogs` (API catálogos).

| Catálogo | Endpoint | Almacén |
|---|---|---|
| Departamentos/Provincias/Municipios | `/shared/{departamentos,provincias,municipios}` | SQLite + ReporteProvider |
| Tipos Evento / Estados EDAN | `/edan/{tipo-evento,estados}` | SQLite + ReporteProvider |
| Cultivos / Pecuario | `/shared/{cultivos,pecuario}` | SQLite + ReporteProvider |
| Grupos Vulnerables / Etarios | `/edan/{grupo-vulnerable,grupo-etario}` | SQLite + ReporteProvider |
| GeoJSON Municipio | GeoJSON endpoint | ReporteProvider |

---

## 4. WIZARD EDAN

**Núcleo:** `edan_form_wizard.dart` (1128L). `EdanFormWizard` (Stateful) + modelo `EdanLocalidad` en memoria (por referencia). `PageView.builder` con swipe, navegación `_irA(i)→animateToPage`, páginas reconstruidas según flags `imp*`.

| # | Key | Archivo | Condicional |
|---|---|---|---|
| intro | — | (en wizard) | siempre |
| 1 | 01 | edan_page01.dart — datos generales + checkboxes impacto | siempre |
| 2 | 02 | edan_page02.dart — población damnificada | siempre |
| 3 | 03 | edan_page03.dart — impacto población (grupos etarios + 1ª respuesta) | `impPoblacion` |
| 4 | 04 | edan_page04.dart — salud (1:N + foto) + necesidad salud | `impSalud` |
| 5 | 05 | edan_page05.dart — daños viales + infra pública (1:N + foto) | `impInfraestructura` |
| 6 | 06 | edan_page06.dart — servicios básicos (checklist) | `impServicios` |
| 7 | 07 | edan_page07.dart — unidades educativas (1:N + foto) | `impEducacion` |
| 8 | 08 | edan_page08.dart — viviendas (1:N + foto) | `impVivienda` |
| 9 | 09 | edan_page09.dart — agrícola + pecuario + infra productiva (foto) | `impAgropecuario` |
| 10 | 10 | edan_page10.dart — grupos vulnerables + apoyo psicológico | `impProteccion` |
| 11 | 11 | edan_page11.dart — necesidades humanitarias | `impNecesidades` |
| resumen | 13 | edan_page13.dart — responsable (solo lectura) | siempre |
| resumen | — | edan_resumen_page.dart — vista previa + Enviar | siempre |

**Flags:** compuestos `impPoblacion…impNecesidades` (checkbox → 1-3 secciones) y detallados `impImpactoPoblacion, impPrimeraRespuesta, impSaludEstablecimientos, impNecesidadSalud, impDanosViales, impDanosInfraPublica, impServiciosBasicos, impUnidadesEducativas, impDanosVivienda, impDanosAgricultura, impDanosPecuarios, impInfraProductiva, impNecesidadHumanitaria` (sub-secciones).

**Navegación/guiado:** AppBar(Guardar) → StepIndicator (círculos clickeables) → PageView(páginas en `EdanSectionPage` con `EdanSeccionInstruction`) → NavigationBar(Atrás/Siguiente/Enviar). Asistente IA: page02 + miniFAB contextual (`AsistenteIaFormFab`) en pages con `documentoIds: [21]`.

**Guardado:** `_guardar(key)` → `EdanSeccionesRegistry.rutasDePagina(key)` → `editado=true` → `updateLocalidad()+guardarSecciones()` (o `insertLocalidad()+activarSecciones()` si idLocal==null) → `_marcarGuardada`.

**Envío:** diálogo declaración jurada → `_guardar` → estado `enviadoUgr` → si hay conexión: `procesarColaDeletes → eliminarFilasAntesDelPush → enviarLocalidadDocumento` (POST crear / PUT actualizar) → `pop(true)`.

**Validación hard-block:** pages 03, 04, 07, 10 retornan `false` (step indicator "Pendiente" + bloquea envío) si la suma de personas excede `totalPoblacionAfectada`. Vive en la fuente canónica `EdanResumenPage.calcularSeccionesCompletas()` (`&& suma <= total`, §9.19/§9.21); el campo `valida` de `_WizardPage` fue eliminado (§9.21).

**Detección de cambios:** snapshot inicial tras sincronizar flags; comparación `jsonEncode(inicial)!=jsonEncode(actual)` excluyendo claves volátiles (`fecha_modificacion, pendiente_*, id_edan_localidad_estado, id_local, id_seccion, id_grupo_vulnerable_catalogo`).

---

## 5. SINCRONIZACIÓN

**EdanSyncRespoService** (rol7, 1372L) — 3 fases:
```
FASE 1 Fotos:  _subirFotosPendientes → uploadFile por foto
FASE 2 Datos:  _eliminarPendientes (DELETE) → _subirSucios (POST/PUT documento)
FASE 3 Pull:   _pullDatos (GET, LWW por timestamps) → 3b _descargarFotosPendientes
```

| Servicio | Rol |
|---|---|
| EdanDocumentoSyncService | Construye JSON, sube fotos primero, POST/PUT/DELETE |
| EdanSeccionesRegistry (270L) | 14 secciones: ruta v2, clave JSON, tipo 1:1/1:N, tabla SQLite |
| EdanLocalidadesEnvioV2Service | `guardarSecciones`, `popularSeccionesDesdeServer`, `cargarSeccionesDesdeSQLite` |

**Mapeo página → tablas SQLite:**

| Página | Tablas |
|---|---|
| 01/02/13 | `edan_localidad` |
| 03 | `seccion_impacto_poblacion`, `seccion_primera_respuesta` |
| 04 | `seccion_salud_establecimientos`, `seccion_necesidad_salud` |
| 05 | `seccion_danos_viales`, `seccion_danos_infra_publica` |
| 06 | `seccion_servicios_basicos` |
| 07 | `seccion_unidades_educativas` |
| 08 | `seccion_danos_vivienda` |
| 09 | `seccion_danos_agricultura`, `seccion_danos_pecuarios`, `seccion_infra_productiva` |
| 10 | `seccion_proteccion` |
| 11 | `seccion_necesidad_humanitaria` |

---

## 6. MODELOS CLAVE

**EdanLocalidad** (`models/edan.dart`, 3356L): cabecera (`idLocal, idEdanLocalidad, idUsuario, ids geográficos, nombre, idTipoEvento, fechas, estadoLocalidad, idEdanLocalidadEstado, editado, sincronizado, pendiente*`), 22 flags `imp*`, arrays 1:N (`impactoPoblacion, establecimientosSalud, danosViales, danosInfraPublica, serviciosBasicos, unidadesEducativas, danosVivienda, danosAgricultura, danosPecuarios, infraProductiva, proteccion`), objeto 1:1 (`necesidadPrimeraRespuesta, necesidadSalud, necesidadHumanitaria, responsable`).

**UgrLocalidadEstado:** borrador=1, enviadoUgr=2, enRevisionUgr=3, aprobadoUgr=4, rechazadoUgr=5, aprobadoAjuste=6.
**TokenResponse** (`models/usuario.dart`): accessToken, tokenType, userId, usuario, nombre, ids geográficos, celular, carnet, comunidad, correo, cargo, idRol, rol, permisos.

---

## 7. WIDGETS DE SOPORTE

| Widget | Función |
|---|---|
| EdanStepIndicator | Círculos de progreso clickeables |
| EdanNavigationBar | Barra inferior Atrás/Siguiente/Enviar |
| EdanSectionPage / EdanSeccionInstruction | Scroll vertical / card instrucción por página |
| EdanSubsectionHeader / EdanItemCard | Header "Agregar" / card ítem colapsable |
| EdanDialogHelper | Confirmaciones + diálogos inline |
| EdanBotonSacarFoto / EdanAvisoAfectaciones | Cámara+GPS / aviso naranja |

---

## 8. REGLAS DE UI (SKILL flutter-dev)

- **Inputs:** NUNCA `labelText`; título estático ARRIBA del campo; `hintText` solo placeholder (gris + itálico); nunca guardar hint como valor.
- **Numéricos:** título prefijado `'N° '` (ej: `'N° Fallecidos'`) en páginas 02-10 y diálogos.
- **Radio:** grupo DEBE tener título estático arriba; usar `RadioGroup<String>` (M3) con radio-row propio; campos condicionales visibles solo con la opción seleccionada.

---

## 9. PROBLEMAS IDENTIFICADOS

### 9.1 Wizard (análisis)
Falta `edan_page12.dart` (salta 11→13); `rebuild()` no reconstruye el PageController; `_snapshotInicial` puede no estar listo con navegación rápida; `_construirPaginas()` en initState y rebuild; validación page01 acepta vacío con checkbox; `_seccionTieneDatos03` no verifica datos reales; IA solo en page02; `_enviar()` guarda la página actual.

### 9.2 Autenticación
Token rol7 nunca expira; contraseña en texto plano; `cargarCatalogos()` muerto; delay splash 800ms; `_autoLogin()` sin errores.

### 9.3 Carga de datos
Sin garantía de orden `ReporteProvider` vs `AuthProvider`; `loadGeography` solo deptos; `fetchAndCacheCatalogs` catch vacío; `downloadPhase` sin progreso por catálogo.

### 9.4 Sincronización
`_subirFotosPendientes` sin retry; DELETE sin rollback; LWW sin resolver ediciones simultáneas; `_descargarFotosPendientes` sin límite de concurrencia; `recargarLocalidades` antes de ReporteProvider.

### 9.5 Click largo muestra JSON (debug en prod) — PENDIENTE
`onLongPress` en items de Inicio (`resp_dashboard_tab.dart:692`) y Reportes (`resp_edan_localidad_tab.dart:515`) abre `EdanJsonPreviewDialog` que muestra el JSON que se enviaría. Expone datos sensibles; condicionar con `kDebugMode` o eliminar.

### 9.6 Botones de acción según estado ✅ CORREGIDO
Preview y wizard mostraban "Enviar" siempre. Ahora `onEnviar` solo si estado `borrador`(1)/`rechazadoUgr`(4) Y `formularioCompleto()`; en `edan_navigation_bar.dart` botón deshabilitado + tooltip "Faltan secciones por completar". Archivos: `edan_preview_resp_screen.dart:78-85`, `edan_form_wizard.dart:1068-1079`, `edan_navigation_bar.dart:63-100`.

### 9.7 Completitud por datos reales ✅ CORREGIDO
`calcularSeccionesCompletas()` (antes `true` solo con flag) verifica `nombre+idTipoEvento`, datos en arrays/objeto y nuevo `formularioCompleto()`. Archivo: `edan_resumen_page.dart:30-89`.

### 9.8 Vista previa sin secciones con datos ✅ CORREGIDO
Causa: la vista previa no llamaba `cargarSeccionesDesdeSQLite()` (arrays vacíos) ni resincronizaba flags. Fix en `edan_preview_resp_screen.dart`: carga en `initState` + `_sincronizarFlagsActivas()` (leen `localidad_secciones_activas` → `construirFlagsDesdeActivas`, igual que `construirDocumento`). La vista previa y el JSON long press quedan 1:1.

### 9.9 Mensaje residual "Al presionar Enviar..." ✅ CORREGIDO
El texto se mostraba siempre. Ahora envuelto en `if (_puedeEnviar())` que solo es `true` en `borrador`/`rechazadoUgr`. Archivo: `edan_resumen_page.dart:187-194`.

### 9.10 Badges de impacto RESP con diseño UGR ✅ CORREGIDO
Inicio y Reportes usaban chips con borde/radio10/texto gris y labels largos. Se replicó el diseño UGR en el widget compartido `edan_seccion_badges.dart`: píldoras sin borde, radio 6, fondo `primary@0.08`, texto `primary`, labels de término completo (`Infraestructura`, `Agricultura`, `Población`, `Salud`, `Servicios`, `Educación`, `Vivienda`, `Protección`, `Necesidades`) vía nuevo `seccionesActivasLabelsCortos()` en `edan_secciones_registry.dart`. UGR no se modificó.

### 9.11 Badges del item con flags viejos ✅ CORREGIDO
Causa: los badges usaban los flags compuestos `imp_*` del `datos_json` guardado, que podían quedar viejos respecto a `localidad_secciones_activas` (fuente autoritativa reconstruida en cada pull y mantenida al guardar). El JSON del long press y la vista previa ya resincronizaban desde `localidad_secciones_activas`, por eso el item no mostraba "Agricultura" ni afectaciones/necesidades marcadas aunque el JSON sí. Fix (fuente de verdad única + unión): nuevo `EdanLocalidadesEnvioV2Service.aplicarFlagsDesdeSeccionesActivas(loc, {unionConGuardados})` (lee `leerSeccionesActivas` → `construirFlagsDesdeActivas`; fallback `recalcularFlagsImpacto()`). Con `unionConGuardados: true` (items de Inicio/Reportes) los grupos marcados en page01 se conservan en unión con los derivados de secciones activas, así el badge = GRUPOS de page01. Se aplica en `_cargarLocalidades()` de Inicio (`resp_dashboard_tab.dart`) y Reportes (`resp_edan_localidad_tab.dart`) antes del setState; `_sincronizarFlagsActivas` de la vista previa delega en el mismo método con default (false) para seguir 1:1 con el JSON. `flutter analyze`: solo infos preexistentes.

### 9.12 Mensaje informativo fijo del item RESP ✅ CORREGIDO
El item de Inicio y Reportes mostraba siempre bajo los badges un hint con icono `info_outline`: "La información debe ser enviada cuando esté completa desde la vista previa." (confundía con el estado del item). Se eliminó el bloque `else` fijo en `resp_dashboard_tab.dart` y `resp_edan_localidad_tab.dart`; se conserva el banner condicional de estado (solo en items pendientes de envío): "Listo para enviar..." / "Incompleta..."

### 9.13 Revisión de flujos "Sincronizar" ✅ CORREGIDO (2 bugs)

**Mapa de flujo (entradas)**
- RESP: `resp_screen.dart:309` `_sincronizar({auto})` → guarda `isSyncing` + conectividad → `EdanSyncRespoService.sincronizar()` → refresca tabs + snackbar. `resp_dashboard_tab.dart:305-308` / `resp_edan_localidad_tab.dart:310` escuchan `pendientes`/`sincronizando`.
- UGR rol 6: `ugr_screen.dart:315`, `ugr_dashboard_tab.dart:64,148` → `EdanSyncService.sincronizar()`.
- Login: `auth_provider.dart:112` `recargarEdansMunicipio`; `:117` `recargarLocalidades` (RESP).

**RESP (`edan_sync_respo_service.dart`)** — `sincronizar():44` en 3 fases: F1 fotos (upload antes del push, path disponible en el JSON), F2a `_eliminarPendientes:397` (DELETE server; 403 consolidado conserva la fila; borrado local solo tras OK), F2b `_subirSucios:486` (`needPush = !sincronizado || editado || modificadas`; `procesarColaDeletes` + `eliminarFilasAntesDelPush`; `enviarLocalidadDocumento(skipFotos:true)`; limpia flags y `localidad_seccion_sync`), F3 `_pullDatos:616` (LWW `_esMasNueva`; salta si local dirty `editado||!sincronizado||modificadas`; DELETE server→local solo si `sincronizado`; reemplazo con `reemplazarLocalidadDesdeServer`), F3b `_descargarFotosPendientes:742`. `recargarLocalidades (login):838` baja catálogo + huerfanas.

**UGR rol 6 (`edan_sync_service.dart`)** — `sincronizar():72` = `_pullEdans` (pull cabeceras + localidades con guarda dirty `:140, :33`) → `_pushDeletions` → `_pushEdans` (por localidad vía `enviarLocalidadDocumento(skipFotos:true)`; EDAN sync solo si todas sus localidades OK). `recargarEdansMunicipio:26` con guarda dirty.

**Compartido (`edan_documento_sync_service.dart`)** — `enviarLocalidadDocumento:43` (carrete → `construirDocumento` → POST/PUT `/documento` → bloque `_errores` NO marca OK → persiste `id_edan_localidad`); `procesarColaDeletes:137` (404 se descarta como resuelto; fallo permanece en cola); `eliminarFilasAntesDelPush:208`.

**DB (`database_helper.dart`)** — `markLocalidadAsSyncedConFecha:2548` conserva la fecha del server (autoridad LWW); `reemplazarLocalidadDesdeServer:2711` limpia flags y marca secciones sincronizadas; `sincronizarFlagEditadoCabecera:2583` recalcula `editado` desde tablas.

**BUG 1 — Delete de ítem 1:N offline huérfano ✅ CORREGIDO**
`eliminarItemSeccion` (`edan_dialog_helper.dart:44-99`) borra la fila en SQLite y agrega a `pendientes_eliminar` pero NO marca la localidad (sin `modificada` ni `editado`). El `procesarColaDeletes` solo corría dentro de `_subirSucios` (`edan_sync_respo_service.dart:515`) por cada localidad sucia, y `needPush` podía ser `false` → el DELETE nunca llegaba al server hasta que otra localidad se ensuciara; además el contador no reflejaba la cola.
Fix: (a) en `sincronizar()` la cola se procesa a nivel global al inicio de Fase 2 (antes de `_eliminarPendientes`); se mantiene el in-loop como red de seguridad (no-op). (b) `countLocalidadesPendientesSync` (`database_helper.dart:2429`) ahora cuenta también localidades con filas `sincronizado=0` en `pendientes_eliminar`, sin doblar las de `pendiente_eliminacion=1`.

**BUG 2 — `recargarLocalidades` pisaba ediciones locales al login ✅ CORREGIDO**
El branch `existente != null` (`edan_sync_respo_service.dart:906-918`) sobrescribía cabecera/JSON con el server y `markLocalidadAsSynced` limpiaba `editado`, sin consultar secciones modificadas. Regresión vs legacy (`localidad_sync_service.dart:63-71`). Además `updateLocalidad` grababa `pendiente_eliminacion` desde el objeto del server (false) → cancelaba silenciosamente un borrado local pendiente.
Fix: guarda en login-pull → salta si `editado || !sincronizado || pendienteEliminacion || modificadas.isNotEmpty` (los cambios sin subir van por Fase 2b). Y se reemplazó `markLocalidadAsSynced` (forzaba `fecha_modificacion=DateTime.now()`, inflaba la fecha local y podía enmascarar el LWW de futuras ediciones remotas) por `markLocalidadAsSyncedConFecha` conservando la fecha del server.

**Pendientes / menores (documentados, sin fix)**
- Fotos: F1 sube 1 foto por llamada y relee la tabla completa por localidad (`edan_sync_respo_service.dart` Fase 1); `_descargarFotosPendientes` secuencial, sin retry (ver 9.4).
- Rol 6: sin fase de fotos en `EdanSyncService.sincronizar()` (si el UGR adjuntara fotos offline, no llegarían por el sync central; hoy solo ve/consolida). `result.actualizados++` cuenta aunque el pull salte (`edan_sync_service.dart:148`).
- Dead code (no eliminado): `LocalidadSyncService` (1120 líneas, sin referencias) y `SyncManager` (solo `reset()`/`pendingCountStream`) — candidatos de limpieza futura.

### 9.14 Preview y acciones UGR (rol 6) según estado real ✅ CORREGIDO

**Estados reales verificados** (catálogo servidor `GET /edan/estados` → `catalogo_estados_edan`; doc `CONSOLIDACION_EDAN (3).md` §Estados/§9): `borrador`(1), `enviado_ugr`(2), `aprobado`(3), `rechazado_ugr`(4), `aprobado_ajuste_ugr`(5); la app agrega `en_revision`/`enRevisionUgr`(6) ("En revisión UGR") que ella misma escribe al abrir una enviada (`ugr_localidades_tab.dart:839-848`) → flujo real 2→6→3|4|5. NO existe "Enviado ajuste": `aprobado_ajuste_ugr`(5) es estado aprobado terminal → misma lógica que `aprobado`(3).

- **Confirmación en el item** (`ugr_localidades_tab.dart:354-389`): `_cambiarEstado` ahora muestra AlertDialog (icono check/cancel, `'$accion localidad'`, Cancelar/acción) y solo ejecuta si confirma; valida `idServer != null` y conectividad antes del PUT `/estado`. Los previews ya confirmaban (`edan_preview_resp_screen.dart:_confirmarAccion:394`, `ugr_edan_localidad_preview_screen.dart:_mostrarConfirmacion:34`).
- **Botones del preview según estado** (`edan_preview_resp_screen.dart:_buildUGRButtons:291`): se renderiza por callback individual (`onAprobar`/`onRechazar` ya no exigen la pareja): ambos → `Row`; solo uno → a ancho completo; ninguno → "Cerrar". `ugr_localidades_tab.dart:_verDetalle:851-870` condiciona los callbacks: `aprobadoUgr` **o** `aprobadoAjuste` → `null,null` (sin Aprobar/Rechazar, solo Cerrar); `rechazadoUgr` → solo `onAprobar` (botón único que cambia a `aprobado`(3)); resto (`enRevisionUgr`, `enviadoUgr` offline, `borrador`) → ambos. `_confirmarAccion` usa `?.call()` → funciona con un solo callback.
- **Mensaje informativo del item UGR eliminado** (`ugr_localidades_tab.dart`, build de `_LocalidadCard`): se quitó la fila fija con `Icons.info_outline` + `estado.descripcion` que aparecía debajo de los badges (badge de estado `_buildSmallBadge` + chip "Pendiente"); el badge de estado ya comunica el estado.

**Verificación:** `flutter analyze` 0 errores / 0 warnings; infos preexistentes: `use_build_context_synchronously` en `ugr_localidades_tab.dart:334` y `edan_preview_resp_screen.dart:393`.

### 9.15 Permisos de ejecución del wizard EDAN y reintento de catálogos en registro ✅ CORREGIDO

Dos correcciones pedidas por el usuario:

**A) Permisos de ejecución (cámara + ubicación) del wizard EDAN**
- Problema: el formulario pedía permisos runtime recién al tomar cada foto (hasta 3 peticiones por captura: `capturarCoordenadas`, `LocationService._getLocationByGPS` por cada fix GPS, `capturarFoto`), y si el SO revocaba el permiso en cualquier momento no había re-pedido explícito al abrir el wizard. Los permisos ya estaban declarados en Android (`main/AndroidManifest.xml:3-8`) e iOS (`Info.plist:67-80`), sin necesidad de cambios de config.
- `permission_service.dart`: nuevo `asegurarPermisosFormulario()` → verifica cámara + ubicación (Windows → `true` sin pedir); solicita ÚNICAMENTE los permisos inactivos (los ya concedidos no se vuelven a pedir, `requestCameraPermission:11`/`requestLocationPermission:26` hacen check-antes-de-request) y vuelve a verificar el estado real del sistema en cada llamada → si el SO revoca uno, se re-solicita. **Silencioso**: no muestra diálogo al abrir el wizard; si un permiso queda negado o el GPS está apagado devuelve `false` y el aviso lo presentan los flujos de captura (`edan_boton_sacar_foto.dart:32-38`), que ya mostraban `showPermissionDeniedDialog`.
- `location_service.dart:_getLocationByGPS`: elimina el doble pedido propio de geolocator y delega en `PermissionService.requestLocationPermission()` como única puerta (un solo diálogo por intención).
- `edan_form_wizard.dart:_precargarCatalogo`: llama `asegurarPermisosFormulario(context)` al abrir el wizard (post-frame), así los permisos se solicitan una vez al inicio.

**B) Reintento de catálogos (departamento/provincia/municipio) en Registro de Usuario**
- Problema: `register_screen.dart:39` llamaba `loadGeography()` una sola vez en `initState`; si fallaba, el error era silencioso (`reporte_provider.loadGeography` catch vacío), sin spinner propio y sin forma de reintentar.
- `reporte_provider.dart`: nuevos flags propios `_isLoadingGeografia`, `_geoError`, `_provinciasError`, `_municipiosError` (+ getters `isLoadingGeografia`, `geoError`, `provinciasError`, `municipiosError`); se activan en el `catch` y se limpian al reintentar. El global `isLoading` queda intacto (los demás consumidores no se ven afectados). Registro es siempre en línea → SIN fallback a caché.
- `register_screen.dart` (dropdowns Departamento/Provincia/Municipio): spinner con el flag propio por nivel; si la lista quedó vacía + error + sin carga → `suffixIcon` `IconButton(Icons.refresh)` ("Reintentar cargar …") que re-llama `loadGeography()`/`loadProvincias(id)`/`loadMunicipios(idProv, idDep)` + texto "Sin respuesta. Toca el icono para reintentar." bajo el campo. Provincia/Municipio solo muestran reintento si su dependencia está seleccionada. NO se tocó `forgot_password_screen.dart` (decisión del usuario).

**Verificación:** `flutter analyze` 0 errores / 0 warnings nuevos; sin infos en `permission_service.dart`, `location_service.dart`, `edan_form_wizard.dart`, `reporte_provider.dart`, `register_screen.dart` (los 2 warnings de `ai/asistente_voz_service.dart` son preexistentes y ajenos).

### 9.16 Badge "Agricultura" no visible en items de Localidades (rol 6) ✅ CORREGIDO

Mismo bug que 9.11 en RESP: los badges del ítem UGR se construían solo desde los flags GRUESOS del documento (`ugr_localidades_tab.dart` `_impactosActivos`: `impAgropecuario → 'Agro'`, `impInfraestructura → 'Infra'`). Si el doc traía el flag grueso viejo (`imp_agropecuario: false`) pero la sección agrícola sí tenía datos (`danos_agricultura`/`imp_danos_agricultura: true`), el badge no se mostraba; además los labels no coincidían con el mapeo oficial.

- `edan_localidades_envio_v2_service.dart` `aplicarFlagsDesdeSeccionesActivas`: ahora `base` (flaggruesos) se captura ANTES de las ramas de fallback; los dos fallbacks (`idLocal` nulo/vacío y `activas.isEmpty`) usan `_aplicarUnionDesdeDatos`: `recalcularFlagsImpacto()` (deriva gruesos desde los datos del modelo) + OR con los gruesos previos cuando `unionConGuardados: true`. Con default (`false`) comporta igual que antes → preview/JSON RESP intactos.
- `ugr_localidades_tab.dart`: nuevo `_resincronizarBadges` → para cada localidad `aplicarFlagsDesdeSeccionesActivas(loc, unionConGuardados: true)`, llamado en `_cargarDatos` en la rama online (tras el merge API+pendientes, antes del `sort`/`setState`) y en la offline. El endpoint `/edan/localidades/municipio/{id}` devuelve estructura completa (14 secciones), así el fallback deduce los flags reales (agricultura incluida) y el union conserva page01; si existe fila local, la fuente es `localidad_secciones_activas` (igual que RESP).
- Badge mapeado con el mapeo oficial: en `_buildLocalidadItem` ahora `impactos: EdanSeccionesRegistry.seccionesActivasLabelsCortos(localidad)` (labels completos: `Agricultura`, `Infraestructura`, …). Se eliminó `_impactosActivos` (único call site: 814).

**Verificación:** `flutter analyze` 0 errores / 0 warnings; solo la info preexistente `use_build_context_synchronously` en `ugr_localidades_tab.dart:339`. Fuera de alcance (paralelo, sin tocar): `ugr_edan_tab.dart:142-150` mapea 'Agropecuario' en el resumen de un EDAN (evento), no ítems de Localidades.

### 9.17 Regresión micrófono tras TTS ✅ CORREGIDO

**Problema:** `_isSpeaking` se quedaba atascado en `true` tras `awaitSpeakCompletion()` que podía colgar indefinidamente → el botón de micrófono permanecía gris y no se reactivaba para escuchar tras hacer una pregunta.

**Fix:** `awaitSpeakCompletion(true)` con timeout `clamp(3000, 60000)` en `hablar()` de `asistente_voz_service.dart`. `onStatus` de `initStt` dispara `_activeFin` en `done`/`notListening` para liberar escucha. `_esperarAntesDeEscuchar` reducido de 600ms a 300ms.

**Archivos:** `asistente_voz_service.dart`, `asistente_ia_provider.dart`.

### 9.18 Built-in Kotlin migration / Google Play compatibility 🔍 INVESTIGADO / SIN RESOLVER

**Problema:** `builtInKotlin=false` genera advertencia de Google Play sobre plugin Kotlin legado. `flutter_tts-4.2.5` usa `kotlin-android` legacy sin versión Built-in Kotlin. Migración intentada y **revertida**. `minSdk` cambiado de 28 a 26 para recuperar dispositivos. 5 dispositivos siguen incompatibles (causa probable: `uses-feature` implícitos o ABI filters).

**Estado:** Build compila con `builtInKotlin=false`, `minSdk=26`. Sin resolver sin reemplazar `flutter_tts` por `google_text_to_speech`.

**Archivos:** `android/app/build.gradle.kts`, `android/gradle.properties`, `pubspec.yaml`.

### 9.19 Control interno — Suma de personas ≤ Total Población Afectada ✅ CORREGIDO

**Problema:** Las secciones 03 (grupos etarios), 04 (salud), 07 (unidades educativas) y 10 (protección) permitían registrar valores sin límite, pudiendo superar el `totalPoblacionAfectada` definido en page02. Esto generaba datos inconsistentes y bloqueaba envíos sin advertencia.

**Fix:** Validación hard-block en 3 niveles:
- **Modelo** (`edan.dart`): Propiedades computadas en `EdanLocalidad`: `sumaGruposEtarios`, `sumaSaludPersonal`, `sumaUnidadesEducativas`, `sumaProteccion`.
- **UI**: Banner naranja de advertencia en cada página cuando la suma excede el cap.
- **Validación**: La completitud por datos reales (step indicator "Pendiente" y envío bloqueado si suma > cap) vive en `calcularSeccionesCompletas()` de `edan_resumen_page.dart`, que combina `_seccionTieneDatos0X` (datos reales) con `&& suma <= cap`. El `valida` de `_WizardPage` para pages 03/04/07/10 fue eliminado en §9.21 (antes retornaba `false` solo por cap, sin exigir datos).

**Archivos:** `models/edan.dart`, `edan_page03.dart`, `edan_page04.dart`, `edan_page07.dart`, `edan_page10.dart`, `edan_form_wizard.dart`, `edan_resumen_page.dart`.

### 9.20 Bloqueo de guardado de EDAN vacío ✅ CORREGIDO

**Problema:** El botón de guardar (AppBar) permitía guardar un EDAN sin datos mínimos — sin `nombre` de localidad o sin `tipo de evento` — generando registros vacíos en SQLite que no tenían sentido y contaminaban la base de datos con borradores inválidos.

**Fix:** Se agregó validación en `_guardarSinSalir()` de `_EdanFormWizardState`:
- Se implementó `_esEdanVacio()` que retorna `true` si `nombre.trim().isEmpty || idTipoEvento == null`.
- Si el EDAN está vacío, se muestra un `SnackBar` rojo con el mensaje indicando que debe completar al menos el nombre de la localidad y el tipo de evento, y se retorna sin guardar.
- Se agregó `valida: (l) => l.nombre.trim().isNotEmpty && l.idTipoEvento != null` a la página 'intro' en `_construirPaginas()` para que el step indicator refleje correctamente el estado de completaridad de la primera sección.
- **Nota:** La navegación entre páginas (`_next`) NO está bloqueada — el usuario puede avanzar libremente para revisar, pero no puede guardar un EDAN vacío.

**Archivos:** `edan_form_wizard.dart`, `CORRECCIONES_EXHAUSTIVAS.md`.

### 9.21 Step indicator pintaba secciones de verde solo con flags (sin datos reales) ✅ CORREGIDO

**Problema:** Al marcar un checkbox en page01 (p.ej. `impSalud`, `impPoblacion`, `impEducacion`, `impProteccion`), el step indicator pintaba de verde la sección correspondiente (03, 04, 07, 10) aunque no hubiera ningún dato real ingresado. Dos causas:
1. `_seccionesCompletas()` y `_seccionCompleta()` del wizard usaban el campo `valida` de `_WizardPage`, y en pages 03/04/07/10 ese `valida` era solo la comprobación de cap (§9.19) `suma <= totalPoblacionAfectada`, que es `true` con `0 <= 0` sin datos. Además page01 marcaba completa con `nombre || impPoblacion || impSalud`.
2. `_seccionTieneDatos()` devolvía `true` con solo los flags detallados `imp*` (p.ej. `impImpactoPoblacion || impPrimeraRespuesta`), sin exigir datos en arrays.

**Fix:** Unificación de la completitud en UNA sola fuente canónica (espejo del resumen §9.7):
- Se eliminó el campo `valida` de `_WizardPage` y todos sus usos (dead code).
- Se eliminó `_seccionTieneDatos(key)` (lógica redundante que confiaba en flags).
- `_seccionCompleta(key)` ahora delega en `EdanResumenPage.calcularSeccionesCompletas(_localidad)`, que exige DATOS REALES por sección (+ el hard-block de sumas §9.19 vía `&& suma <= total`). `_seccionesCompletas()` llama a `_seccionCompleta`.
- La página 'intro' conserva su regla §9.20 (nombre + tipo de evento).

**Comportamiento resultante (ambos procedimientos, crear desde cero y entrar a editar un borrador):**
- Crear desde cero: marcar checkboxes en page01 ya no pinta verde ninguna sección; las páginas se pintan verdes solo al ingresar datos reales.
- Entrar a editar: al reabrir, `_sincronizarFlagsDesdeSeccionesActivas()` recarga arrays desde SQLite y `calcularSeccionesCompletas` devuelve verde solo para las secciones que efectivamente tienen datos guardados.
- El botón "Enviar" ya usaba `formularioCompleto()` (misma fuente §9.7), por lo que queda consistente con la vista del step indicator.

**Archivos:** `edan_form_wizard.dart` (el `seccionesCompletas` del resumen y la lógica `_seccionTieneDatos03..11` estaban correctos desde §9.7), `CORRECCIONES_EXHAUSTIVAS.md`.

**Verificación:** `flutter analyze` 0 errores / 0 warnings nuevos (solo infos preexistentes). Los tests que fallan (`api_flow_test.dart`, `proteccion_endpoint_test.dart`) son de serialización `toApiJson()`/`fotografia` del modelo y son preexistentes, ajenos a este cambio.

---

## 10. ARCHIVOS A REVISAR

| Prioridad | Archivo | Motivo |
|---|---|---|
| ALTA | `edan_form_wizard.dart`, `edan_page01.dart`, `auth_service.dart`, `splash_screen.dart`, `reporte_provider.dart`, `edan_sync_respo_service.dart`, `edan_secciones_registry.dart`, `auth_provider.dart` | Núcleo navegación/envío, login, carga, sync |
| MEDIA | `edan_page02/03/04/09`, `edan_resumen_page.dart`, `edan_documento_sync_service.dart`, `edan_localidades_envio_v2_service.dart`, `database_helper.dart` | Secciones 1:N, resumen, envío, persistencia |
| BAJA | `edan_navigation_bar.dart`, `edan_step_indicator.dart`, `edan_wizard_service.dart`, `edan_dialog_helper.dart`, `edan_item_card.dart`, `edan_boton_sacar_foto.dart`, `resp_screen.dart`, `role_router.dart` | UI/soporte |

---

## 11. DEPENDENCIAS

```
main → MultiProvider → AuthProvider → AuthService → ApiService | SecureStorage | SharedPreferences
                     → ReporteProvider → DatabaseHelper | ApiService | SyncManager
                     → ConnectivityProvider → ConnectivityService
Splash → AuthProvider.initialize → _autoLogin → _dispararCargaEdansMunicipio → EdanSyncRespoService.recargarLocalidades
RespScreen → ReporteProvider.initialize + EdanSyncRespoService.sincronizar (al recuperar conexión)
EdanFormWizard → EdanLocalidad | EdanSeccionesRegistry | DatabaseHelper | EdanLocalidadesEnvioV2Service | EdanDocumentoSyncService | EdanSyncRespoService | ConnectivityService
```

---

## 12. COMANDOS ÚTILES

```powershell
cd D:\CLIMBAT\OpenCodeProyect\APP_REA\REA
flutter analyze
flutter build apk --debug / windows --release
flutter run -d windows / -d <device_id>
flutter clean
```

---

## 13. ASISTENTE IA CON VOZ (RAG)

> Nuevo feature de esta sesión: reemplazo del asistente de llenado EDAN por un chatbot RAG con voz (STT/TTS) + texto, conectado al MotorIA.

### 13.1 Arquitectura

Flujo: usuario habla o escribe → `asistente_ia_service.dart` → `POST {ApiConfig.ragBaseUrl}/chat` → SSE stream de tokens → respuesta token-a-token en el bottom sheet.

| Capa | Archivo | Responsabilidad |
|---|---|---|
| **API** | `lib/services/ai/asistente_ia_service.dart` | `chatStream()`, `chat()` con params; parsing SSE |
| **Estado** | `lib/providers/asistente_ia_provider.dart` | Saludo contextual, toggle voz/texto, `_stripMarkdown()`, flujo de escucha |
| **TTS/STT** | `lib/services/ai/asistente_voz_service.dart` | `_tts.speak()` + `awaitSpeakCompletion(true)`; `SpeechToText` escucha |
| **UI** | `lib/widgets/asistente_ia.dart`, `lib/widgets/asistente_ia/asistente_ia_bottom_sheet.dart`, `lib/widgets/asistente_ia/asistente_ia_fab.dart` | Bottom sheet, FAB, toggle |

### 13.2 API — MotorIA

| Parámetro | Valor |
|---|---|
| Endpoint | `POST {ApiConfig.ragBaseUrl}/chat` |
| `pregunta` | Texto del usuario, SIN prefijos (limpio). El contexto de sección va en `termino`. |
| `limite` | `15` (solo chat global, sin `grupo_id`) |
| `max_tokens` | `700` |
| `grupo_id` | `2` (opcional, filtra por grupo documental) |
| `termino` | Nombre de la sección/pantalla (solo con `grupo_id`; p.ej. `"Datos Generales"`) |
| Header | `X-API-Key` (opcional) |

**Errores antes del stream (JSON):**
- `404 {"detail":"Grupo no encontrado"}` → `grupo_id` inválido.
- `400 {"detail":"El grupo no tiene documentos"}` → grupo vacío.
- El cliente extrae `detail` y lo incluye en el error (`Error MotorIA 404: Grupo no encontrado`).

**SSE:** líneas `data: {"type":"token","content":"..."}` hasta `data: {"type":"done","fuentes":[...]}`. Las fuentes se muestran en el chat en una tarjeta expandible (ver §13.9).

### 13.3 Modo voz / texto

- **Toggle persistente:** `SharedPreferences` key `asistente_voz_habilitada`, default `true`.
- **Activación por voz:** al habilitar, el sistema **habla el saludo** (por hora + nombre via `split(' ').first` + `contextoPantalla`). Si hay conversaciones previas, habla `"Haz tu pregunta."`. Luego escucha automáticamente (300ms espera).
- **Modo texto:** micrófono oculto; sin escucha automática por voz.
- **Banner de silencio:** aparece `"Presiona para volver a hablar"` cuando `_intentosVacios >= 2`.

### 13.4 TTS — Detalles técnicos

- `_tts.speak()` con `awaitSpeakCompletion(true)` + timeout `clamp(3000, 60000)` para evitar que `_isSpeaking` se atasque.
- `onStatus` de `initStt` dispara `_activeFin` en `done`/`notListening` para liberar la escucha.
- `_stripMarkdown()` elimina: negrita, cursiva, headers, viñetas (`-`, `*`, `•`, `+`), listas numeradas (`1.`, `1)`), checkboxes (`[ ]`, `[x]`), blockquotes, links, código inline, tachado, tablas.
- `_obtenerNombreUsuario()` usa `split(' ').first` (solo primer nombre).

### 13.5 AsistenteIaFormFab

Widget reutilizable insertado en `edan_form_wizard.dart`:
- Posicionado `Positioned(bottom: 80, right: 16)`.
- `_grupoId = 2` → filtra las fuentes RAG por el grupo documental EDAN (`grupo_id`).
- Muestra saludo contextual basado en `pageTitle` / `pageKey` de la página actual del wizard.
- Abre el bottom sheet del Asistente IA con contexto de sección.

### 13.6 Built-in Kotlin

- **`minSdk 28 → 26`** para recuperar dispositivos excluidos por versiones anteriores de Android.
- **`builtInKotlin=false`** (revertido): `flutter_tts-4.2.5` usa `kotlin-android` legacy y no tiene versión Built-in Kotlin. La migración completa está **bloqueada** — alternativa: reemplazar por `google_text_to_speech`.
- Build compila: `flutter build apk --debug` sin errores.

### 13.7 Filtro por grupo documental (`grupo_id: 2`)

El asistente vinculado al wizard EDAN (`AsistenteIaFormFab`) enviaba antes `documento_ids: [21]` (documento suelto). Ahora envía `grupo_id: 2` (grupo documental completo) con `termino` de sección:

```json
{
  "pregunta": "<texto del usuario>",
  "max_tokens": 700,
  "grupo_id": 2,
  "termino": "Datos Generales"
}
```

- `AsistenteIaFormFab._grupoId = 2` y `contextoPantalla: pageTitle` → `AsistenteIAProvider(grupoId: ..., contextoPantalla: ...)` → `AsistenteIAService._buildBody(pregunta, grupoId, termino)`.
- Cuando `grupoId == null` (asistente global sin wizard) se sigue enviando `limite: 15`; sin `grupo_id`, sin `termino` ni `llm_externo`.
- **Regla estricta:** nunca se envían `"grupo_id": 0` ni `"termino": "string"`. `grupo_id` solo aparece si es un entero `> 0` (el FAB genérico de Inicio/Navegación crea `AsistenteIAProvider()` sin grupo → el body queda solo `{pregunta, max_tokens, limite}`). `termino` solo se incluye cuando hay `grupo_id` válido y texto no vacío.
- `chatStream()` y `chat()` del service usan los mismos parámetros por consistencia.

### 13.8 Contexto de sección como `termino`

El asistente vinculado al wizard envía la sección actual en el campo `termino` (NO concatenada a la pregunta):

```json
{
  "pregunta": "<texto del usuario>",
  "max_tokens": 700,
  "grupo_id": 2,
  "termino": "<pageTitle>"
}
```

- `termino` = `page.titulo` (p.ej. `"Datos Generales"`, `"Impacto en viviendas"`) pasado vía `AsistenteIaFormFab.contextoPantalla` → `AsistenteIAProvider.contextoPantalla` → `chatStream(termino: contextoPantalla)`.
- **Regla backend:** `termino` solo se aplica si va con `grupo_id`; sin `grupo_id` se ignora (chats normales intactos). Si `termino` no coincide con ninguna sección, cae a la búsqueda normal del grupo (fallback, no falla).
- `pregunta` se envía **limpia** (solo el texto del usuario); el saludo visible del bottom sheet sí muestra la sección, pero no va en el payload.
- `_ultimaPreguntaFallida` conserva el texto original; al reintentar se re-envía con el mismo `termino`.

### 13.9 Documentos de referencia (fuentes)

El evento `done` del SSE de `/chat` trae un array `fuentes` y un mapa `citas`:

```json
{
  "documento_id": 21,
  "titulo": "Ley Nº 28611 — Ley General del Ambiente",
  "tipo": "Ley",
  "prioridad": 1,
  "numerals": ["Artículo 72", "Artículo 73"],
  "similitud": 0.98,
  "numerals_truncados": true
}
```

```json
"citas": {
  "1": {"documento_id": 14, "titulo": "Comité de Operaciones", "numeral": "Artículo 72 (parte 4)"},
  "5": {"documento_id": 7, "titulo": "Unidad de gestión de riesgos municipal", "numeral": "Artículo 22"}
}
```

**Flujo en la app:**
- `AsistenteIAService.chatStream()` recibe callbacks `onFuentes` y `onCitas`: al llegar `type == 'done'` parsea `fuentes` y `citas` (claves string → `AsistenteCita` con documentoId/titulo/numeral) y los invoca.
- `AsistenteIAProvider.enviarPregunta()` los captura y adjunta al mensaje del asistente: `AsistenteChatMessage(role: 'assistant', content: ..., fuentes: [...], citas: {...})`. Mensajes de error no llevan metadatos.
- Modelo: `lib/models/ai/asistente_chat_message.dart` define `AsistenteFuente`, `AsistenteCita` y `AsistenteChatMessage` con `fuentes` (`List<AsistenteFuente>?`) y `citas` (`Map<String, AsistenteCita>?`).

**UI (bottom sheet):** debajo de cada respuesta IA (mensajes terminados, no el que streamea) se muestra una tarjeta **colapsada por defecto** "Referencias (N)":
- Header: `Icons.description_outlined` + contador + flecha para expandir/colapsar (chevron). Pegada a la burbuja de la respuesta.
- Al expandir (máx. 220px, scroll): cada fuente es un ítem con **número en círculo**, título (negrita, 2 líneas), `tipo` + numerales citados, badge verde de similitud `(similitud * 100).round()`%, y fila morada `Cita: <numeral>` cuando el `documento_id` coincide con una `citas` del `done`.
- Solo información: no abre ni descarga el documento.

**Citas en el texto de la respuesta:** al renderizar el markdown se expanden los marcadores `[N]` del LLM con `_expandirCitas()` (regex `\[(\d+)\]`): si `citas[N]` existe → `[<documento_id>] <titulo> (<numeral>)` (mantiene el marcador `[·]` visible para guiar hacia el listado numerado); si no existe, se deja `[N]` tal cual. El copiado conserva el texto original con `[N]` sin expandir. Durante el streaming (aún sin `done`) se muestra el texto crudo y se expande al recibir las citas.

**Acciones por mensaje (dentro del contenedor de la respuesta):** fila de iconos dentro del fondo de la burbuja gris — copiar, voz (si `soportaVoz`) y reintentar (solo en error, `Icons.refresh` rojo). El timeout del provider pasó de 30s a **90s** (señal lenta); el `request.send()` del service cubre solo conexión/headers (60s), el límite real del chat lo marca el provider.

---

> **Este archivo se actualizará conforme se identifiquen y corrijan problemas.