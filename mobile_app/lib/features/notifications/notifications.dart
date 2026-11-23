import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/push_service.dart';
import '../auth/auth_providers.dart';

/// `users/{uid}/notifications/{id}` — la crea el motor; el usuario solo la marca como leída.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.productId,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String message;
  final String? productId;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final payload = (d['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    return AppNotification(
      id: doc.id,
      type: d['type'] as String? ?? '',
      title: d['title'] as String? ?? '',
      message: d['message'] as String? ?? '',
      productId: payload['productId'] as String?,
      readAt: date(d['readAt']),
      createdAt: date(d['createdAt']),
    );
  }
}

class NotificationsRepository {
  NotificationsRepository(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Las 50 más recientes (la bandeja no necesita más; cuida la cuota).
  Stream<List<AppNotification>> recent() => _col
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());

  /// Solo cambia `readAt` (es lo único que las reglas permiten al usuario).
  Future<void> markRead(String id) =>
      _col.doc(id).update({'readAt': FieldValue.serverTimestamp()});

  Future<void> markAllRead(List<AppNotification> items) async {
    final batch = _db.batch();
    for (final n in items.where((n) => !n.isRead)) {
      batch.update(_col.doc(n.id), {'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}

final notificationsRepositoryProvider = Provider<NotificationsRepository?>((
  ref,
) {
  final user = ref.watch(authStateProvider).value;
  return user == null
      ? null
      : NotificationsRepository(FirebaseFirestore.instance, user.uid);
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo == null ? Stream.value(const []) : repo.recent();
});

final unreadCountProvider = Provider<int>(
  (ref) =>
      ref.watch(notificationsProvider).value?.where((n) => !n.isRead).length ??
      0,
);

/// Servicio push: se registra al iniciar sesión y se desregistra al cerrarla.
final pushServiceProvider = Provider<PushService?>((ref) {
  if (!pushSupported) return null;
  final service = PushService(
    FirebaseFirestore.instance,
    FirebaseMessaging.instance,
  );
  ref.listen(authStateProvider, (previous, next) {
    final uid = next.value?.uid;
    if (uid != null) {
      service.register(uid);
    } else if (previous?.value != null) {
      service.unregister();
    }
  }, fireImmediately: true);
  return service;
});

String _when(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// Campana con el número de avisos sin leer.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      key: const Key('notifications-nav'),
      tooltip: unread == 0
          ? 'Notificaciones'
          : 'Notificaciones: $unread sin leer',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () => context.push('/notifications'),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final repo = ref.watch(notificationsRepositoryProvider);
    final hasUnread = (items.value ?? const []).any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => repo?.markAllRead(items.value!),
              child: const Text('Marcar todo leído'),
            ),
          IconButton(
            tooltip: 'Mis alertas',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/alerts'),
          ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 56,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Sin notificaciones',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Crea una alerta en un producto y te avisaremos aquí cuando baje al precio que quieres.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => context.push('/alerts'),
                        child: const Text('Ver mis alertas'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final n = list[i];
                  return Dismissible(
                    key: ValueKey(n.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => repo?.delete(n.id),
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete_outline),
                    ),
                    child: ListTile(
                      leading: Icon(
                        n.isRead
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          fontWeight: n.isRead
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(n.message),
                      trailing: Text(
                        _when(n.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () {
                        if (!n.isRead) repo?.markRead(n.id);
                        if (n.productId != null) {
                          context.push('/product/${n.productId}');
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
