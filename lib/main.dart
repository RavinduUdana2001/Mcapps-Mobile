// lib/main.dart
import 'dart:convert';
import 'dart:io' show Platform;
import  'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:mcapps/pages/lunchpage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcapps/splashscreen.dart';
import 'package:mcapps/pages/message_detail_page.dart';
import 'package:mcapps/mainpage.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final Set<String> _handledKeys = <String>{};
const int _handledKeysMax = 100;

Map<String, dynamic>? _initialNotificationData;

// Optional: auto-navigate to a screen even while app in foreground
const bool AUTO_NAV_ON_FOREGROUND = true;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Local notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse res) async {
      if (res.payload != null) {
        try {
          final data = json.decode(res.payload!);
          // Route to screen if provided; otherwise show detail page
          if (await _tryOpenScreenFromData(data)) return;
          await _navigateToDetail(data);
        } catch (_) {}
      }
    },
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'mcapps_channel',
      'MCApps Notifications',
      description: 'Channel for MCApps alerts',
      importance: Importance.max,
    ),
  );

  // Android 13+ runtime permission
  await androidPlugin?.requestNotificationsPermission();

  // If app was launched by tapping a push from terminated state
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _initialNotificationData = {
      ...initialMessage.data,
      if (initialMessage.notification?.title != null)
        'title': initialMessage.notification!.title!,
      if (initialMessage.notification?.body != null)
        'message': initialMessage.notification!.body!,
    };
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _wired = false;

  @override
  void initState() {
    super.initState();
    _initFCM();

    // Handle initial push after splash so nav is clean
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_initialNotificationData != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (await _tryOpenScreenFromData(_initialNotificationData!)) return;
        await _navigateToDetail(_initialNotificationData!);
      }
    });
  }

  Future<void> _initFCM() async {
    if (_wired) return;
    _wired = true;

    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await _mirrorTokenToRTDB(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _mirrorTokenToRTDB(t);
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      final dedupeId = data['dedupe_id']?.toString();
      final ts = data['timestamp']?.toString();
      final title = (message.notification?.title ?? data['title'] ?? '').toString();
      final body  = (message.notification?.body  ?? data['message'] ?? '').toString();

      final key = dedupeId ?? '$title|$body|$ts';
      if (_handledKeys.contains(key)) return;
      _handledKeys.add(key);
      if (_handledKeys.length > _handledKeysMax) {
        _handledKeys.remove(_handledKeys.first);
      }

      _showLocalNotification(message);

      if (AUTO_NAV_ON_FOREGROUND &&
          await _tryOpenScreenFromData({
            ...data,
            if (message.notification?.title != null)
              'title': message.notification!.title!,
            if (message.notification?.body != null)
              'message': message.notification!.body!,
          })) {
        // navigated
      }
    });

    // Taps from background
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final data = {
        ...message.data,
        if (message.notification?.title != null)
          'title': message.notification!.title!,
        if (message.notification?.body != null)
          'message': message.notification!.body!,
      };
      if (await _tryOpenScreenFromData(data)) return;
      await _navigateToDetail(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: Splashscreen(notificationData: _initialNotificationData),
    );
  }
}

void _showLocalNotification(RemoteMessage message) {
  final n = message.notification;
  final data = message.data;

  final title = n?.title ?? data['title'] ?? 'No Title';
  final body  = n?.body  ?? data['message'] ?? 'No Message';

  const androidDetails = AndroidNotificationDetails(
    'mcapps_channel',
    'MCApps Notifications',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
  );
  final details = const NotificationDetails(android: androidDetails);

  final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

  // Include screen_name so tapping local banner routes too
  flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    details,
    payload: json.encode({
      'title': title,
      'message': body,
      'screen_name': data['screen_name'],
      'timestamp': data['timestamp'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
    }),
  );
}

Future<void> _navigateToDetail(Map<String, dynamic> data) async {
  try {
    String? tsRaw = data['timestamp']?.toString();
    int? ts = tsRaw != null ? int.tryParse(tsRaw) : null;
    if (ts != null && ts < 20000000000) ts *= 1000;

    final formatted = ts != null
        ? DateFormat('MMMM d, y – hh:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(ts))
        : 'Unknown Time';

    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('userData');
    final isLoggedIn  = prefs.getBool('isLoggedIn') ?? false;

    if (userDataStr != null && isLoggedIn) {
      final userData = jsonDecode(userDataStr);
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => Mainpage(userData: userData)),
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 300));
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          title: data['title'] ?? 'No Title',
          message: data['message'] ?? 'No Message',
          timestamp: formatted,
        ),
      ),
    );
  } catch (_) {}
}

// ===== Screen routing helpers =====

Future<bool> _tryOpenScreenFromData(Map<String, dynamic> data) async {
  final screen = (data['screen_name'] ?? data['screen'] ?? '').toString().trim();
  if (screen.isEmpty) return false;

  // If your app wants to land on Mainpage first when logged in
  final prefs = await SharedPreferences.getInstance();
  final userDataStr = prefs.getString('userData');
  final isLoggedIn  = prefs.getBool('isLoggedIn') ?? false;
  Map<String, dynamic> userData = {};
  if (userDataStr != null) {
    try { userData = jsonDecode(userDataStr); } catch (_) {}
  }

  if (isLoggedIn && userData.isNotEmpty) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Mainpage(userData: userData)),
      (route) => false,
    );
    await Future.delayed(const Duration(milliseconds: 200));
  }

  return _openScreenByName(screen, userData: userData);
}

Future<bool> _openScreenByName(String name, {required Map<String, dynamic> userData}) async {
  switch (name) {
    case 'LunchScreen':
    case 'LunchPage':
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => LunchPage(userData: userData)),
      );
      return true;

    // Add more mappings here as needed
    default:
      return false;
  }
}

// ===== Token mirroring (unchanged) =====
Future<void> _mirrorTokenToRTDB(String token) async {
  try {
    final rtdb = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://mcapps-6e40e-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    final di = DeviceInfoPlugin();
    String deviceKey = 'unknown_device';
    if (Platform.isAndroid) {
      final info = await di.androidInfo;
      deviceKey = _sanitizeForRtdbKey(info.id ?? 'android_unknown');
    } else if (Platform.isIOS) {
      final info = await di.iosInfo;
      deviceKey = _sanitizeForRtdbKey(info.identifierForVendor ?? 'ios_unknown');
    } else {
      deviceKey = 'other_device';
    }

    await rtdb.ref('device_tokens/$deviceKey').set(token);
  } catch (_) {}
}

String _sanitizeForRtdbKey(String input) {
  return input.replaceAll(RegExp(r'[.\#\$\[\]/]'), '_');
}
