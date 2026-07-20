import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_page.dart';
import 'admin_profile_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AdminSidebar {
  static bool notificationOn = true;

  static void show(BuildContext context) {
    final supabase = Supabase.instance.client;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Admin Menu',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _loadSidebarData(supabase),
          builder: (context, snapshot) {
            final data = snapshot.data ??
                {
                  'name': 'Admin',
                  'email': '',
                  'role': 'Workshop Administrator',
                  'vehicles': '0',
                  'customers': '0',
                  'todayBookings': '0',
                };

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
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF339BFF),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF339BFF),
                                Color(0xFF5CB6FF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF339BFF).withOpacity(0.30),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [

                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const CircleAvatar(
                                  radius: 42,
                                  backgroundColor: Colors.white,
                                  child: Icon(
                                    Icons.admin_panel_settings_rounded,
                                    size: 48,
                                    color: Color(0xFF339BFF),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Text(
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                    ? 'Loading...'
                                    : data['name']!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                data['email']!.isEmpty
                                    ? 'No Email'
                                    : data['email']!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),

                              const SizedBox(height: 16),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.28),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white38,
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [

                                    Icon(
                                      Icons.verified_user,
                                      color: Colors.white,
                                      size: 16,
                                    ),

                                    SizedBox(width: 6),

                                    Text(
                                      data['role'].toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Workshop Overview',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _overviewMiniCard(
                              icon: Icons.directions_car,
                              title: 'Vehicles',
                              value: data['vehicles'].toString(),
                            ),
                            const SizedBox(width: 10),
                            _overviewMiniCard(
                              icon: Icons.people,
                              title: 'Customers',
                              value: data['customers'].toString(),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        _fullOverviewCard(
                            icon: Icons.calendar_month,
                            title: 'Bookings',
                          value: data['todayBookings'].toString(),
                        ),

                        const SizedBox(height: 18),
                        _sidebarItem(
                          context: context,
                          icon: Icons.person,
                          title: 'Admin Profile',
                          subtitle: 'View & edit your profile',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminProfilePage(),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 12),
                        _sidebarItem(
                          context: context,
                          icon: Icons.notifications,
                          title: 'Notification',
                          subtitle: 'Manage notification settings',
                          onTap: () {
                            Navigator.pop(context);
                            _showNotificationDialog(context);
                          },
                        ),

                          const SizedBox(height: 18),
                            const Divider(
                              height: 32,
                              thickness: 1,
                              color: Color(0xFFE5E5E5),
                            ),
                        const Text(
                          'Workshop Management System',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 4),

                        const Text(
                          'Version 1.0.0',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              elevation: 5,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              _showLogoutDialog(context, supabase);
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            );
          },
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

  static Future<Map<String, dynamic>> _loadSidebarData(
      SupabaseClient supabase,
      ) async {
    final user = supabase.auth.currentUser;

    String name = 'Admin';
    String email = '';
    String role = 'Workshop Administrator';

    if (user != null) {
      final admin = await supabase
          .from('admins')
          .select('name,email,role')
          .eq('admin_id', user.id)
          .maybeSingle();

      if (admin != null) {
        name = admin['name'] ?? 'Admin';
        email = admin['email'] ?? user.email ?? '';
        role = admin['role'] ?? 'Workshop Administrator';
      }
    }

    // Total Vehicles
    final vehicles = await supabase
        .from('vehicles')
        .select('vehicle_id');

    // Total Customers
    final customers = await supabase
        .from('customers')
        .select('customer_id');

    // Today's Bookings
    final today = DateTime.now().toIso8601String().split('T').first;

    final bookings = await supabase
        .from('bookings')
        .select('booking_id')
        .eq('appointment_date', today);

    return {
      'name': name,
      'email': email,
      'role': role,
      'vehicles': vehicles.length,
      'customers': customers.length,
      'todayBookings': bookings.length,
    };
  }

  static Widget _sidebarItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD),
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
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF339BFF),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.chevron_right,
            size: 18,
            color: Color(0xFF339BFF),
          ),
        ),
      ),
    );
  }

  static Widget _overviewMiniCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF339BFF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 18,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF339BFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _fullOverviewCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF339BFF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Today's Appointments",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF339BFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showNotificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        bool tempNotification = notificationOn;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Notification Setting'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF339BFF),
                title: const Text('Notification'),
                subtitle: Text(
                  tempNotification
                      ? 'Admin notification is turned on'
                      : 'Admin notification is turned off',
                ),
                value: tempNotification,
                onChanged: (value) {
                  setDialogState(() {
                    tempNotification = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    notificationOn = tempNotification;
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          notificationOn
                              ? 'Notification turned on.'
                              : 'Notification turned off.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _showLogoutDialog(
      BuildContext context,
      SupabaseClient supabase,
      ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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

                try {
                  final token = await FirebaseMessaging.instance.getToken();

                  if (token != null && token.isNotEmpty) {
                    await supabase
                        .from('admin_fcm_tokens')
                        .delete()
                        .eq('fcm_token', token);

                    debugPrint('Current admin device removed.');
                  }

                  await supabase.auth.signOut();

                  if (!context.mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(),
                    ),
                        (route) => false,
                  );
                } catch (e) {
                  debugPrint('Logout error: $e');

                  await supabase.auth.signOut();

                  if (!context.mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(),
                    ),
                        (route) => false,
                  );
                }
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}