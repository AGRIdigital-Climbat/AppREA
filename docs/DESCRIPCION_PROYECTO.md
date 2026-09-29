# Sistema REA – Evaluación de Daños y Análisis de Necesidades (EDAN)

Aplicación móvil multiplataforma desarrollada en Flutter para el levantamiento,
registro y sincronización de reportes de daños por eventos adversos (SINAGER-SAT / VIDECI).

**Versión:** 1.0.10+10
**Plataformas:** Android (API 28+), iOS, Windows (escritorio)
**Backend:** `https://api.climbat.net/api/v2`
**Base de datos local:** SQLite v29 (25+ tablas)

---

## 1. Desarrollo de la aplicación móvil

Aplicación nativa construida con Flutter para Android e iOS, con soporte adicional
para Windows (escritorio). Permite a los Responsables Locales (rol RESP) y a las
Unidades de Gestión de Riesgos (rol UGR) realizar levantamientos de daños en campo,
gestionar localidades afectadas y sincronizar reportes con el servidor central.

### Roles diferenciados

| Rol | Perfil | Función principal |
|-----|--------|-------------------|
| **RESP** (Responsable Local) | Rol 7 | Levantamiento de daños en campo, creación de localidades por comunidad |
| **UGR** (Unidad de Gestión de Riesgos) | Rol 6 | Revisión, aprobación/rechazo, consolidación municipal y envío del EDAN final |

### Módulos de la plataforma

| Módulo | Estado | Descripción |
|--------|--------|-------------|
| **EDAN** | Activo | Evaluación de Daños y Análisis de Necesidades |
| **RIDA** | Pendiente | Registro de Información de Daños |
| **SIN-B** | Pendiente | Sistema de Información Nacional B |

### Funcionalidades de autenticación

| Funcionalidad | Descripción |
|---------------|-------------|
| Auto-login | Sesión persistente via `flutter_secure_storage`; el splash verifica credenciales al iniciar |
| Registro | Formulario con nombre, carnet, celular, comunidad, cargo y correo |
| Recuperación de contraseña | Endpoint `POST /auth/forgot-password` |
| Router por roles | Cada rol (RESP/UGR) accede a un conjunto diferente de pantallas y permisos |

---

## 2. Funcional en modo offline, para zonas sin conectividad

El sistema funciona completamente sin conexión a internet. Los datos se almacenan
localmente en SQLite y se sincronizan bidireccionalmente al recuperar conectividad.

### Base de datos local (SQLite v29)

#### Tablas principales

| Tabla | Descripción |
|-------|-------------|
| `localidades_offline` | Localidades/comunidades creadas por el RESP (PK: UUID `id_local`) |
| `edans_offline` | EDANs consolidados guardados localmente |
| `reportes_offline` | Reportes individuales con estado de sincronización |
| `borradores` | Borradores de formularios incompletos para reanudación |
| `foto_pendiente` / `foto_pendiente_v2` | Cola de fotos pendientes de subir/descargar |
| `pendientes_eliminar` | Cola de eliminaciones offline pendientes de procesar |
| `sincronizaciones` | Historial de sincronizaciones (fecha, enviados, fallidos) |
| `localidad_seccion_sync` | Tracking de sincronización por sección |
| `localidad_secciones_activas` | Secciones activas por localidad |
| `municipio_geojson` | GeoJSON de municipios para mapas offline |
| `config` | Pares clave-valor de configuración local |

#### Tablas de las 14 secciones del EDAN

| # | Tabla SQLite | Tipo | Campos clave |
|---|---|---|---|
| 01 | `seccion_impacto_poblacion` | 1:N | id_grupo_etario, rango, fallecidos, heridos, desaparecidos |
| 02 | `seccion_salud_establecimientos` | 1:N | nombre_establecimiento, comunidad, dano_parcial/total, medicos_afectados, coordenada_lat/lon, fotografia |
| 03 | `seccion_danos_viales` | 1:N | via, puente, tramo, km_danio, coordenada_lat/lon, fotografia |
| 04 | `seccion_danos_infra_publica` | 1:N | comunidad, tipo_estructura, dano_parcial/total, coordenada_lat/lon, fotografia |
| 05 | `seccion_servicios_basicos` | 1:N | tipo, dano_parcial/total, coordenada_lat/lon, fotografia |
| 06 | `seccion_unidades_educativas` | 1:N | nombre_establecimiento, comunidad, dano_parcial/total, suspension_clases, funciona_albergue, estudiantes/profesores/administrativos, coordenada_lat/lon, fotografia |
| 07 | `seccion_danos_vivienda` | 1:N | comunidad, dano_parcial/total, coordenada_lat/lon, fotografia |
| 08 | `seccion_danos_agricultura` | 1:N | id_cultivo, tipo_cultivo, hectareas_afectadas/perdidas, coordenada_lat/lon, fotografia |
| 09 | `seccion_danos_pecuarios` | 1:N | id_especie, especie, raza, animales_afectados/muertos, coordenada_lat/lon, fotografia |
| 10 | `seccion_infra_productiva` | 1:N | tipo, dano_parcial/total, coordenada_lat/lon, fotografia |
| 11 | `seccion_proteccion` | 1:N | id_grupo_vulnerable, mujeres, hombres, total, apoyo_psicologico, reposicion_documentos |
| 12 | `seccion_primera_respuesta` | 1:1 | busqueda, salvamento, evacuacion |
| 13 | `seccion_necesidad_salud` | 1:1 | numero_personas, otras_necesidades |
| 14 | `seccion_necesidad_humanitaria` | 1:1 | alimentos, refugio_vivienda, ropa_cama, articulos_higiene/cocina, prendas_vestir, herramientas, almacenamiento_agua, banos |

> Las secciones 1:N permiten múltiples registros (ej: varios establecimientos de salud
> dañados). Las secciones 1:1 son un solo registro por localidad.

#### Columnas comunes de sincronización (todas las tablas de secciones)

```sql
editado INTEGER DEFAULT 0,
marcado_borrar INTEGER DEFAULT 0,
insertada_en_server INTEGER DEFAULT 0,
fecha_modificacion_local TEXT
```

#### Catálogos sincronizados offline

| Tabla catálogo | Contenido |
|----------------|-----------|
| `catalogo_departamentos` | Departamentos de Bolivia (codigo_ine, nombre) |
| `catalogo_provincias` | Provincias por departamento |
| `catalogo_municipios` | Municipios por provincia |
| `catalogo_estados_edan` | Estados del flujo EDAN |
| `catalogo_tipos_evento` | Tipos de evento adverso |
| `catalogo_tipo_localidad` | Tipos de localidad |
| `catalogo_cultivos` | Catálogo de cultivos (nombre, grupo) |
| `catalogo_pecuario_grupos` | Grupo de especies pecuarias |
| `catalogo_grupo_vulnerable` | Grupos vulnerables (mujeres, niños, adultos mayores, etc.) |
| `catalogo_grupo_etario` | Grupos etarios para impacto de población |
| `catalogo_estados` | Estados genéricos |
| `catalogo_categorias` | Categorías de daño |
| `catalogo_tipos_repositorio` | Tipos de documento del repositorio |

### Sincronización bidireccional

| Operación | Descripción |
|-----------|-------------|
| **Pull** | Descarga EDANs y localidades del servidor con todas sus secciones (14 por localidad) |
| **Push** | Envía cambios locales pendientes (reportes, secciones, fotos) |
| **Delete** | Procesa eliminaciones pendientes desde la cola `pendientes_eliminar` |
| **LWW** | Resolución de conflictos por timestamp (Last Writer Wins); no se pisan cambios locales no sincronizados |

### Colas de pendientes

| Cola | Tabla | Función |
|------|-------|---------|
| Fotos a subir | `foto_pendiente_v2` | Imágenes capturadas pendientes de envío al servidor |
| Fotos a descargar | `foto_pendiente_v2` | Imágenes del servidor pendientes de descarga local |
| Eliminaciones | `pendientes_eliminar` | Registros marcados para borrado offline |
| Borradores | `borradores` | Formularios incompletos guardados para reanudación |

### Detección de conectividad

| Capacidad | Descripción |
|-----------|-------------|
| Monitoreo continuo | `connectivity_plus` con verificación HTTP real contra el backend |
| Polling | Cada 15 segundos con tolerancia a fallos (3 fallos consecutivos antes de marcar desconectado) |
| Sincronización automática | Al reconectar la red, se ejecuta pull/push automáticamente |
| Indicador visual | Badge "En línea" (verde) / "Sin conexión" (rojo) en la barra de navegación |

---

## 3. Android/iOS para levantamiento de datos en campo con georreferenciación

Aplicación móvil para captura directa en terreno, con levantamiento parcial por
comunidades y georreferenciación de cada punto de daño.

### Levantamiento por comunidades

| Aspecto | Descripción |
|---------|-------------|
| Registro independiente | Cada localidad/comunidad es un registro independiente en `localidades_offline` (UUID como PK) |
| Creación | El RESP crea localidades individuales por comunidad; cada una lleva sus 14 secciones del EDAN |
| Consolidación | El UGR consolida localidades aprobadas del mismo tipo de evento en un EDAN municipal |
| Consolidación manual | Selección de múltiples localidades aprobadas (`POST /edan/consolidar`) |
| Consolidación automática | El sistema agrupa automáticamente por tipo de evento (`POST /edan/consolidar/auto`) |
| Reversibilidad | La consolidación puede deshacerse (`PUT /edan/{id}/deshacer`) |

#### Estados de una localidad

| ID | Estado | Descripción |
|----|--------|-------------|
| 1 | Borrador | En proceso de construcción por el RESP |
| 2 | Enviado UGR | Enviado a la UGR para revisión |
| 3 | Aprobado UGR | Validado y aprobado por la UGR |
| 4 | Rechazado UGR | Rechazado; revisar observaciones |
| 5 | Aprobado con ajuste | Aprobado con correcciones menores |
| 6 | En revisión UGR | Abierto por la UGR para verificar |

### Formulario EDAN multi-sección (14 secciones)

El formulario se presenta como un wizard de varias páginas con validación por sección,
borrador automático y vista previa antes de enviar. Cada sección se guarda
independientemente en su tabla SQLite.

| # | Sección | Tipo | Georreferenciada | Con fotografía |
|---|---------|------|:----------------:|:--------------:|
| 01 | Impacto de población | 1:N | - | - |
| 02 | Salud y establecimientos | 1:N | Si | Si |
| 03 | Daños a vías y puentes | 1:N | Si | Si |
| 04 | Daños a infraestructura pública | 1:N | Si | Si |
| 05 | Servicios básicos | 1:N | Si | Si |
| 06 | Unidades educativas | 1:N | Si | Si |
| 07 | Daños a viviendas | 1:N | Si | Si |
| 08 | Daños a agricultura | 1:N | Si | Si |
| 09 | Daños a pecuarios | 1:N | Si | Si |
| 10 | Infraestructura productiva | 1:N | Si | Si |
| 11 | Protección | 1:N | - | - |
| 12 | Necesidad de primera respuesta | 1:1 | - | - |
| 13 | Necesidad de salud | 1:1 | - | - |
| 14 | Necesidad humanitaria | 1:1 | - | - |

### Georreferenciación

| Capacidad | Implementación |
|-----------|----------------|
| GPS en tiempo real | `geolocator` con alta precisión para captura de coordenadas en campo |
| Georreferenciación por sección | Cada sección del EDAN (02-10) tiene `coordenada_lat` y `coordenada_lon` en SQLite |
| Fotos georreferenciadas | Cada foto capturada incluye lat/lon del momento de la toma (tabla `foto_pendiente_v2`) |
| Mapa interactivo | `flutter_map` con clustering (`flutter_map_marker_cluster`), filtrado por sección, polígono GeoJSON municipal, vista satelital/callejera, popup con detalles y fotos |
| Geocodificación | Resolución inversa de coordenadas a direcciones (`geocoding`) |
| Soporte offline | GeoJSON de municipios descargado y almacenado en SQLite (`municipio_geojson`) |

---

## 4. Repositorio de documentos y firma digital

Cada EDAN tiene asociado su propio repositorio de documentos. La aplicación permite
subir, gestionar, validar y descargar documentos PDF vinculados a cada localidad/EDAN.

### Capacidades del repositorio

| Capacidad | Descripción |
|-----------|-------------|
| Subida de documentos PDF | Archivo + metadatos (nombre, tipo, fecha, observaciones) vinculados a un EDAN |
| Validación de firma digital | Análisis automático al subir: estado, firmante, checks de integridad |
| Badge de estado | Indicador visual por documento: "Firmado" (verde) o "Sin firma" (naranja) |
| Descarga y apertura | PDF descargado y abierto con el visor del dispositivo (`open_filex`) |
| Eliminación | Lógica (soft delete) y física (hard delete) |
| Búsqueda y filtros | Por tipo de documento, texto libre, rango de fechas, departamento/provincia/municipio |

### Flujo de subida y validación de firma

1. El usuario selecciona un archivo PDF (solo extensión `.pdf`).
2. Completa los metadatos: nombre del documento, tipo de documento (catálogo), observaciones.
3. Si el PDF es menor a 20 MB, la app lo envía en base64 al endpoint
   `POST /api/v2/firma-digital/validar-pdf` para validar si contiene firma digital.
4. Se muestra un diálogo con el resultado de la validación:
   - **Estado:** Firma válida / Revisar firma / Sin firma
   - **Datos del firmante:** Nombre, CI/NIT, cargo, organización, correo electrónico
   - **Fecha de firma**
   - **Checks de integridad:** No modificado, cadena de confianza, firmado durante vigencia, sello de tiempo
   - **Hash del documento**
5. El usuario confirma la subida (el documento se sube tanto si tiene firma como si no).
6. El documento se asocia al EDAN y queda visible en el repositorio con su badge de estado.

### Estados de firma por documento

| Badge | Color | Significado |
|-------|-------|-------------|
| Firmado | Verde | El PDF contiene firma digital válida verificada |
| Sin firma | Naranja | El PDF no contiene firma digital |

### Información mostrada por documento en el repositorio

| Campo | Descripción |
|-------|-------------|
| Nombre del documento | Nombre asignado por el usuario |
| Tipo de documento | Categoría del catálogo de tipos de repositorio |
| Fecha del documento | Fecha de creación/modificación del documento |
| Estado de firma | Badge verde "Firmado" o naranja "Sin firma" |
| Acciones | Ver firma, abrir documento, descargar PDF |

### Información detallada de la firma (diálogo)

| Campo | Descripción |
|-------|-------------|
| Estado | "Firma válida" / "Revisar firma" |
| Firmante | Nombre completo del firmante |
| CI/NIT | Cédula de identidad o NIT del firmante |
| Cargo | Cargo institucional del firmante |
| Organización | Entidad a la que pertenece |
| Correo electrónico | Email del firmante |
| Fecha de firma | Fecha y hora de la firma |
| No modificado | Boolean: el documento no fue alterado después de firmar |
| Cadena de confianza | Boolean: el certificado es válido en la cadena de confianza |
| Firmado durante vigencia | Boolean: el certificado estaba vigente al momento de firmar |
| Sello de tiempo | Boolean: la firma incluye sello de tiempo |
| Hash | Código hash del documento para verificación de integridad |
| Fecha de validación | Fecha en que se realizó la validación |

### Endpoints del repositorio

| Método | Endpoint | Función |
|--------|----------|---------|
| GET | `/repositorio/tipos` | Listar catálogo de tipos de documento |
| GET | `/repositorio/edan/{id}/documentos` | Documentos asociados a un EDAN |
| POST | `/repositorio/edan/{id}/documentos` | Subir documento PDF (multipart) |
| GET | `/repositorio/documentos/filtrar` | Filtrar por departamento, provincia, municipio, tipo, fecha, nombre |
| GET | `/repositorio/documentos/buscar?q=` | Búsqueda por texto libre |
| GET | `/repositorio/documentos/{id}/descargar` | Descarga binaria del PDF |
| GET | `/repositorio/documentos/{id}` | Detalle de un documento |
| DELETE | `/repositorio/documentos/{id}` | Eliminación lógica |
| DELETE | `/repositorio/documentos/{id}/hard` | Eliminación física |

### Tabla de catálogo de tipos de repositorio

```sql
CREATE TABLE catalogo_tipos_repositorio (
  id_tipo_documento INTEGER PRIMARY KEY,
  codigo TEXT NOT NULL,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  orden INTEGER DEFAULT 0,
  activo INTEGER DEFAULT 1,
  extensiones_permitidas TEXT DEFAULT 'pdf',
  tamano_maximo_bytes INTEGER DEFAULT 52428800  -- 50 MB
);
```

---

## 5. Interoperabilidad y backend

### Backend centralizado

**API REST** (`https://api.climbat.net/api/v2`) con los siguientes módulos:

| Módulo | Endpoints | Función |
|--------|-----------|---------|
| Auth | `/auth/login`, `/auth/register`, `/auth/forgot-password` | Autenticación y gestión de usuarios |
| EDAN | `/edan/`, `/edan/{id}`, `/edan/consolidar`, `/edan/estado` | CRUD de EDANs, consolidación y estados |
| Localidades | `/edan/localidades`, `/localidades/documento` | CRUD de localidades (flujo "todo-en-uno") |
| Repositorio | `/repositorio/` | Gestión de documentos PDF asociados a EDANs |
| Firma Digital | `/firma-digital/validar-pdf` | Validación de firmas digitales en PDFs |
| Upload | `/upload`, `/foto/subir` | Subida de fotos y archivos multimedia |
| Catálogos | `/edan/tipo-evento`, `/edan/estados`, `/edan/grupo-vulnerable`, `/edan/grupo-etario` | Catálogos de referencia |
| Usuarios | `/usuarios/` | Gestión de usuarios |

### Flujo de consolidación EDAN

```
RESP (campo)                    UGR (municipal)
─────────────                   ───────────────
Crear localidad
  → Borrador
       │
Enviar a UGR ─────────────────→ Recibir
  → Enviado UGR                   │
                                  ├─ Revisar y Aprobar → Aprobado UGR
                                  │                         │
                                  ├─ Revisar y Rechazar     │
                                  │   → Rechazado UGR       │
                                  │                         │
                                  │   ← (el RESP corrige y reenvía)
                                  │
Consolidar (×N aprobadas) ←─────┤
  → EDAN municipal                │
       │                          │
Enviar EDAN ───────────────────→ Recibir EDAN consolidado
                                  │
                              Nivel nacional
```

### Modelo de documento "todo-en-uno"

Cada localidad se sincroniza como un documento compacto que incluye:

| Componente | Contenido |
|------------|-----------|
| Datos generales | Municipio, evento, fechas, población afectada/familias |
| 14 secciones EDAN | Arrays/objetos JSON (11 secciones 1:N + 3 secciones 1:1) |
| Flags de impacto | 22 booleanos `imp_*` que indican qué secciones tienen datos |
| Fotos | Subidas previamente al servidor; referenciadas por sección |
| Metadatos | Fecha de modificación, estado de sincronización, intentos de envío |

### Módulos pendientes

- **RIDA** (Registro de Información de Daños): Módulo definido pero pendiente de implementación.
- **SIN-B** (Sistema de Información Nacional B): Módulo definido pero pendiente de implementación.

---

## 6. Manual interactivo

El sistema incluye tres capas de ayuda contextual para orientar al usuario en el
llenado de formularios y la gestión de reportes.

### Guía asistente animada (TutorialGuide)

| Característica | Descripción |
|----------------|-------------|
| Personaje animado | Figura con burbuja de ayuda contextual que aparece al lado del formulario |
| Invocación | Botón "Ayuda" (azul) en el encabezado de cada página del wizard EDAN |
| Contenido | Texto y consejos específicos por sección, editables en el wizard |
| Animación | Entrada secuencial: personaje primero, burbuja después con efecto de escala |
| Cierre | Tap fuera, botón X, o tiempo configurable |

### Asistente IA integrado

| Característica | Descripción |
|----------------|-------------|
| Acceso | Botón flotante (FAB) accesible desde cualquier pantalla |
| Modo de respuesta | Streaming en tiempo real (SSE) token por token |
| Fallback | Búsqueda por similitud (RAG) en documentos normativos del motor IA |
| Fuentes | Muestra documentos de referencia consultados |
| Ejemplos | "¿Qué datos lleva la sección de salud?", "¿Qué es un damnificado?", "¿Cómo envío el reporte al UGR?" |

### Guías por rol

| Rol | Contenido de la guía |
|-----|----------------------|
| **RESP** | Ciclo del EDAN en 5 pasos, tips de fotografía georreferenciada, acceso al asistente IA |
| **UGR** | Proceso de gestión en 5 pasos, checklist "Verificar antes de enviar" (11 items), guía detallada por cada sección del EDAN (qué llenar, pasos, consejos, ejemplos, indicador de obligatorio/opcional), gestión de localidades, biblioteca de documentos normativos descargables |

---

## 7. Dashboard y monitoreo

### Dashboard del RESP

Panel principal del Responsable Local con indicadores de su área de trabajo:

| Indicador | Descripción |
|-----------|-------------|
| Total localidades | Cantidad total de localidades creadas por el RESP |
| Sin consolidar | Localidades huérfanas (sin EDAN asociado) |
| Enviadas UGR | Localidades enviadas a la UGR para revisión |
| Aprobadas | Localidades aprobadas por la UGR |
| Rechazadas | Localidades rechazadas por la UGR |

Incluye actividad reciente con badges de secciones activas (`EdanSeccionBadges`) e
indicador de completitud del formulario.

### Dashboard del UGR

Panel principal de la Unidad de Gestión de Riesgos con indicadores municipales:

| Indicador | Descripción |
|-----------|-------------|
| Localidades pendientes | Localidades en estado de revisión |
| Aprobadas | Localidades aprobadas listas para consolidar |
| EDAN consolidados | Total de EDANs municipales creados |
| EDAN enviados | EDANs consolidados enviados a nivel nacional |

Incluye tarjetas de localidades pendientes y EDANs consolidados con detalles de
evento, población y estado.

---

## 8. Funcionalidades transversales

| Funcionalidad | Implementación |
|---------------|----------------|
| **Detección de conectividad** | Monitoreo continuo con verificación HTTP real, polling cada 15s, tolerancia a fallos |
| **Indicador de conexión** | Badge visual "En línea" / "Sin conexión" en la barra de navegación |
| **Sincronización manual** | Botón de sincronización con badge de pendientes |
| **Sincronización automática** | Al reconectar la red, se ejecuta pull/push automáticamente |
| **Captura de fotos** | Cámara con geolocalización automática, calidad configurable (80%, 1920x1080) |
| **Selección de galería** | Photo Picker del sistema (Android 13+) / GET_CONTENT (versiones anteriores) |
| **Firma digital** | Validación de firmas en PDFs con datos del certificado |
| **Mapa interactivo** | flutter_map con clustering, GeoJSON municipal, vista satelital/callejera |
| **Manual interactivo** | TutorialGuide animado + asistente IA con RAG + guías por rol |
| **Geocodificación** | Resolución inversa de coordenadas a direcciones |
| **Multiidioma** | Localización en español (es_BO) con soporte para inglés |
| **Tema personalizado** | Paleta de colores configurable por módulo |
| **Depuración** | Log de errores a archivo local con DebugLog |
