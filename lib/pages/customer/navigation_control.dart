import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'customer_dashboard_content.dart';
import 'my_vehicles_page.dart';
import 'book_service_page.dart';
import 'customer_quotations_page.dart';
import 'service_records_page.dart';
import 'customer_edit_profile_page.dart';
import 'customer_settings_page.dart';
import 'customer_notification_page.dart';

class NavigationControl extends StatefulWidget {
  final int initialIndex;

  const NavigationControl({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<NavigationControl> createState() => _NavigationControlState();
}

class _NavigationControlState extends State<NavigationControl> {
  final supabase = Supabase.instance.client;

  late int currentIndex;
  bool notificationOn = true;
  bool isLoadingProfile = false;

  Map<String, String> customerProfile = {
    'name': 'Customer',
    'email': '',
    'phone': '',
    'profile_image_url': '',
  };

  @override
  void initState() {
    super.initState();

    final requestedIndex = widget.initialIndex;

    if (requestedIndex < 0) {
      currentIndex = 0;
    } else if (requestedIndex > 4) {
      currentIndex = 4;
    } else {
      currentIndex = requestedIndex;
    }

    loadCustomerProfile();
  }

  Future<void> loadCustomerProfile() async {
    setState(() => isLoadingProfile = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final response = await supabase
          .from('customers')
          .select('name, email, phone, profile_image_url')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (response != null) {
        setState(() {
          customerProfile = {
            'name': (response['name'] ?? 'Customer').toString(),
            'email': (response['email'] ?? user.email ?? '').toString(),
            'phone': (response['phone'] ?? '').toString(),
            'profile_image_url':
            (response['profile_image_url'] ?? '')
                .toString(),
          };
        });
      }
    } catch (error) {
      debugPrint('Failed to load customer profile: $error');
    } finally {
      if (mounted) setState(() => isLoadingProfile = false);
    }
  }

  void changePage(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  Future<void> logoutCustomer() async {
    try {
      final user = supabase.auth.currentUser;

      final currentToken =
      await FirebaseMessaging.instance.getToken();

      if (user != null &&
          currentToken != null &&
          currentToken.trim().isNotEmpty) {
        final customer = await supabase
            .from('customers')
            .select('customer_id, fcm_token')
            .eq('auth_user_id', user.id)
            .maybeSingle();

        final customerId =
        customer?['customer_id']?.toString();

        if (customerId != null &&
            customerId.isNotEmpty) {
          // Delete only this device's token.
          await supabase
              .from('customer_fcm_tokens')
              .delete()
              .eq('customer_id', customerId)
              .eq('fcm_token', currentToken);

          // Clear the old single-token column only when
          // it belongs to this current device.
          final oldToken =
          customer?['fcm_token']?.toString();

          if (oldToken == currentToken) {
            await supabase
                .from('customers')
                .update({
              'fcm_token': null,
            })
                .eq('customer_id', customerId);
          }
        }
      }
    } catch (error) {
      debugPrint(
        'Failed to remove customer FCM token during logout: $error',
      );
    }

    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.remove('remember_me');
      await preferences.remove('remembered_role');
    } catch (error) {
      debugPrint(
        'Failed to clear Remember Me settings: $error',
      );
    }

    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
          (route) => false,
    );
  }

  void showLogoutConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Confirm Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to logout?\n\nYou will need to login again to access your account.',
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await logoutCustomer();
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  String get customerProfileImageUrl {
    return customerProfile['profile_image_url']
        ?.trim() ??
        '';
  }

  Widget buildCustomerProfileImage({
    required double size,
  }) {
    if (customerProfileImageUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFD7E5FA),
        child: Icon(
          Icons.person,
          size: size * 0.58,
          color: const Color(0xFF339BFF),
        ),
      );
    }

    return Image.network(
      customerProfileImageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (
          context,
          error,
          stackTrace,
          ) {
        return Container(
          width: size,
          height: size,
          color: const Color(0xFFD7E5FA),
          child: Icon(
            Icons.person,
            size: size * 0.58,
            color: const Color(0xFF339BFF),
          ),
        );
      },
    );
  }

  Widget buildCustomerAvatar({
    required double size,
    double borderWidth = 3,
  }) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: buildCustomerProfileImage(
          size: size - (borderWidth * 2),
        ),
      ),
    );
  }

  void showCustomerProfilePicturePreview() {
    if (customerProfileImageUrl.isEmpty) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final screenSize =
            MediaQuery.of(dialogContext).size;

        final previewSize =
        screenSize.width < 520
            ? screenSize.width - 34
            : 470.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(17),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: previewSize,
                height: previewSize,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                  BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color:
                      Colors.black.withOpacity(0.36),
                      blurRadius: 28,
                      offset:
                      const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    customerProfileImageUrl,
                    width: previewSize,
                    height: previewSize,
                    fit: BoxFit.contain,
                    errorBuilder: (
                        context,
                        error,
                        stackTrace,
                        ) {
                      return const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 70,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Pinch to zoom the profile picture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void showCustomerMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Customer Menu',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 290,
              height: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7E5FA),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: customerProfileImageUrl.isEmpty
                                ? null
                                : showCustomerProfilePicturePreview,
                            child: buildCustomerAvatar(
                              size: 92,
                              borderWidth: 4,
                            ),
                          ),
                          if (customerProfileImageUrl.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Tap picture to view',
                              style: TextStyle(
                                color: Colors.black45,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            isLoadingProfile
                                ? 'Loading...'
                                : customerProfile['name']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            customerProfile['email']!.isEmpty
                                ? 'No email'
                                : customerProfile['email']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            customerProfile['phone']!.isEmpty
                                ? 'No phone number'
                                : customerProfile['phone']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Customer Account',
                              style: TextStyle(
                                color: Color(0xFF339BFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    sidebarItem(
                      icon: Icons.edit,
                      title: 'Edit Profile',
                      subtitle: 'Update your account information',
                      onTap: () async {
                        Navigator.pop(context);

                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerEditProfilePage(
                              customerProfile: customerProfile,
                              onProfileUpdated: (updatedProfile) {
                                setState(() {
                                  customerProfile = {
                                    ...customerProfile,
                                    ...updatedProfile,
                                  };
                                });
                              },
                            ),
                          ),
                        );

                        await loadCustomerProfile();
                      },
                    ),

                    sidebarItem(
                      icon: Icons.notifications,
                      title: 'Notifications',
                      subtitle: 'View all notification messages',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CustomerNotificationPage(),
                          ),
                        );
                      },
                    ),

                    sidebarItem(
                      icon: Icons.settings,
                      title: 'Settings',
                      subtitle: 'Notification preferences',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerSettingsPage(
                              notificationOn: notificationOn,
                              onNotificationChanged: (value) {
                                setState(() {
                                  notificationOn = value;
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),

                    const Spacer(),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showLogoutConfirmDialog();
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'Logout',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
    );
  }

  Widget sidebarItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFD7E5FA),
          child: Icon(icon, color: const Color(0xFF339BFF)),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const profileButtonSize = 42.0;

    final profileButtonTop =
        MediaQuery.of(context).padding.top +
            ((kToolbarHeight - profileButtonSize) / 2);

    final pages = [
      CustomerDashboardContent(onNavigate: changePage),
      const MyVehiclesPage(),
      const BookServicePage(),
      const CustomerQuotationPage(),
      const ServiceRecordsPage(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          pages[currentIndex],
          Positioned(
            left: 12,
            top: profileButtonTop,
            child: SizedBox(
              width: profileButtonSize,
              height: profileButtonSize,
              child: FloatingActionButton(
                heroTag: 'customerProfileButton',
                elevation: 4,
                backgroundColor: Colors.white,
                shape: const CircleBorder(),
                onPressed: showCustomerMenu,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: buildCustomerProfileImage(
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF339BFF),
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          elevation: 0,
          onTap: changePage,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_car_rounded),
              label: 'Vehicles',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'Booking',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Quotation',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'Records',
            ),
          ],
        ),
      ),
    );
  }
}