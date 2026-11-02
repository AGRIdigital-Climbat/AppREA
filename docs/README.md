# REA - Reporte de Eventos Adversos

Aplicación móvil desarrollada para el personal del **BATALLÓN DE INGENIEROS N°40 "VICTOR HUGO RENDÓN PÉREZ"** de la Fuerza Aérea Boliviana, diseñada para reportar eventos adversos climáticos con soporte offline y sincronización automática al servidor SINAGER-SAT.

---

## Objetivo

Facilitar la recolección y reporte de eventos adversos (inundaciones, riadas, deslizamientos, heladas, granizadas, sequías e incendios) en zonas remotas donde la conectividad es limitada o inexistente. La aplicación permite el registro offline de reportes con evidencia fotográfica y coordenadas GPS, sincronizando automáticamente los datos cuando se restablece la conexión a internet.

---

## Funcionalidades

### Autenticación
- Registro de usuarios con carnet de identidad, nombre, ubicación y contraseña
- Inicio de sesión con carnet de identidad y contraseña
- Token JWT almacenado de forma segura (FlutterSecureStorage)
- Auto-login al cerrar y volver a abrir la aplicación

### Reporte de Eventos
- Formulario con auto-relleno de ubicación desde el perfil del usuario
- Selección de tipo de evento (inundación, riada, deslizamiento, etc.)
- Captura de fecha y hora del evento
- Captura fotográfica (cámara) o selección desde galería (hasta 5 imágenes)
- Registro de coordenadas GPS automáticas
- Selección de categorías de afectación (niños, adolescentes, mujeres embarazadas, etc.)
- Descripción libre del evento
- **Pantalla de vista previa** antes de enviar con todos los datos consolidados
- **Alerta de verificación** recordlando que los datos serán verificados por SINAGER-SAT

### Dashboard
- Tarjeta de bienvenida con información del usuario
- Estadísticas: total de reportes, pendientes, sincronizados
- Sección de reportes pendientes con botón "Enviar ahora" (solo con conexión)
- Último reporte sincronizado

### Historial de Reportes
- Lista completa de reportes del usuario
- Filtros: Todos, Pendientes, Sincronizados
- Detalle completo de cada reporte con estado de sincronización
- Opción de sincronización manual individual
- Eliminación de reportes

### Perfil de Usuario
- Visualización de datos personales
- Edición de nombre, celular, comunidad y ubicación geográfica
- Cascada de selección Departamento → Provincia → Municipio
- Campo de carnet de identidad visible pero no editable
- Cierre de sesión con confirmación

### Conectividad
- Badge de estado online/offline en el AppBar (punto verde/rojo)
- Detección automática de cambios en la conectividad
- Banner de conexión con indicador visual

---

## Gestión Offline/Online

### Flujo Offline → Online

```
┌─────────────────────────────────────────────────────┐
│  USUARIO CREA REPORTE (sin conexión)                │
│  → Se guarda en SQLite local (sincronizado = false) │
│  → Se almacenan imágenes localmente                 │
│  → Se muestra toast: "Reporte guardado localmente"  │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  DETECCIÓN DE CONEXIÓN                              │
│  → ConnectivityService monitorea el estado           │
│  → Cuando se detecta conexión, se inicia sync       │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  SINCRONIZACIÓN AUTOMÁTICA                          │
│  → Envía reportes pendientes al servidor SINAGER    │
│  → Marca como sincronizado (sincronizado = true)     │
│  → Toast: "Reporte enviado exitosamente"            │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  MANEJO DE ERRORES                                  │
│  → Si falla, se incrementa intentos_sync            │
│  → Máximo 3 reintentos automáticos                  │
│  → Después de 3 fallos: toast de error              │
│  → El reporte se mantiene local para reintento      │
│    manual                                           │
└─────────────────────────────────────────────────────┘
```

### Almacenamiento Local (SQLite)
| Tabla | Descripción |
|-------|-------------|
| `reportes_offline` | Reportes creados con toda su información |
| `borradores` | Borradores guardados a medio camino |
| `sincronizaciones` | Log de intentos de sincronización |

### Políticas de Retención
- Los reportes se conservan **permanentemente** en el dispositivo
- Las imágenes se mantienen localmente incluso después de sincronizar
- No se eliminan datos automáticamente

---

## Tracking de Estado

| Funcionalidad | Estado |
|--------------|--------|
| Proyecto Flutter con configuración Android | Completado |
| Modelo de datos (Departamento, Provincia, Municipio, Evento) | Completado |
| Base de datos SQLite local | Completado |
| Servicio de autenticación (Login/Register) | Completado |
| Formulario de registro con validaciones | Completado |
| Formulario de login | Completado |
| Splash screen con auto-login | Completado |
| Home screen con 3 tabs (Dashboard/Historial/Perfil) | Completado |
| Dashboard con estadísticas y reportes pendientes | Completado |
| Formulario de reporte con auto-relleno de perfil | Completado |
| Pantalla de vista previa antes de enviar | Completado |
| Alerta de verificación SINAGER-SAT | Completado |
| Captura fotográfica (cámara/galería) | Completado |
| Geolocalización GPS automática | Completado |
| Categorías de afectación | Completado |
| Historial de reportes con filtros | Completado |
| Detalle de reporte individual | Completado |
| Perfil de usuario (ver/editar) | Completado |
| Badge online/offline | Completado |
| Sync automática offline → online | Completado |
| Reintentos de sincronización (3 intentos) | Completado |
| Toast de notificación de sync | Completado |
| Servicio de permisos (cámara, ubicación) | Completado |
| Servicio de imágenes local | Completado |
| Integración API SINAGER-SAT | Completado |
| Build APK release (52.8 MB) | Completado |

---

## API SINAGER-SAT

> **Vigente (2026-10-19):** `https://api.climbat.net/api/v2`.
> El mapa completo pantalla → API para los roles 6 (UGR) y 7 (RESP), incluido el
> wizard EDAN, está en [`MAPA_APIS_WEB_EDAN.md`](./MAPA_APIS_WEB_EDAN.md).
> La tabla siguiente es histórica (API v1).

**URL Base (histórica):** `https://aircraft-specialty-impaired-procedures.trycloudflare.com/api/v1`

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/auth/login` | POST | Inicio de sesión |
| `/usuarios/` | POST | Registro de usuario |
| `/usuarios/:id` | GET | Obtener usuario |
| `/usuarios/:id` | PUT | Actualizar usuario |
| `/shared/departamentos` | GET | Lista de departamentos |
| `/shared/provincias?id_departamento=X` | GET | Provincias por departamento |
| `/shared/municipios?id_provincia=X&id_departamento=X` | GET | Municipios por provincia |
| `/rea/reportes` | GET | Listar reportes |
| `/rea/reportes` | POST | Crear reporte |

---

## Tecnologías

- **Framework:** Flutter 3.x con Dart
- **Estado:** Provider
- **Base de datos:** SQLite (sqflite)
- **Almacenamiento seguro:** FlutterSecureStorage
- **Conectividad:** connectivity_plus
- **Geolocator:** geolocator
- **Geocoding:** geocoding
- **Permisos:** permission_handler
- **Imágenes:** image_picker
- **HTTP:** http
- **Fuentes:** Google Fonts (Roboto)

---

## Configuración del Proyecto

- **Android:** compileSdk 36, minSdk 28, targetSdk 36
- **Dispositivo de prueba:** JDY LX3P (AETJCP4926402069)
- **GitHub:** https://github.com/AGRIdigital-Climbat/AppREA.git

---

## Ejecución

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en dispositivo/emulador
flutter run

# Construir APK release
flutter build apk --release
```
