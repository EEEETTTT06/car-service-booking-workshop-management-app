import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'firebase_options.dart';
import 'pages/auth/login_page.dart';
import 'pages/customer/navigation_control.dart';

Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  await Supabase.initialize(
    url: 'https://vnrvpblqdgljfgjrvdbr.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZucnZwYmxxZGdsamZnanJ2ZGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MzAyNjMsImV4cCI6MjA5NjIwNjI2M30.GYrrBnRhnOdeS2aZ7IW_mn2WGNnGUThbDcuvxuEcrDs',
  );

  runApp(const CarServiceApp());
}

class CarServiceApp extends StatefulWidget {
  const CarServiceApp({super.key});

  @override
  State<CarServiceApp> createState() => _CarServiceAppState();
}

class _CarServiceAppState extends State<CarServiceApp> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setupFCM();
    });
  }

  Future<void> setupFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      debugPrint('FCM TOKEN: $token');

      await updateAppIconBadge();

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('Foreground notification: ${message.notification?.title}');
        await updateAppIconBadge();
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        debugPrint('Notification opened: ${message.notification?.title}');
        await updateAppIconBadge();
      });
    } catch (e) {
      debugPrint('FCM setup skipped/error: $e');
    }
  }

  Future<void> updateAppIconBadge() async {
    try {
      final isSupported = await AppBadgePlus.isSupported();

      if (!isSupported) {
        debugPrint('App icon badge is not supported on this device.');
        return;
      }

      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        await AppBadgePlus.updateBadge(0);
        return;
      }

      int unreadCount = 0;

      final admin = await Supabase.instance.client
          .from('admins')
          .select('admin_id')
          .eq('admin_id', user.id)
          .maybeSingle();

      if (admin != null) {
        final response = await Supabase.instance.client
            .from('admin_notifications')
            .select('notification_id')
            .eq('admin_id', user.id)
            .eq('is_read', false);

        unreadCount = response.length;
      } else {
        final customer = await Supabase.instance.client
            .from('customers')
            .select('customer_id')
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (customer != null) {
          final response = await Supabase.instance.client
              .from('notifications')
              .select('notification_id')
              .eq('customer_id', customer['customer_id'])
              .eq('is_read', false);

          unreadCount = response.length;
        }
      }

      await AppBadgePlus.updateBadge(unreadCount);
      debugPrint('App icon badge updated: $unreadCount');
    } catch (error) {
      debugPrint('Failed to update app icon badge: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Service App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkLoginSession();
    });
  }

  Future<void> checkLoginSession() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      goLogin();
      return;
    }

    try {
      final adminData = await supabase
          .from('admins')
          .select()
          .eq('admin_id', user.id)
          .maybeSingle();

      if (adminData != null) {
        await safeSignOut();
        goLogin();
        return;
      }

      final customerData = await supabase
          .from('customers')
          .select()
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (customerData != null) {
        await updateCustomerFcmToken(user.id);
        goCustomer();
        return;
      }

      await safeSignOut();
      goLogin();
    } catch (error) {
      debugPrint('AuthGate error: $error');
      await safeSignOut();
      goLogin();
    }
  }

  Future<void> updateCustomerFcmToken(String userId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken != null) {
        await supabase.from('customers').update({
          'fcm_token': fcmToken,
        }).eq('auth_user_id', userId);
      }
    } catch (e) {
      debugPrint('FCM token update skipped/error: $e');
    }
  }

  Future<void> safeSignOut() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out skipped/error: $e');
    }
  }

  void goLogin() {
    if (!mounted || _navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    });
  }

  void goCustomer() {
    if (!mounted || _navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NavigationControl()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFD7E5FA),
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}