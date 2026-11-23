# CompraMejor — Análisis de la v1.0 y decisión de arquitectura

> Complemento de [COMPRA_MEJOR.md](COMPRA_MEJOR.md) (v1.1). El documento original está en [docs/historial/PRECIO_JUSTO_v1.0_original.md](docs/historial/PRECIO_JUSTO_v1.0_original.md).

---

## 1. Análisis de la v1.0

### 1.1. Puntos fuertes (se conservan en v1.1)

- **Separación producto / publicación** (`products` vs `storeProducts`).
- **Dinero exacto, fechas en UTC, historial inmutable.**
- **Regla de precio desactualizado** (RF-04, RN-01, RN-09).
- **Costo de envío desconocido ≠ 0** (RN-03).
- **Postura legal y ética del scraping**: sin evasión de CAPTCHAs ni bloqueos, con evaluación por tienda.
- **Fusión conservadora de productos**: la IA asiste, pero no decide.

### 1.2. Observaciones y estado en v1.1

| # | Observación en v1.0 | Estado en v1.1 |
|---|---|---|
| 1 | Sin identificador, la puntuación máxima era 95, justo el umbral de "alta confianza". | ✅ Resuelto: identificador = Nivel 1 directo; umbrales 90 / 75 y reglas bloqueantes (sección 8). |
| 2 | El worker evaluaba alertas, pero 6.4 decía que el scraping no tenía lógica de negocio. | ✅ Resuelto: sin backend, el motor asume explícitamente post-proceso y alertas (sección 6.4). |
| 3 | Faltaban tablas de refresh tokens y recuperación de contraseña. | ✅ Resuelto: lo gestiona Firebase Auth. |
| 4 | El freemium no tenía soporte en datos. | ✅ Resuelto: `users.plan` y `config/app.freePlanLimits`. |
| 5 | Se medían "clics hacia tiendas" sin dónde registrarlos. | ✅ Resuelto: evento `outbound_click` en Google Analytics for Firebase (plugin de Flutter). |
| 6 | Faltaban preferencias de notificación. | ✅ Resuelto: `users.notificationPrefs`. |
| 7 | Publicaciones y alertas no distinguían variantes. | ✅ Resuelto: `variantId` en `storeProducts` y `alerts`. |
| 8 | `wishlist_items` sin restricción de unicidad. | ✅ Resuelto: arreglo `productIds` con `arrayUnion`. |
| 9 | No se guardaba el envío actual por oferta. | ✅ Resuelto: `currentShippingCents`. |
| 10 | Estados (`condition`, `matchStatus`, etc.) sin valores definidos. | ✅ Resuelto: valores definidos en la sección 9.3. |
| 11 | El periodo de vigencia no tenía dónde configurarse. | ✅ Resuelto: `stores.freshnessMinutes` y `config/app.defaultFreshnessMinutes`. |
| 12 | Búsqueda tolerante a errores sin tecnología definida. | ⚠️ Parcial: tokens normalizados en el MVP; buscador externo en fase posterior. |
| 13 | Sprint 1 muy cargado (3 lenguajes, Docker, Redis). | ✅ Resuelto: 2 lenguajes (Dart y Python), sin servidores ni Docker. |
| 14 | "FINANCIO" se menciona sin contexto. | ⏳ Pendiente: agregar una línea explicativa si el documento será leído por terceros. |

---

## 2. Decisión de arquitectura

**Decisión (22/11/2026):** no usar backend propio. Se adopta **Firebase en plan Spark (gratis)** con **GitHub Actions** para el scraping.

**Motivo:** no hay presupuesto para infraestructura durante el desarrollo y la validación.

### Opciones evaluadas

| Opción | Resultado | Motivo |
|---|---|---|
| Spring Boot + PostgreSQL + Redis (v1.0) | ❌ Descartada | Requiere servidores con costo mensual y mantener 3 lenguajes. |
| Firebase Data Connect (PostgreSQL / Cloud SQL) | ❌ Descartada por ahora | Solo tiene prueba gratuita (90 días en Spark); después, Cloud SQL cuesta desde ~US$ 9/mes. |
| Supabase (PostgreSQL gratis) | ⏸️ Alternativa | Gratis con 500 MB y conserva el modelo relacional, pero el proyecto se pausa tras una semana sin actividad. |
| **Firebase Spark (Auth + Firestore) + GitHub Actions** | ✅ **Elegida** | Plan gratuito permanente, sin tarjeta; el scraping se ejecuta en GitHub Actions. |

### Lo que se acepta a cambio

- Montos en céntimos (Firestore no tiene DECIMAL).
- Datos desnormalizados (resúmenes de precio dentro del producto).
- Búsqueda simple por palabras en el MVP.
- Sin Cloud Functions: la lógica se ejecuta en el motor Python después de cada corrida.
- MVP pequeño (1 categoría, 1 a 2 tiendas, cientos de productos) para no pasar la cuota.

### Cuándo revisar la decisión

- Si el uso diario supera el 70 % de la cuota de lecturas o escrituras de Firestore.
- Si se necesita búsqueda tolerante a errores o validaciones en servidor.
- Si se empieza a cobrar a usuarios Premium.

En esos casos, el paso natural es activar el plan **Blaze**, que mantiene la cuota gratuita y cobra solo el exceso.
