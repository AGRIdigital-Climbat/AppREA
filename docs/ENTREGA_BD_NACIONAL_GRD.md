# Informe de Entrega — Base de Datos Nacional y Repositorio de GRD

**Proyecto:** Fortalecimiento del Sistema Nacional de Gestión del Riesgo de Desastres  
**Sección del contrato:** 4.2 — Base de Datos Nacional y Repositorio de GRD  
**Organismo:** SINAGER-SAT / VIDECI  

---

## 1. Esquema en PostgreSQL/PostGIS operativo

Backend API REST desplegado y operativo con **47 endpoints únicos** documentados vía OpenAPI (accesibles en `/docs`). Soporte geoespacial PostGIS para polígonos de límite municipal y consultas espaciales.

**8 módulos funcionales:**

- **Autenticación** — Login JWT, verificación de identidad, cambio de contraseña, registro de usuarios
- **Geografía** — Departamentos, provincias, municipios, polígonos GeoJSON
- **Reportes** — CRUD completo con estados, fotos, filtros y paginación
- **Evaluación de Daños (EDAN)** — Evaluaciones con 13 secciones, consolidación, estados
- **Localidades** — Localidades dentro de evaluaciones, sync batch, fotos por sección
- **Usuarios** — Gestión de usuarios con roles, filtros por municipio
- **Archivos** — Upload y descarga de imágenes vía multipart
- **Asistente IA** — Chat en tiempo real, búsqueda semántica y descarga de documentos de referencia

Esquema de base de datos relacional documentado con tablas de auditoría y trazabilidad de operaciones por cada registro.

---

## 2. Información del Observatorio Nacional de Desastres cargada

Formulario de Evaluación de Daños y Necesidades (EDAN) completo con 13 secciones de levantamiento de datos. Cada sección es independiente y puede habilitarse o deshabilitarse por localidad según el tipo de daño reportado.

**Secciones implementadas:**

1. **Datos Generales** — Alcalde, ubicación, fechas de evaluación
2. **Población Afectada y Damnificada** — Grupo etario, impacto poblacional
3. **Municipio Afectado** — Tipo de evento, impacto, primera respuesta
4. **Salud** — Establecimientos de salud, daños, necesidades
5. **Infraestructura** — Vialidad, puentes, infraestructura pública
6. **Servicios Básicos** — Agua, electricidad, alcantarillado, comunicaciones
7. **Educación** — Unidades educativas, estudiantes, docentes afectados
8. **Vivienda** — Daño parcial y total de viviendas
9. **Sector Agropecuario** — Agricultura, pecuario, infraestructura productiva
10. **Protección** — Población vulnerable, datos de género
11. **Necesidades Humanitarias** — Alimentación, refugio, higiene, otros
12. *(Reservado para uso futuro)*
13. **Responsable del Formulario** — Información del firmante

Más de 22 clases de modelo con serialización JSON bidireccional. Catálogos de referencia: tipos de evento, estados de evaluación, tipos de localidad, niveles de daño.

---

## 3. Módulo operativo municipal con sincronización automática

La aplicación móvil permite el levantamiento de datos en campo con modo completo offline para zonas sin conectividad. Base de datos local SQLite (12 tablas) que funciona como fuente de verdad cuando no hay red, con sincronización automática al servidor central cuando se detecta conectividad.

**5 mecanismos de sincronización automática:**

- **Reportes de campo** — Push/pull con reintento automático (hasta 3 intentos por registro)
- **Evaluaciones EDAN** — Sincronización en lote con el servidor
- **Localidades** — Merge inteligente con deduplicación por huella de datos
- **Imágenes** — Upload fotográfico vía multipart cuando se detecta conectividad
- **Monitoreo de conectividad** — Ping al servidor cada 30 segundos con actualización en tiempo real

**Estrategia de merge en sincronización:**

- Deduplicación automática de registros duplicados por huella JSON
- Preservación de encabezados locales cuando el servidor no los almacena
- Regeneración automática de IDs en caso de conflicto
- Dirección: el dispositivo local es autoritativo; el servidor aporta datos faltantes (rutas de fotos, coordenadas)
- Carga automática de datos del servidor al iniciar sesión del usuario

---

## 4. Registro de usuarios y trazabilidad

Autenticación JWT con almacenamiento seguro en el dispositivo. Auto-login con expiración diferenciada según rol.

**3 niveles de acceso:**

- **UGR** (Unidad de Gestión de Riesgos) — Gestión completa: creación de evaluaciones, aprobación, consolidación, administración de usuarios
- **RESP** (Responsable de Campo) — Levantamiento de datos en campo: formulario con cámara, mapa de localidades, sincronización
- **Genérico** — Consultas y visualización de reportes

Sistema de permisos por módulo (Reportes, Evaluación, RIDA, SIN-B). Registro de nuevos usuarios con verificación de identidad. CRUD de usuarios desde la interfaz UGR con asignación de municipio y rol. Logs de auditoría por cada operación registrados en el servidor.

---

## 5. Consultas por municipio, amenaza y periodo

Filtros de consulta disponibles: municipio, estado de la evaluación, rango de fechas, usuario responsable, estado de sincronización, borradores.

Resumen por municipio con contadores por estado de la evaluación (enviado, en revisión, aprobado, rechazado, cerrado). Dashboards con indicadores y actividad reciente para UGR. Dashboard con estadísticas y elementos pendientes para RESP. Mapas interactivos con visualización de localidades afectadas filtradas por municipio.

---

## 6. Aplicación móvil Android/iOS

Aplicación desarrollada en Flutter (Dart ^3.12.2), compilada para Android (compileSdk 36) e iOS. 82 archivos fuente, 27 pantallas, 11 widgets reutilizables.

**Levantamiento de datos en campo:**

- Formulario EDAN completo con 13 secciones, adaptable por tipo de daño
- Captura fotográfica integrada con cámara del dispositivo
- Georreferenciación automática del levantamiento (GPS alta precisión)
- Levantamientos parciales por comunidades dentro de un mismo municipio
- Modo borrador para guardar avances sin conexión
- Sincronización automática al restaurar conectividad

**Mapas interactivos:**

- Vista satelital (ArcGIS) y callejera (OpenStreetMap)
- Polígono de límite municipal缓存本地
- Marcadores agrupados con datos de sección por localidad
- Alternancia de capas y zoom por defecto al límite municipal

**Gestión de evaluaciones:**

- Dashboard con indicadores por estado (enviado, en revisión, aprobado, rechazado, cerrado)
- Vista previa de evaluaciones antes de enviar
- Consolidación de localidades aprobadas en evaluaciones individuales
- Eliminación con registro de pendiente de eliminación en servidor

**Funcionalidades técnicas:**

- Navegación por roles con acceso diferenciado
- Tema Material 3 con 7 paletas configurables por módulo
- Soporte dual Android/iOS con permisos diferenciados por versión
- Almacenamiento seguro de credenciales (FlutterSecureStorage)

---

## 7. Módulo de exportación de reportes en PDF y Excel

Vista previa de reportes con diseño de documento estilizado: encabezado coloreado con título y fecha, secciones con campos etiquetados, mapa embebido con ubicación del evento, y pie de página con notas.

Apertura de documentos PDF de referencia desde la plataforma mediante el asistente inteligente.

**Estado:** Módulo de visualización funcional. Generación nativa de archivos PDF y Excel en fase de implementación.

---

## 8. Manual interactivo

Guía oficial de evaluación de daños y necesidades integrada en la aplicación. Guía específica por rol disponible dentro de la app para levantamiento en campo.

**Asistente inteligente integrado:**

- Chat en tiempo real con streaming de respuesta token por token
- Búsqueda semántica de documentos de referencia con puntuación de similitud
- Citación de fuentes con referencias numeradas
- Preguntas sugeridas para consultas frecuentes
- Descarga de documentos PDF de referencia para consulta offline

Documentación técnica completa: README del proyecto con diagramas de flujo offline, esquema de base de datos documentado, guía de publicación en tiendas de aplicaciones.

---

## 9. Resumen de alcance entregado

| Entregable (contrato 4.2) | Estado |
|----------------------------|--------|
| Esquema PostgreSQL/PostGIS operativo | Implementado |
| Observatorio Nacional de Desastres cargado | Implementado |
| Módulo municipal con sincronización automática | Implementado |
| Registro de usuarios y trazabilidad | Implementado |
| Consultas por municipio, amenaza y periodo | Implementado |
| Aplicación móvil Android/iOS | Implementado |
| Exportación PDF/Excel | En progreso |
| Manual interactivo | Implementado |

---

## 10. Métricas técnicas

- **82** archivos fuente Dart
- **47** endpoints API del sistema principal + **5** del asistente IA
- **12** tablas SQLite locales
- **24+** clases de modelo de datos
- **27** pantallas de interfaz
- **13** secciones de evaluación de daños
- **5** mecanismos de sincronización
- **3** niveles de acceso por rol
