import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'firebase_options.dart';
import 'pages/auth/login_page.dart';
import 'pages/customer/navigation_control.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/admin/admin_main_page.dart';

final GlobalKey<NavigatorState> appNavigatorKey =
GlobalKey<NavigatorState>();

int? pendingCustomerInitialIndex;

int? customerPageIndexFromData(
    Map<String, dynamic> data,
    ) {
  final targetPage =
  data['target_page']?.toString().trim();

  switch (targetPage) {
    case 'my_vehicles':
      return 1;
    case 'my_bookings':
      return 2;
    case 'customer_quotations':
      return 3;
    case 'service_records':
      return 4;
    default:
      return null;
  }
}

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

  final initialMessage =
  await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    pendingCustomerInitialIndex =
        customerPageIndexFromData(initialMessage.data);
  }

  runApp(const CarServiceApp());
}

class CarServiceApp extends StatefulWidget {
  const CarServiceApp({super.key});

  @override
  State<CarServiceApp> createState() => _CarServiceAppState();
}

class _CarServiceAppState extends State<CarServiceApp> {
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
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

      if (token != null && token.trim().isNotEmpty) {
        await saveTokenForCurrentUser(token);
      }

      await _tokenRefreshSubscription?.cancel();

      _tokenRefreshSubscription =
          messaging.onTokenRefresh.listen(
                (newToken) async {
              debugPrint('FCM TOKEN REFRESHED: $newToken');

              await saveTokenForCurrentUser(newToken);
            },
            onError: (error) {
              debugPrint(
                'Failed to refresh FCM token: $error',
              );
            },
          );

      await updateAppIconBadge();

      await _foregroundMessageSubscription?.cancel();
      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen(
                (RemoteMessage message) async {
              debugPrint(
                'Foreground notification: ${message.notification?.title}',
              );
              await updateAppIconBadge();
            },
          );

      await _messageOpenedSubscription?.cancel();
      _messageOpenedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(
                (RemoteMessage message) async {
              debugPrint(
                'Notification opened: ${message.notification?.title}',
              );
              await handleOpenedNotification(message);
            },
          );
    } catch (e) {
      debugPrint('FCM setup skipped/error: $e');
    }
  }

  Future<void> handleOpenedNotification(
      RemoteMessage message,
      ) async {
    try {
      await updateAppIconBadge();

      final pageIndex =
      customerPageIndexFromData(message.data);

      if (pageIndex == null) {
        debugPrint(
          'No supported target_page found in notification.',
        );
        return;
      }

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        pendingCustomerInitialIndex = pageIndex;
        return;
      }

      var customer = await supabase
          .from('customers')
          .select('customer_id')
          .eq('customer_id', user.id)
          .maybeSingle();

      customer ??= await supabase
          .from('customers')
          .select('customer_id')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (customer == null) {
        debugPrint(
          'Opened notification does not belong to a Customer account.',
        );
        return;
      }

      final navigator = appNavigatorKey.currentState;

      if (navigator == null) {
        pendingCustomerInitialIndex = pageIndex;
        return;
      }

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => NavigationControl(
            initialIndex: pageIndex,
          ),
        ),
            (route) => false,
      );
    } catch (error) {
      debugPrint(
        'Failed to open notification target page: $error',
      );
    }
  }

  Future<void> saveTokenForCurrentUser(
      String fcmToken,
      ) async {
    try {
      final token = fcmToken.trim();

      if (token.isEmpty) return;

      final supabase =
          Supabase.instance.client;

      final user =
          supabase.auth.currentUser;

      // Not logged in yet.
      // Login and AuthGate will save the token later.
      if (user == null) {
        debugPrint(
          'FCM token refresh skipped because no user is logged in.',
        );
        return;
      }

      final admin = await supabase
          .from('admins')
          .select('admin_id')
          .eq('admin_id', user.id)
          .maybeSingle();

      if (admin != null) {
        await supabase
            .from('admin_fcm_tokens')
            .upsert(
          {
            'admin_id':
            admin['admin_id'].toString(),
            'fcm_token': token,
            'platform': 'Android',
            'device_name': 'Admin Device',
            'last_login':
            DateTime.now().toIso8601String(),
          },
          onConflict: 'fcm_token',
        );

        debugPrint(
          'Refreshed Admin FCM token saved.',
        );

        return;
      }

      var customer = await supabase
          .from('customers')
          .select('customer_id')
          .eq('customer_id', user.id)
          .maybeSingle();

      customer ??= await supabase
          .from('customers')
          .select('customer_id')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (customer == null) {
        debugPrint(
          'No customer or admin record found for refreshed token.',
        );
        return;
      }

      final customerId =
      customer['customer_id'].toString();

      await supabase
          .from('customer_fcm_tokens')
          .upsert(
        {
          'customer_id': customerId,
          'fcm_token': token,
          'platform': 'Android',
          'device_name': 'Customer Device',
          'last_login':
          DateTime.now().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );

      // Keep legacy column temporarily.
      await supabase
          .from('customers')
          .update({
        'fcm_token': token,
      }).eq(
        'customer_id',
        customerId,
      );

      debugPrint(
        'Refreshed Customer FCM token saved.',
      );
    } catch (error) {
      debugPrint(
        'Failed to save refreshed FCM token: $error',
      );
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
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
  State<AuthGate> createState() =>
      _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase =
      Supabase.instance.client;

  bool _navigated = false;

  static const String rememberMeKey =
      'remember_me';

  static const String rememberedRoleKey =
      'remembered_role';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      checkLoginSession();
    });
  }

  Future<void> checkLoginSession() async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      final rememberMe =
          preferences.getBool(
            rememberMeKey,
          ) ??
              false;

      final rememberedRole =
      preferences.getString(
        rememberedRoleKey,
      );

      final user =
          supabase.auth.currentUser;

      // User did not allow the app to remember login.
      if (!rememberMe) {
        if (user != null) {
          await safeSignOut();
        }

        goLogin();
        return;
      }

      // Remember Me was ON, but Session is no longer valid.
      if (user == null) {
        await clearRememberSetting();
        goLogin();
        return;
      }

      final adminData = await supabase
          .from('admins')
          .select('admin_id')
          .eq('admin_id', user.id)
          .maybeSingle();

      if (adminData != null) {
        if (rememberedRole != null &&
            rememberedRole != 'admin') {
          await clearRememberSetting();
          await safeSignOut();
          goLogin();
          return;
        }

        await updateAdminFcmToken(
          user.id,
        );

        goAdmin();
        return;
      }

      var customerData = await supabase
          .from('customers')
          .select('customer_id')
          .eq('customer_id', user.id)
          .maybeSingle();

      customerData ??= await supabase
          .from('customers')
          .select('customer_id')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (customerData != null) {
        if (rememberedRole != null &&
            rememberedRole !=
                'customer') {
          await clearRememberSetting();
          await safeSignOut();
          goLogin();
          return;
        }

        await updateCustomerFcmToken(
          customerId:
          customerData['customer_id'].toString(),
        );

        goCustomer();
        return;
      }

      await clearRememberSetting();
      await safeSignOut();
      goLogin();
    } catch (error) {
      debugPrint(
        'AuthGate error: $error',
      );

      await clearRememberSetting();
      await safeSignOut();
      goLogin();
    }
  }

  Future<void> updateAdminFcmToken(
      String adminId,
      ) async {
    try {
      final fcmToken =
      await FirebaseMessaging.instance
          .getToken();

      if (fcmToken == null ||
          fcmToken.isEmpty) {
        return;
      }

      await supabase
          .from('admin_fcm_tokens')
          .upsert(
        {
          'admin_id': adminId,
          'fcm_token': fcmToken,
          'platform': 'Android',
          'device_name':
          'Admin Device',
          'last_login':
          DateTime.now()
              .toIso8601String(),
        },
        onConflict: 'fcm_token',
      );
    } catch (error) {
      debugPrint(
        'Failed to restore Admin FCM token: $error',
      );
    }
  }

  Future<void> updateCustomerFcmToken({
    required String customerId,
  }) async {
    try {
      final fcmToken =
      await FirebaseMessaging.instance.getToken();

      if (fcmToken == null ||
          fcmToken.trim().isEmpty) {
        debugPrint(
          'Customer FCM token is unavailable.',
        );
        return;
      }

      // Save this device separately.
      // Multiple devices for the same customer
      // will have separate rows.
      await supabase
          .from('customer_fcm_tokens')
          .upsert(
        {
          'customer_id': customerId,
          'fcm_token': fcmToken,
          'platform': 'Android',
          'device_name': 'Customer Device',
          'last_login':
          DateTime.now().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );

      // Keep the old column temporarily because some
      // existing notification functions may still use it.
      await supabase
          .from('customers')
          .update({
        'fcm_token': fcmToken,
      }).eq(
        'customer_id',
        customerId,
      );

      debugPrint(
        'Customer device registered successfully.',
      );
    } catch (error) {
      debugPrint(
        'Failed to register Customer device: $error',
      );
    }
  }

  Future<void> clearRememberSetting() async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.setBool(
        rememberMeKey,
        false,
      );

      await preferences.remove(
        rememberedRoleKey,
      );
    } catch (error) {
      debugPrint(
        'Failed to clear Remember Me: $error',
      );
    }
  }

  Future<void> safeSignOut() async {
    try {
      final user = supabase.auth.currentUser;

      final currentToken =
      await FirebaseMessaging.instance.getToken();

      if (user != null &&
          currentToken != null &&
          currentToken.trim().isNotEmpty) {
        final admin = await supabase
            .from('admins')
            .select('admin_id')
            .eq('admin_id', user.id)
            .maybeSingle();

        if (admin != null) {
          // Remove only this Admin device.
          await supabase
              .from('admin_fcm_tokens')
              .delete()
              .eq('admin_id', admin['admin_id'])
              .eq('fcm_token', currentToken);
        } else {
          var customer = await supabase
              .from('customers')
              .select('customer_id, fcm_token')
              .eq('customer_id', user.id)
              .maybeSingle();

          customer ??= await supabase
              .from('customers')
              .select('customer_id, fcm_token')
              .eq('auth_user_id', user.id)
              .maybeSingle();

          if (customer != null) {
            final customerId =
            customer['customer_id'].toString();

            // Remove only this Customer device.
            await supabase
                .from('customer_fcm_tokens')
                .delete()
                .eq('customer_id', customerId)
                .eq('fcm_token', currentToken);

            // Clear legacy token only when it matches
            // this current device.
            final legacyToken =
            customer['fcm_token']?.toString();

            if (legacyToken == currentToken) {
              await supabase
                  .from('customers')
                  .update({
                'fcm_token': null,
              }).eq(
                'customer_id',
                customerId,
              );
            }
          }
        }
      }
    } catch (error) {
      debugPrint(
        'Failed to remove device token during automatic sign out: $error',
      );
    }

    try {
      await supabase.auth.signOut();
    } catch (error) {
      debugPrint(
        'Sign out skipped/error: $error',
      );
    }
  }

  void goLogin() {
    if (!mounted || _navigated) return;

    _navigated = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context)
          .pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
          const LoginPage(),
        ),
      );
    });
  }

  void goCustomer() {
    if (!mounted || _navigated) return;

    _navigated = true;

    final initialIndex =
        pendingCustomerInitialIndex ?? 0;

    pendingCustomerInitialIndex = null;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context)
          .pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              NavigationControl(
                initialIndex: initialIndex,
              ),
        ),
      );
    });
  }

  void goAdmin() {
    if (!mounted || _navigated) return;

    _navigated = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context)
          .pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
          const AdminMainPage(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor:
      Color(0xFFD7E5FA),
      body: Center(
        child:
        CircularProgressIndicator(),
      ),
    );
  }
}

