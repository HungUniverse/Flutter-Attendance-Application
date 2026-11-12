import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_services.dart';
import 'contracts.dart';

/// FCM handles notification taps. Firestore supplies the account-scoped inbox.
class FirestoreNotifications extends FirebaseNotificationService {
  FirestoreNotifications(super.messaging, this.db);
  final FirebaseFirestore db;

  @override
  Future<List<AppNotice>> history(String uid) async {
    final rows = await db.collection('announcements').where('recipientUid', isEqualTo: uid).get();
    final notices = rows.docs.map((row) {
      final data = row.data();
      return AppNotice(
        id: row.id, title: data['title'] as String, body: data['body'] as String,
        at: (data['at'] as Timestamp).toDate(),
        classId: data['classId'] as String?, meetingId: data['meetingId'] as String?,
      );
    }).toList()..sort((a, b) => b.at.compareTo(a.at));
    return notices;
  }
}
