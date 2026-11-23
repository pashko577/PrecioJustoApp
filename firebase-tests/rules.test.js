// Pruebas de las reglas de seguridad de Firestore (se ejecutan en el emulador).
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, collection, getCountFromServer } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-precio-justo',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8085,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'products/p1'), { normalizedName: 'Kingston NV3 1TB', status: 'ACTIVE' });
    await setDoc(doc(db, 'users/ana'), { email: 'ana@test.pe', plan: 'FREE' });
    await setDoc(doc(db, 'users/ana/notifications/n1'), { title: 'Bajó', readAt: null });
  });
});

const anon = () => env.unauthenticatedContext().firestore();
const user = (uid) => env.authenticatedContext(uid).firestore();
const admin = () => env.authenticatedContext('root', { admin: true }).firestore();

test('el catálogo es de lectura pública', async () => {
  await assertSucceeds(getDoc(doc(anon(), 'products/p1')));
});

test('un usuario normal no puede escribir el catálogo', async () => {
  await assertFails(setDoc(doc(user('ana'), 'products/p2'), { normalizedName: 'X' }));
});

test('un admin sí puede escribir el catálogo', async () => {
  await assertSucceeds(setDoc(doc(admin(), 'products/p2'), { normalizedName: 'X' }));
});

test('un usuario lee su perfil pero no el de otro', async () => {
  await assertSucceeds(getDoc(doc(user('ana'), 'users/ana')));
  await assertFails(getDoc(doc(user('luis'), 'users/ana')));
});

test('al crear el perfil el plan debe ser FREE', async () => {
  await assertFails(setDoc(doc(user('luis'), 'users/luis'), { plan: 'PREMIUM' }));
  await assertSucceeds(setDoc(doc(user('luis'), 'users/luis'), { plan: 'FREE' }));
});

test('un usuario no puede cambiarse a PREMIUM', async () => {
  await assertFails(updateDoc(doc(user('ana'), 'users/ana'), { plan: 'PREMIUM' }));
  await assertSucceeds(updateDoc(doc(user('ana'), 'users/ana'), { displayName: 'Ana' }));
});

test('alertas: valida precio en céntimos enteros y positivos', async () => {
  const ref = doc(user('ana'), 'users/ana/alerts/a1');
  const base = { productId: 'p1', currency: 'PEN', condition: 'AT_OR_BELOW', status: 'ACTIVE' };
  await assertFails(setDoc(ref, { ...base, targetPriceCents: 249.9 }));
  await assertFails(setDoc(ref, { ...base, targetPriceCents: -100 }));
  await assertSucceeds(setDoc(ref, { ...base, targetPriceCents: 24990 }));
});

test('alertas: el usuario no puede marcarlas como TRIGGERED', async () => {
  const ref = doc(user('ana'), 'users/ana/alerts/a1');
  await assertFails(setDoc(ref, {
    productId: 'p1', currency: 'PEN', condition: 'AT_OR_BELOW', status: 'TRIGGERED', targetPriceCents: 100,
  }));
});

test('nadie más puede crear alertas en la cuenta de otro', async () => {
  await assertFails(setDoc(doc(user('luis'), 'users/ana/alerts/a1'), {
    productId: 'p1', currency: 'PEN', condition: 'AT_OR_BELOW', status: 'ACTIVE', targetPriceCents: 100,
  }));
});

test('notificaciones: el usuario solo puede marcar readAt', async () => {
  const ref = doc(user('ana'), 'users/ana/notifications/n1');
  await assertSucceeds(updateDoc(ref, { readAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { title: 'Hackeado' }));
});

test('el usuario no puede crear notificaciones', async () => {
  await assertFails(setDoc(doc(user('ana'), 'users/ana/notifications/n2'), { title: 'X' }));
});

test('favoritos: el ID del documento debe coincidir con productId', async () => {
  await assertFails(setDoc(doc(user('ana'), 'users/ana/favorites/p1'), { productId: 'otro' }));
  await assertSucceeds(setDoc(doc(user('ana'), 'users/ana/favorites/p1'), { productId: 'p1' }));
});

test('scrapingJobs: nadie escribe desde la app', async () => {
  await assertFails(setDoc(doc(admin(), 'scrapingJobs/j1'), { status: 'SUCCESS' }));
});

// ---------- Flujos del sprint 2 (mismas escrituras que FirebaseAuthRepository) ----------

test('registro: el perfil tal como lo crea la app está permitido', async () => {
  await assertSucceeds(setDoc(doc(user('nuevo'), 'users/nuevo'), {
    email: 'nuevo@correo.pe',
    displayName: 'Nuevo',
    plan: 'FREE',
    notificationPrefs: { push: true, priceAlerts: true, backInStock: true, weeklySummary: false },
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('perfil: cambiar nombre y preferencias está permitido', async () => {
  const ref = doc(user('ana'), 'users/ana');
  await assertSucceeds(updateDoc(ref, { displayName: 'Ana María', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, {
    notificationPrefs: { push: false, priceAlerts: true, backInStock: true, weeklySummary: true },
    updatedAt: serverTimestamp(),
  }));
});

test('perfil: no se puede alterar createdAt', async () => {
  await assertFails(updateDoc(doc(user('ana'), 'users/ana'), { createdAt: serverTimestamp() }));
});

test('eliminar cuenta: el dueño puede borrar subcolecciones y perfil', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const sub of ['favorites', 'wishlists', 'alerts', 'devices', 'notifications']) {
      await setDoc(doc(db, `users/ana/${sub}/x`), { productId: 'x' });
    }
  });
  const db = user('ana');
  for (const sub of ['favorites', 'wishlists', 'alerts', 'devices', 'notifications']) {
    await assertSucceeds(deleteDoc(doc(db, `users/ana/${sub}/x`)));
  }
  await assertSucceeds(deleteDoc(doc(db, 'users/ana')));
});

test('eliminar cuenta: nadie puede borrar el perfil de otro', async () => {
  await assertFails(deleteDoc(doc(user('luis'), 'users/ana')));
});

// ---------- Sprint 7: seguimiento (mismas escrituras que TrackingRepository) ----------

const alertDoc = (status, target = 23050) => ({
  productId: 'p1', variantId: null, productName: 'NV3', targetPriceCents: target,
  currency: 'PEN', condition: 'AT_OR_BELOW', status, lastTriggeredPriceCents: null,
});

test('alertas: el usuario reactiva una alerta cumplida al editarla', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/ana/alerts/a1'), { ...alertDoc('TRIGGERED'), lastTriggeredPriceCents: 22000 });
  });
  await assertSucceeds(setDoc(doc(user('ana'), 'users/ana/alerts/a1'), alertDoc('ACTIVE', 21000)));
  await assertSucceeds(setDoc(doc(user('ana'), 'users/ana/alerts/a1'), alertDoc('PAUSED', 21000)));
});

test('alertas: moneda o condición distintas se rechazan', async () => {
  await assertFails(setDoc(doc(user('ana'), 'users/ana/alerts/a2'), { ...alertDoc('ACTIVE'), currency: 'USD' }));
  await assertFails(setDoc(doc(user('ana'), 'users/ana/alerts/a2'), { ...alertDoc('ACTIVE'), condition: 'ABOVE' }));
});

test('listas: crear, renombrar y límite de 100 productos', async () => {
  const ref = doc(user('ana'), 'users/ana/wishlists/l1');
  await assertSucceeds(setDoc(ref, { name: 'Cocina', productIds: [], createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(ref, { name: 'Cocina nueva', productIds: ['p1', 'p2'], updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref, { name: '', productIds: [] }));
  await assertFails(setDoc(ref, { name: 'X', productIds: Array.from({ length: 101 }, (_, i) => `p${i}`) }));
});

test('conteo de favoritos (límite del plan): el dueño puede contar, otro no', async () => {
  await assertSucceeds(getCountFromServer(collection(user('ana'), 'users/ana/favorites')));
  await assertFails(getCountFromServer(collection(user('luis'), 'users/ana/favorites')));
});
