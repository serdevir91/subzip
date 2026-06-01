import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (!Platform.isAndroid) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (_) {},
    );
  }

  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    if (!Platform.isAndroid) return;

    final androidDetails = AndroidNotificationDetails(
      'supzip_tasks',
      'SupZip Tasks',
      channelDescription: 'Notifications for SupZip background operations',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: true,
      ongoing: true,
      playSound: false,
      enableVibration: false,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(id, title, body, notificationDetails);
  }

  Future<void> showCompleteNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;

    const androidDetails = AndroidNotificationDetails(
      'supzip_tasks',
      'SupZip Tasks',
      channelDescription: 'Notifications for SupZip background operations',
      importance: Importance.defaultImportance,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(id, title, body, notificationDetails);
  }

  Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid) return;
    await _notificationsPlugin.cancel(id);
  }
}
