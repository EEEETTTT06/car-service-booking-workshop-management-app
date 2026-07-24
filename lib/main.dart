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
import 'pages/admin/admin_bookings_page.dart';
import 'pages/admin/admin_quotations_page.dart';
import 'pages/admin/pending_service_page.dart';
import 'pages/admin/vehicle_management_page.dart';
import 'pages/common/notification_navigation_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey =
GlobalKey<NavigatorState>();

Map<String, dynamic>? pendingPushNotification;

Map<String, dynamic> notificationPayloadFromMessage(
    RemoteMessage message,
    ) {
  final payload = Map<String, dynamic>.from(
    message.data,
  );

  final title = message.notification?.title?.trim();
  final body = message.notification?.body?.trim();

  if (title != null && title.isNotEmpty) {
    payload['title'] = title;
  }

  if (body != null && body.isNotEmpty) {
    payload['message'] = body;
  }

  return payload;
}

String? cleanNotificationValue(dynamic value) {
  final text = value?.toString().trim();

  if (text == null ||
      text.isEmpty ||
      text.toLowerCase() == 'null') {
    return null;
  }

  return text;
}

Route<void>? buildPushNotificationRoute({
  required Map<String, dynamic> notification,
  required bool isAdmin,
}) {
  final target =
  NotificationNavigationService.resolveTargetPage(
    notification: notification,
    isAdmin: isAdmin,
  );

  if (target == null) {
    return null;
  }

  if (!isAdmin) {
    int? customerIndex;

    switch (target) {
      case 'my_vehicles':
        customerIndex = 1;
        break;
      case 'my_bookings':
        customerIndex = 2;
        break;
      case 'customer_quotations':
        customerIndex = 3;
        break;
      case 'service_records':
        customerIndex = 4;
        break;
    }

    if (customerIndex == null) {
      return null;
    }

    return MaterialPageRoute<void>(
      builder: (_) => NavigationControl(
        initialIndex: customerIndex!,
      ),
    );
  }

  final bookingId = cleanNotificationValue(
    notification['booking_id'],
  );
  final vehicleId = cleanNotificationValue(
    notification['vehicle_id'],
  );
  final plateNumber = cleanNotificationValue(
    notification['plate_number'],
  );

  int selectedIndex = 0;
  Widget? relatedPage;

  switch (target) {
    case 'admin_bookings':
      selectedIndex = 1;
      relatedPage = AdminBookingsPage(
        initialBookingId: bookingId,
      );
      break;
    case 'pending_service':
      selectedIndex = 1;
      relatedPage = const PendingServicePage();
      break;
    case 'admin_quotations':
      selectedIndex = 1;
      relatedPage = const AdminQuotationsPage();
      break;
    case 'vehicle_management':
      selectedIndex = 2;
      relatedPage = VehicleManagementPage(
        initialVehicleId: vehicleId,
        initialPlateNumber: plateNumber,
      );
      break;
    case 'admin_customers':
      selectedIndex = 2;
      break;
    case 'admin_records':
      selectedIndex = 4;
      break;
    default:
      return null;
  }

  return MaterialPageRoute<void>(
    builder: (_) => AdminMainPage(
      initialIndex: selectedIndex,
      initialRelatedPage: relatedPage,
    ),
  );
}

bool openPushNotificationRoute({
  required Map<String, dynamic> notification,
  required bool isAdmin,
}) {
  final route = buildPushNotificationRoute(
    notification: notification,
    isAdmin: isAdmin,
  );

  final navigator = appNavigatorKey.currentState;

  if (route == null || navigator == null) {
    return false;
  }

  /*
   * Keep the current dashboard route under the
   * notification target. Related Admin pages have
   * their own Back button, so removing every older
   * route would leave nothing to return to and may
   * display a black screen.
   */
  navigator.push(route);

  return true;
}

Future<bool?> resolveCurrentUserIsAdmin() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return null;
  }

  final admin = await supabase
      .from('admins')
      .select('admin_id')
      .eq('admin_id', user.id)
      .maybeSingle();

  if (admin != null) {
    return true;
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

  if (customer != null) {
    return false;
  }

  return null;
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
    pendingPushNotification =
        notificationPayloadFromMessage(
          initialMessage,
        );
  }

  runApp(const CarServiceApp());
}

class CarServiceApp extends StatefulWidget {
  const CarServiceApp({super.key});

  @override
  State<CarServiceApp> createState() => _CarServiceAppState();
}

class _CarServiceAppState extends State<CarServiceApp>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  bool _isRegisteringFcmToken = false;
  String? _lastRegisteredDeviceKey;
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setupFCM();
    });
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    unawaited(
      registerCurrentDeviceToken(
        reason: 'app resumed',
      ),
    );
  }

  Future<void> setupFCM() async {
    try {
      final messaging =
          FirebaseMessaging.instance;

      await messaging.setAutoInitEnabled(true);

      final permission =
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint(
        'Notification permission: '
            '${permission.authorizationStatus}',
      );

      await registerCurrentDeviceToken(
        reason: 'FCM setup',
      );

      await _tokenRefreshSubscription
          ?.cancel();

      _tokenRefreshSubscription =
          messaging.onTokenRefresh.listen(
                (newToken) async {
              debugPrint(
                'FCM TOKEN REFRESHED: $newToken',
              );

              _lastRegisteredDeviceKey = null;

              await saveTokenForCurrentUser(
                newToken,
              );
            },
            onError: (error) {
              debugPrint(
                'Failed to refresh FCM token: '
                    '$error',
              );
            },
          );

      await _authStateSubscription
          ?.cancel();

      _authStateSubscription =
          Supabase.instance.client.auth
              .onAuthStateChange
              .listen(
                (authState) async {
              final event = authState.event;

              debugPrint(
                'Auth state changed for FCM: '
                    '$event',
              );

              if (event ==
                  AuthChangeEvent.signedIn ||
                  event ==
                      AuthChangeEvent
                          .tokenRefreshed ||
                  event ==
                      AuthChangeEvent
                          .initialSession ||
                  event ==
                      AuthChangeEvent
                          .userUpdated) {
                _lastRegisteredDeviceKey =
                null;

                /*
             * Give LoginPage/AuthGate a short
             * moment to finish role/profile
             * loading before saving this device.
             */
                await Future<void>.delayed(
                  const Duration(
                    milliseconds: 250,
                  ),
                );

                await registerCurrentDeviceToken(
                  reason:
                  'auth state $event',
                );
              }

              if (event ==
                  AuthChangeEvent.signedOut) {
                _lastRegisteredDeviceKey =
                null;
              }
            },
            onError: (error) {
              debugPrint(
                'FCM auth listener error: '
                    '$error',
              );
            },
          );

      await updateAppIconBadge();

      await _foregroundMessageSubscription
          ?.cancel();

      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen(
                (RemoteMessage message) async {
              debugPrint(
                'Foreground notification: '
                    '${message.notification?.title}',
              );

              debugPrint(
                'Foreground notification data: '
                    '${message.data}',
              );

              await updateAppIconBadge();
            },
          );

      await _messageOpenedSubscription
          ?.cancel();

      _messageOpenedSubscription =
          FirebaseMessaging
              .onMessageOpenedApp
              .listen(
                (RemoteMessage message) async {
              debugPrint(
                'Notification opened: '
                    '${message.notification?.title}',
              );

              debugPrint(
                'Opened notification data: '
                    '${message.data}',
              );

              await handleOpenedNotification(
                message,
              );
            },
          );
    } catch (error, stackTrace) {
      debugPrint(
        'FCM setup skipped/error: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );
    }
  }

  Future<void> registerCurrentDeviceToken({
    required String reason,
  }) async {
    if (_isRegisteringFcmToken) {
      debugPrint(
        'FCM registration already running. '
            'Skipped: $reason',
      );
      return;
    }

    final user =
        Supabase.instance.client.auth
            .currentUser;

    if (user == null) {
      debugPrint(
        'FCM registration waiting for login. '
            'Reason: $reason',
      );
      return;
    }

    _isRegisteringFcmToken = true;

    try {
      final token =
      await FirebaseMessaging.instance
          .getToken();

      if (token == null ||
          token.trim().isEmpty) {
        debugPrint(
          'FCM token is unavailable. '
              'Reason: $reason',
        );
        return;
      }

      final normalizedToken =
      token.trim();

      final deviceKey =
          '${user.id}|$normalizedToken';

      if (_lastRegisteredDeviceKey ==
          deviceKey) {
        debugPrint(
          'FCM device is already registered. '
              'Reason: $reason',
        );
        return;
      }

      await saveTokenForCurrentUser(
        normalizedToken,
      );

      _lastRegisteredDeviceKey =
          deviceKey;

      debugPrint(
        'FCM device registration completed. '
            'Reason: $reason',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'FCM device registration failed: '
            '$error',
      );

      debugPrint(
        stackTrace.toString(),
      );
    } finally {
      _isRegisteringFcmToken = false;
    }
  }

  Future<void> handleOpenedNotification(
      RemoteMessage message,
      ) async {
    try {
      await updateAppIconBadge();

      final notification =
      notificationPayloadFromMessage(
        message,
      );

      if (notification.isEmpty) {
        debugPrint(
          'Opened Push Notification has no routing data.',
        );
        return;
      }

      final isAdmin =
      await resolveCurrentUserIsAdmin();

      if (isAdmin == null) {
        pendingPushNotification =
            notification;

        debugPrint(
          'Push Notification routing is waiting for a valid login session.',
        );
        return;
      }

      final opened =
      openPushNotificationRoute(
        notification: notification,
        isAdmin: isAdmin,
      );

      if (!opened) {
        pendingPushNotification =
            notification;

        debugPrint(
          'Push Notification target is not available yet.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to open Push Notification target page: $error',
      );
      debugPrint(stackTrace.toString());
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
        final adminId =
        admin['admin_id']
            .toString();

        await supabase
            .from('admin_fcm_tokens')
            .upsert(
          {
            'admin_id': adminId,
            'fcm_token': token,
            'platform': 'Android',
            'device_name':
            'Admin Device',
            'last_login':
            DateTime.now()
                .toIso8601String(),
          },
          onConflict: 'fcm_token',
        );

        debugPrint(
          'Admin FCM token saved. '
              'Admin ID: $adminId, '
              'token ending: '
              '${token.length > 8 ? token.substring(token.length - 8) : token}',
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
    WidgetsBinding.instance.removeObserver(this);
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    _authStateSubscription?.cancel();
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

        final pendingNotification =
            pendingPushNotification;

        if (pendingNotification != null) {
          pendingPushNotification = null;

          goPushNotification(
            notification: pendingNotification,
            isAdmin: true,
          );
        } else {
          goAdmin();
        }

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

        final pendingNotification =
            pendingPushNotification;

        if (pendingNotification != null) {
          pendingPushNotification = null;

          goPushNotification(
            notification: pendingNotification,
            isAdmin: false,
          );
        } else {
          goCustomer();
        }

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

  void goPushNotification({
    required Map<String, dynamic> notification,
    required bool isAdmin,
  }) {
    if (!mounted || _navigated) {
      return;
    }

    _navigated = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      final navigator =
          appNavigatorKey.currentState;

      if (navigator == null) {
        return;
      }

      final baseRoute =
      MaterialPageRoute<void>(
        builder: (_) => isAdmin
            ? const AdminMainPage()
            : const NavigationControl(),
      );

      final relatedRoute =
      buildPushNotificationRoute(
        notification: notification,
        isAdmin: isAdmin,
      );

      /*
       * A terminated app starts from AuthGate.
       * Replace that temporary gate with the normal
       * dashboard first, then push the related page.
       * Therefore the related page's Back button
       * always has a safe screen underneath it.
       */
      navigator.pushAndRemoveUntil(
        baseRoute,
            (route) => false,
      );

      if (relatedRoute == null) {
        return;
      }

      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        final currentNavigator =
            appNavigatorKey.currentState;

        if (currentNavigator == null) {
          return;
        }

        currentNavigator.push(
          relatedRoute,
        );
      });
    });
  }

  void goCustomer() {
    if (!mounted || _navigated) return;

    _navigated = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context)
          .pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
          const NavigationControl(),
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

