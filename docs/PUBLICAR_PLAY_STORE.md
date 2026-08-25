# Firma y Publicación en Google Play

Guía para generar el **App Bundle firmado** (`app-release.aab`) y subirlo a Google Play Console.

---

## Requisitos

- Flutter instalado (las versiones actuales usan Kotlin DSL / `build.gradle.kts`)
- Android Studio (para `keytool` si no está en el PATH)
- Keystore de release: `android/app/edan-release-key.jks`
- Credenciales del keystore

> **IMPORTANTE:** El keystore y su contraseña son **irrecuperables**. Si se pierden,
> no se podrán publicar actualizaciones de la app ni recuperar la cuenta de Play Store.
> Haz una copia de seguridad fuera del repositorio (nube privada, pendrive, etc.).
> `key.properties` y `*.jks` están en `.gitignore` y **no** deben subirse a git.

---

## Estructura de archivos

| Archivo | Ubicación | Propósito |
|---------|-----------|-----------|
| Keystore | `android/app/edan-release-key.jks` | Clave privada de firma (PKCS12) |
| Credenciales | `android/key.properties` | Password, alias y ruta del keystore |
| Config de firma | `android/app/build.gradle.kts` | `signingConfigs.release` + `buildTypes.release` |

---

## Configuración de firma

### 1. `android/key.properties`

```properties
storePassword=AGRIdigital2024
keyPassword=AGRIdigital2024
keyAlias=edan
storeFile=edan-release-key.jks
```

- `storeFile` se resuelve relativo a `android/app/` (donde vive el keystore).
- No debe versionarse (ya excluido por `.gitignore`).

### 2. `android/app/build.gradle.kts`

```kotlin
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... namespace, compileSdk, defaultConfig ...

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

> El release ya **no** usa el keystore de debug; usa `edan-release-key.jks`.

---

## Generar el App Bundle

```bash
flutter build appbundle --release
```

**Salida:** `build/app/outputs/bundle/release/app-release.aab`

### Verificar la firma

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

La huella **SHA-256** debe coincidir con la del keystore:

```bash
keytool -list -v -keystore android/app/edan-release-key.jks
```

Huella actual del keystore `edan`:
```
97:B7:88:12:00:F8:20:7E:26:04:3C:59:B1:68:FC:5D:9B:D3:1C:4B:21:10:E3:89:CC:E4:BA:24:96:8A:44:0D
```

---

## Versión

La versión se define en `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

- `1.0.0` → `versionName` (visible para el usuario)
- `+1` → `versionCode` (entero incremental usado por Play Store)

**Regla:** cada subida nueva a Play Store debe tener un `versionCode` mayor.

---

## Subir a Google Play Console

1. Entra a [Google Play Console](https://play.google.com/console).
2. Selecciona la app (o créala si es la primera vez).
3. Menú **Release → Production** (o **Internal testing** / **Closed testing** para pruebas previas).
4. **Create new release**.
5. Sube el archivo `app-release.aab`.
6. Completa las notas de la versión (release notes).
7. **Save** → **Review release** → **Start rollout to Production**.

> Play Console usa **App Signing by Google Play**: Google administra la clave de firma
> de la app; tu keystore queda como *upload key* para subir los AAB. No hay que hacer
> nada extra en el proyecto para esto; se configura al crear la app en Play Console.

---

## Errores comunes

| Error | Causa / Solución |
|-------|------------------|
| `keytool` no se encuentra | Usar la ruta completa de Android Studio, p. ej. `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe` |
| `Keystore was tampered with` | El `.jks` se modificó/corrompió; restaurar la copia de seguridad |
| Play Store rechaza el versionCode | Bajar versión / versionCode repetido; incrementar `versionCode` en `pubspec.yaml` |
| Firma con debug en producción | Verificar que `buildTypes.release.signingConfig` apunte a `signingConfigs.getByName("release")` |

---

## Comandos útiles

```bash
# Generar bundle release firmado
flutter build appbundle --release

# Generar APK release firmado (para distribuir fuera de Play Store)
flutter build apk --release

# Listar entradas del keystore
keytool -list -v -keystore android/app/edan-release-key.jks

# Verificar firma de un AAB
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```
