import 'package:cloud_firestore/cloud_firestore.dart';

/// Preferencias de notificación (RF-01, RF-12).
class NotificationPrefs {
  const NotificationPrefs({
    this.push = true,
    this.priceAlerts = true,
    this.backInStock = true,
    this.weeklySummary = false,
  });

  final bool push;
  final bool priceAlerts;
  final bool backInStock;
  final bool weeklySummary;

  factory NotificationPrefs.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const NotificationPrefs();
    return NotificationPrefs(
      push: d['push'] as bool? ?? true,
      priceAlerts: d['priceAlerts'] as bool? ?? true,
      backInStock: d['backInStock'] as bool? ?? true,
      weeklySummary: d['weeklySummary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'push': push,
        'priceAlerts': priceAlerts,
        'backInStock': backInStock,
        'weeklySummary': weeklySummary,
      };

  NotificationPrefs copyWith({bool? push, bool? priceAlerts, bool? backInStock, bool? weeklySummary}) =>
      NotificationPrefs(
        push: push ?? this.push,
        priceAlerts: priceAlerts ?? this.priceAlerts,
        backInStock: backInStock ?? this.backInStock,
        weeklySummary: weeklySummary ?? this.weeklySummary,
      );
}

/// Documento `users/{uid}` (PRECIO_JUSTO.md, sección 9.3).
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.plan = 'FREE',
    this.notificationPrefs = const NotificationPrefs(),
    this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String plan;
  final NotificationPrefs notificationPrefs;
  final DateTime? createdAt;

  bool get isPremium => plan == 'PREMIUM';

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final created = d['createdAt'];
    return UserProfile(
      uid: doc.id,
      email: d['email'] as String? ?? '',
      displayName: d['displayName'] as String? ?? '',
      plan: d['plan'] as String? ?? 'FREE',
      notificationPrefs: NotificationPrefs.fromMap(d['notificationPrefs'] as Map<String, dynamic>?),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
