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

## Scraping

Tiendas activas (VTEX): **Coolbox**, **Plaza Vea**, **Oechsle** y **Promart**. Wong está registrada pero inactiva (términos sin revisar).
Cada tienda tiene su evaluación (robots.txt, términos, conclusión) y su mapa de categorías en [stores.json](scraping-engine/app/data/stores.json).

**Agregar una tienda VTEX** es solo configuración: añadir su entrada en `stores.json` con la evaluación completa y `vtexCategories`. El spider se genera solo y el workflow la incluye si `scrapingEnabled` es `true` (no se activa sin evaluación).

Probar contra el emulador (una página por categoría, ~1 minuto, pausas de 5 s entre solicitudes):

```powershell
cd scraping-engine
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8085"
.venv\Scripts\python -m app.admin.seed
.venv\Scripts\scrapy crawl coolbox -a max_pages=1     # también: plazavea, oechsle, promart
```

En producción lo ejecuta el workflow [scrape.yml](.github/workflows/scrape.yml) cada 6 horas, **solo si existe el secret `FIREBASE_SERVICE_ACCOUNT`**:

1. Firebase Console → Configuración del proyecto → **Cuentas de servicio** → **Generar nueva clave privada** (descarga un JSON).
2. GitHub → Settings → Secrets and variables → Actions → **New repository secret**: nombre `FIREBASE_SERVICE_ACCOUNT`, valor = contenido completo del JSON.
3. **Borrar el JSON descargado** de la computadora (o guardarlo fuera del repositorio).
4. Probar: Actions → Scraping → Run workflow (con `max_pages` = 1).

## Administración del catálogo

Los scripts escriben en el **emulador** por defecto (requiere `FIRESTORE_EMULATOR_HOST`):

```powershell
cd scraping-engine
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8085"
.venv\Scripts\python -m app.admin.categories                                   # árbol de categorías
.venv\Scripts\python -m app.admin.import_products app/data/sample_products.json # carga de productos
.venv\Scripts\python -m app.admin.import_products mi_archivo.json --dry-run     # solo validar
```

Para el **proyecto real**: quitar `FIRESTORE_EMULATOR_HOST`, apuntar `GOOGLE_APPLICATION_CREDENTIALS` a la clave de la cuenta de servicio (guardada **fuera** del repositorio) y agregar `--prod --yes`.

Formato de productos: ver el encabezado de [import_products.py](scraping-engine/app/admin/import_products.py) y el ejemplo [sample_products.json](scraping-engine/app/data/sample_products.json).

## Pruebas

```bash
cd mobile_app && flutter analyze && flutter test          # app
cd scraping-engine && .venv/Scripts/python -m pytest -q   # motor
cd firebase-tests && npm install && npm test              # reglas (levanta el emulador solo)
```

## Proyecto real de Firebase

| Dato | Valor |
|---|---|
| ID del proyecto | `precio-justo-pe` (alias `prod` en `.firebaserc`) |
| Consola | https://console.firebase.google.com/project/precio-justo-pe/overview |
| Plan | Spark (gratis, sin facturación) |
| Firestore | `(default)` en `southamerica-east1` (São Paulo), protección contra borrado activada |
| Authentication | Correo y contraseña (Google Sign-In pendiente) |
| Apps registradas | Android `com.preciojusto.precio_justo`, iOS `com.preciojusto.precioJusto`, Web |

El alias `default` sigue apuntando al proyecto ficticio de los emuladores, así que **todo comando contra producción debe llevar `--project prod`**:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project prod
```

Ejecutar la app contra el proyecto real (sin emuladores):

```bash
cd mobile_app
flutter run --dart-define=USE_EMULATORS=false
```

Si se agregan plataformas o cambian los identificadores, regenerar la configuración con
`flutterfire configure --project=precio-justo-pe` (reemplaza `lib/firebase_options.dart` y `android/app/google-services.json`).

### Pendiente para el scraping en GitHub Actions (sprint 4)

Crear una cuenta de servicio (Configuración del proyecto → Cuentas de servicio → Generar clave privada) y guardar el JSON **solo** como secret `FIREBASE_SERVICE_ACCOUNT` del repositorio. **Nunca** subir ese archivo.

## Seguridad

- `firebase_options.dart` y `google-services.json` contienen claves de API **públicas** (no son secretas); la protección la dan `firestore.rules`. Recomendado: restringir esas claves por app en Google Cloud Console → APIs y servicios → Credenciales.
- La cuenta de servicio del Admin SDK **sí** es secreta.
- El spider de demostración usa una página **ficticia**. Antes de activar una tienda real, seguir la sección 7.7 del documento (términos de uso, `robots.txt`, límites).
