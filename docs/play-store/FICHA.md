# Publicación en Google Play: CompraMejor

Todo lo que pide Play Console, listo para copiar. Los valores entre `{{ }}` faltan:
`{{CORREO}}` es el correo de contacto público y `{{RESPONSABLE}}` el nombre del responsable de los datos.

- Paquete: `pe.compramejor.app`
- Archivo a subir: `mobile_app/build/app/outputs/bundle/release/app-release.aab`, que genera
  `flutter build appbundle --release` firmado con la llave de subida (ver «Llave de firma»).
- Política de privacidad: https://precio-justo-pe.web.app/privacidad
- Eliminación de cuenta: https://precio-justo-pe.web.app/eliminar-cuenta

## 1. Ficha de la tienda

**Nombre de la app** (máx. 30): `CompraMejor: compara precios`

**Descripción breve** (máx. 80):
`Compara precios de tiendas del Perú, mira el historial y recibe alertas.`

**Descripción completa** (máx. 4000):

```
¿Ese precio es realmente una oferta? CompraMejor te lo dice antes de comprar.

Reunimos los precios de laptops, celulares, televisores, consolas y más productos publicados por tiendas en línea del Perú, y te mostramos en un solo lugar dónde está más barato hoy.

• Compara: el mismo producto en varias tiendas, ordenado del precio más bajo al más alto.
• Historial: mira cómo cambió el precio en los últimos días y meses, y no te dejes llevar por un «antes» inflado.
• Bajadas reales: te marcamos cuándo un precio bajó de verdad, según los precios que observamos nosotros.
• Alertas: elige el precio que quieres pagar y te avisamos cuando lo alcance.
• Favoritos y listas: guarda lo que te interesa y síguelo sin buscarlo de nuevo.

Puedes ver precios sin crear una cuenta. La cuenta solo hace falta para guardar favoritos, listas y alertas, y la puedes eliminar cuando quieras desde la app.

CompraMejor no vende productos ni cobra comisiones: el botón «Ir a la tienda» te lleva a la página del producto en la tienda, donde completas tu compra. Los precios son referenciales y se actualizan periódicamente; el precio final es el que indica la tienda al momento de comprar.

CompraMejor es una app independiente y no está afiliada a las tiendas cuyos precios muestra.
```

No pongas nombres ni logos de tiendas en el título, la descripción ni las capturas: Google lo puede
tratar como uso de marcas ajenas o suplantación.

**Gráficos** (en esta carpeta):
- Ícono de 512 × 512: `icono-512.png`
- Gráfico destacado de 1024 × 500: `grafico-destacado-1024x500.png`
- Capturas del teléfono (mínimo 2, recomendado 4 a 8, 9:16): sácalas del celular con la app
  instalada (inicio, producto con comparación, historial, alertas). Que no se vean fotos ni
  logos de tiendas.

**Categoría:** Compras · **Etiquetas:** Comparación de precios, Compras.
**Datos de contacto:** correo `{{CORREO}}` (obligatorio y público). Sitio web
https://precio-justo-pe.web.app. El teléfono es opcional.

## 2. Contenido de la app (Política → Contenido de la app)

| Sección | Respuesta |
|---|---|
| Política de privacidad | https://precio-justo-pe.web.app/privacidad |
| Acceso a la app | «Parte de la funcionalidad está restringida»: crea una cuenta de prueba en la app (por ejemplo `revision.play@…`, con contraseña) y escríbela aquí. Ver precios no requiere cuenta |
| Anuncios | No contiene anuncios |
| Clasificación de contenido | Ver punto 3 |
| Público objetivo | 18 años o más (la app no está dirigida a niños) |
| App de noticias | No |
| Apps de rastreo de contactos o estado de salud de COVID-19 | No |
| Seguridad de los datos | Ver punto 4 |
| Apps gubernamentales | No |
| Funciones financieras | Ninguna (no vende, no presta, no procesa pagos) |
| Salud | No |
| Eliminación de cuenta | https://precio-justo-pe.web.app/eliminar-cuenta |

## 3. Cuestionario de clasificación de contenido (IARC)

- Categoría: **Todas las demás categorías de apps** (no es juego).
- Violencia, sexo, lenguaje, drogas, juegos de azar o apuestas: **No** en todo.
- ¿Los usuarios interactúan o comparten contenido entre sí? **No**.
- ¿Comparte la ubicación del usuario? **No**.
- ¿Permite comprar productos digitales? **No**. Enlaza a tiendas externas, sin pagos en la app.
- Resultado esperado: «Apto para todo público» / PEGI 3.

## 4. Seguridad de los datos

**¿Recopila o comparte datos de usuario?** Sí, recopila. **No los comparte** con terceros: Google
Firebase actúa como proveedor de servicios y no cuenta como «compartir».

- **¿Los datos se cifran en tránsito?** Sí.
- **¿Los usuarios pueden pedir que se borren?** Sí, desde la app o desde el enlace web.

| Tipo de dato (categoría de Google) | Recopilado | Obligatorio | Finalidad |
|---|---|---|---|
| Información personal → Dirección de correo | Sí | Opcional (solo con cuenta) | Funcionalidad de la app, Administración de la cuenta |
| Información personal → Nombre | Sí | Opcional (solo con cuenta) | Funcionalidad de la app, Administración de la cuenta |
| Actividad en la app → Otras acciones del usuario (favoritos, listas, alertas) | Sí | Opcional | Funcionalidad de la app |
| ID del dispositivo u otros ID → identificador de notificaciones (token push) | Sí | Opcional (solo si activa avisos) | Funcionalidad de la app |

No se recopila: ubicación, contactos, fotos, archivos, información financiera, salud, mensajes,
historial web, identificador de publicidad, ni datos de diagnóstico o fallos (la app no usa
Analytics ni Crashlytics). Las búsquedas y vistas recientes **no salen del celular**, así que no se
declaran.

Si después se agrega Analytics, Crashlytics, publicidad o inicio de sesión con Google, este
formulario y la política de privacidad deben actualizarse **antes** de publicar esa versión.

## 5. Pasos en orden

1. **Cuenta de desarrollador** en https://play.google.com/console (pago único de US$ 25 y
   verificación de identidad con DNI). Elige cuenta **personal**, salvo que tengas una empresa
   con RUC y D-U-N-S.
2. Completar `{{CORREO}}` y `{{RESPONSABLE}}` en `hosting/public/*.html` y publicar las páginas:
   `firebase deploy --only hosting --project prod`.
3. Crear la app en Play Console: nombre «CompraMejor», idioma español (Latinoamérica), app,
   gratuita.
4. Llenar «Contenido de la app» (punto 2) y la ficha (punto 1).
5. **Prueba cerrada obligatoria:** las cuentas personales nuevas deben tener **al menos 12
   probadores** con la prueba aceptada durante **14 días seguidos** antes de pedir acceso a
   producción. Crea un track de prueba cerrada, sube el `.aab`, agrega los correos de amigos o
   familiares (con Android) y pásales el enlace de inscripción.
6. Pasados los 14 días: Play Console → «Solicitar acceso a producción». Google hace algunas
   preguntas sobre la prueba y revisa la app (normalmente 1 a 7 días).
7. Publicar en producción, en Perú.

## Llave de firma (subida)

- La llave está **fuera del repositorio**: `C:\Users\User\.compramejor\upload-keystore.jks`. Su
  contraseña está en `mobile_app/android/key.properties` (ignorado por git) y en el respaldo
  `C:\Users\User\.compramejor\key.properties.respaldo`.
- **Guarda una copia de los dos archivos** fuera de esta computadora (USB o gestor de
  contraseñas). Sin ellos no puedes subir actualizaciones.
- Al crear la app, acepta **«Firma de apps de Play»**: Google guarda la llave final de la app y
  la tuya solo sirve para subir versiones. Si la pierdes, Google la puede reemplazar a pedido.
- Huella SHA-256 de la llave de subida (para verificar):
  `0D:F7:E3:E9:2B:39:B7:9D:D9:9C:EE:69:06:36:7A:33:04:44:E6:03:E0:CE:C6:09:D2:25:56:C8:8E:16:AA:88`

## Cada versión nueva

1. Subir `version:` en `mobile_app/pubspec.yaml` (por ejemplo `1.0.1+2`; el número tras `+` siempre
   aumenta).
2. `flutter build appbundle --release`.
3. Subir el `.aab` en Play Console (prueba cerrada o producción).
