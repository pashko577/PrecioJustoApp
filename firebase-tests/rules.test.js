// Pruebas de las reglas de seguridad de Firestore (se ejecutan en el emulador).
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

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
