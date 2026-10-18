# Diagramas de la app REA (Flutter)

Carpeta de diagramas en Markdown (Mermaid) para analizar visualmente el funcionamiento de la app `APP_REA/REA`. Cada documento traza un flujo concreto **leyendo el código real** (cita archivo y línea en cada paso), de modo que sirva como herramienta de análisis y no como documentación decorativa.

Cada documento traza un flujo concreto (inicio de sesión y registro de un rol, creación de un EDAN local, etc.), con las descargas que ocurren después (catálogos, localidades, fotos e histórico, según corresponda).

## Cómo verlos

Los diagramas usan sintaxis [Mermaid](https://mermaid.js.org/). Se renderizan automáticamente en:
- GitHub / GitLab (al abrir el `.md`)
- VS Code con la extensión *Markdown Preview Mermaid Support*
- Any editors que soporten Mermaid en Markdown

## Índice de documentos

| # | Documento | Flujo que cubre | Estado |
|---|---|---|---|
| 01 | [Rol 7 (RESP): inicio de sesión y registro](01_rol7_resp_sesion_y_registro.md) | Registro de usuario nuevo (rol 7); inicio de sesión y auto-login; descargas posteriores: catálogos, localidades y fotos (propias, bajadas a local). | ✅ |
| 02 | [Rol 6 (UGR): inicio de sesión y EDAN local](02_rol6_ugr_sesion_y_registro.md) | Inicio de sesión y auto-login (token expira a 3 días); registro in-app inexistente; descargas tras el login (catálogos, estados, histórico del municipio) y la pestaña **Localidades**: crear/editar EDAN local con el wizard "Formulario EDAN" + SQLite V2, recuperación de los reportes **propios** (con fotos) y fotos del municipio **online**. | ✅ |
| 03 | [El botón de guardar y la sincronización](03_boton_guardar_y_sincronizacion.md) | Qué hace (y qué **no** hace) el **botón de guardar** del wizard "Formulario EDAN" (solo escribe en SQLite local; no sube) y **cuándo** se guarda; si la **sincronización** es **automática o manual** (es **ambas**); cuándo se **habilita** el botón Sincronizar (conectividad); y el **ciclo de vida de las fotos** multi-sección + la **máquina de estados de la cola** (qué se reintenta y qué no). | ✅ |
| 04 | [Wizard "Formulario EDAN": SQLite, guardar y sincronizar](04_wizard_edan_sqlite_guardar_sincronizar.md) | Recorrido del wizard contra SQLite: **crear nuevo vs. editar**, tablas V2 (`formularios`/`filas_seccion`/`viviendas`/`cola_*`), **botón de guardar** y sus disparadores, **botón de sincronizar** (habilitación + fases del motor) y **crear y enviar**. Diagramas y tablas. | ✅ |
| 05 | [Wizard EDAN: mostrar y recoger datos (crear · editar · visualizar) + flags `true`/`false`](05_wizard_crear_editar_visualizar_flags_api.md) | Cómo el wizard **muestra** y **recoge** datos en los tres recorridos: **crear** un formulario nuevo, **editar** un borrador y **visualizar** al tocar el ítem del listado. Mapeo completo **grupos (page01) → rutas v2 → 22 flags `imp_*`**, el **pull/push** contra la API v2 y los fixes del bug "lo `true` no se mostraba". Diagramas y tablas. | ✅ |

## Convenciones

- Diagramas en español, con nombres de métodos/variables en el idioma original del código.
- Cada paso importante cita `archivo.dart:línea`.
- Los problemas/riesgos se marcan con ⚠ y se listan en la sección de observaciones.
- Un documento = un flujo o tema; nada de páginas monolíticas.
