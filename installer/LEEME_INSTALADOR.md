# Generación del instalador Windows (Instalador_EDAN.exe)

Este documento describe los comandos necesarios para generar el instalador ejecutable de EDAN para Windows.

## Requisitos previos

- Flutter SDK con soporte Windows habilitado (canal estable).
- Visual Studio con la carga de trabajo **"Desarrollo para escritorio con C++"**.
- **Inno Setup 6** instalado (compila el instalador). Si no está instalado:

```powershell
winget install JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements
```

La ruta de ISCC.exe suele ser:
- `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
- o `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` (instalación por usuario)

## Flujo de compilación

### 1. Limpiar builds previos (opcional, recomendado)

```powershell
cd D:\CLIMBAT\OpenCodeProyect\APP_REA\REA
flutter clean
```

> Nota: borra `build\`, `.dart_tool\` y fuerza resoluciones de dependencias desde cero.

### 2. Obtener dependencias

```powershell
flutter pub get
```

### 3. Compilar la aplicación en modo release

```powershell
flutter build windows --release
```

> Esto genera el bundle ejecutable en:
> `build\windows\x64\runner\Release\`
> - `EDAN.exe` (runner nativo)
> - `flutter_windows.dll` (motor Flutter)
> - `sqlite3.dll` y `*_plugin.dll` (plugins)
> - `data\` (código Dart AOT + assets)

**Importante:** el `EDAN.exe` por sí solo NO funciona; depende de los DLLs y la carpeta `data\` de su misma carpeta.

### 4. Generar el instalador con Inno Setup

El script de configuración está en `installer\edan.iss`. Compilación:

```powershell
cd D:\CLIMBAT\OpenCodeProyect\APP_REA\REA\installer
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" edan.iss
```

O con rutas fijas según tu instalación:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" edan.iss
```

### 5. Resultado

```text
D:\CLIMBAT\OpenCodeProyect\APP_REA\REA\dist\Instalador_EDAN.exe
```

Un único archivo ejecutable (~14 MB) que:
- Instala EDAN en `C:\Program Files\EDAN\`.
- Crea accesos directos en el Menú Inicio y (opcional) Escritorio.
- Registra el desinstalador en "Programas y características".

## Comandos rápidos (todo en uno)

Para regenerar el instalador tras un cambio de código, abre **PowerShell** y ejecuta:

```powershell
cd D:\CLIMBAT\OpenCodeProyect\APP_REA\REA
flutter build windows --release
if ($?) { & "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" installer\edan.iss }
```

> `if ($?)` garantiza que el instalador solo se compile si el build fue exitoso.

## Notas

- **Actualizar el instalador**: basta repetir los pasos 3 y 4; `edan.iss` ya apunta a la carpeta `Release` actual y a la versión definida en el propio script (editar `#define MyAppVersion` si cambia la versión de la app).
- **Base de datos**: en Windows se guarda en `%APPDATA%` (AppData), fuera de `Program Files`, por lo que no se pierde al desinstalar.
- **Privilegios**: el instalador requiere permisos de administrador (instala en `Program Files`).
- **Verificación manual**: instalar, ejecutar, probar sincronización UGR (rol 6) y desinstalar.