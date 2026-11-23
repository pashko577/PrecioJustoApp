# PRECIO JUSTO

Comparador de precios para el mercado peruano. App en **Flutter**, datos en **Firebase (plan gratuito Spark)** y scraping en **Python** ejecutado con **GitHub Actions**. Costo de desarrollo: **S/ 0**.

- Documento del producto: [PRECIO_JUSTO.md](PRECIO_JUSTO.md)
- Análisis y decisión de arquitectura: [ANALISIS_Y_PROPUESTA_FIREBASE.md](ANALISIS_Y_PROPUESTA_FIREBASE.md)

## Estructura

```text
mobile_app/        App Flutter (Dart)
scraping-engine/   Motor de scraping (Python + Scrapy)
firebase-tests/    Pruebas de las reglas de seguridad (Node, solo pruebas)
firestore.rules    Reglas de seguridad de Firestore
firebase.json      Configuración de emuladores y despliegue
.github/workflows/ CI y scraping programado
```

## Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| Flutter | 3.44+ | App móvil |
| Python | 3.12 | Motor de scraping |
| Node.js | 20+ | CLI de Firebase |
| Java (JDK) | 21+ | Emuladores de Firebase |
| Firebase CLI | `npm install -g firebase-tools` | Emuladores y despliegue de reglas |

## ¿Qué son los emuladores de Firebase?

Son versiones **locales** de los servicios de Firebase (Firestore, Authentication) que corren en tu PC. Sirven para desarrollar y probar sin tocar el proyecto real:

- **Gratis y sin cuota**: las lecturas y escrituras no cuentan contra el plan Spark.
- **Sin internet ni cuenta**: el proyecto `demo-precio-justo` es ficticio; no necesita `firebase login`.
- **Datos desechables**: al apagarlos se borran (o se pueden exportar con `--export-on-exit`).
- **Interfaz web** en http://127.0.0.1:4000 para ver y editar los datos como en la consola de Firebase.
- **Reglas de seguridad reales**: el emulador aplica `firestore.rules`, así que se prueban antes de publicarlas.

| Servicio | Puerto |
|---|---|
| Firestore | 8085 (el 8080 ya estaba ocupado en esta PC) |
| Authentication | 9099 |
| Interfaz (UI) | 4000 |

## Puesta en marcha local

### 1. Levantar los emuladores (terminal 1)

```bash
firebase emulators:start --project demo-precio-justo
```

### 2. Cargar datos de ejemplo y ejecutar el spider demo (terminal 2)

```powershell
cd scraping-engine
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8085"
.venv\Scripts\python -m app.admin.seed      # categorías, tiendas y productos FICTICIOS
.venv\Scripts\scrapy crawl demo_store       # lee tests/fixtures/demo_store.html
```

### 3. Ejecutar la app (terminal 3)

```bash
cd mobile_app
flutter pub get
flutter run -d chrome        # o un emulador Android
```

La app usa los emuladores por defecto. En el emulador de Android la PC se ve como `10.0.2.2` (ya configurado). En un **celular físico**:

```bash
firebase emulators:start --project demo-precio-justo   # con "host": "0.0.0.0" en firebase.json
flutter run --dart-define=EMULATOR_HOST=192.168.X.X     # IP de tu PC en la red local
```

## Pruebas

```bash
cd mobile_app && flutter analyze && flutter test          # app
cd scraping-engine && .venv/Scripts/python -m pytest -q   # motor
cd firebase-tests && npm install && npm test              # reglas (levanta el emulador solo)
```

## Conectar con el proyecto real de Firebase (cuando toque)

1. Crear el proyecto en https://console.firebase.google.com en **plan Spark** (no agregar facturación).
2. Activar **Firestore** (región `southamerica-east1`) y **Authentication** (correo y Google).
3. Iniciar sesión y vincular:
   ```bash
   firebase login
   firebase use --add            # elegir el proyecto y ponerle el alias "prod"
   firebase deploy --only firestore:rules,firestore:indexes
   ```
4. Generar la configuración de la app (reemplaza `lib/firebase_options.dart`):
   ```bash
   dart pub global activate flutterfire_cli
   cd mobile_app && flutterfire configure
   ```
5. Compilar contra el proyecto real: `flutter run --dart-define=USE_EMULATORS=false`.
6. Para el scraping en GitHub Actions: crear una cuenta de servicio (Configuración del proyecto → Cuentas de servicio → Generar clave privada) y guardar el JSON **solo** como secret `FIREBASE_SERVICE_ACCOUNT` en GitHub. **Nunca** subir ese archivo al repositorio.

## Seguridad

- La configuración de `firebase_options.dart` no es secreta; la protección la dan `firestore.rules`.
- La cuenta de servicio del Admin SDK **sí** es secreta.
- El spider de demostración usa una página **ficticia**. Antes de activar una tienda real, seguir la sección 7.7 del documento (términos de uso, `robots.txt`, límites).
