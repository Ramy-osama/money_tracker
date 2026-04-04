import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'sms_transactions';
  static const _channelName = 'SMS Transactions';
  static const _channelDesc = 'Notifications for auto-detected SMS transactions';

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: initSettings);
    _initialized = true;

    await _requestNotificationPermission();
    debugPrint('NotificationService initialized');
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    debugPrint('Notification permission: $status');
  }

  Future<void> showSmsTransactionNotification({
    required double amount,
    String? merchant,
    String type = 'expense',
  }) async {
    if (!_initialized) await initialize();

    final title = type == 'income'
        ? 'Income Detected'
        : 'Expense Detected';

    final amountStr = amount.toStringAsFixed(2);
    final body = merchant != null && merchant.isNotEmpty
        ? '$amountStr EGP ${type == 'income' ? 'from' : 'at'} $merchant'
        : '$amountStr EGP $type detected from SMS';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
