import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_change_password_page.dart';
import '../auth/login_page.dart';
import 'edit_admin_profile_page.dart';
import 'workshop_profile_setting_page.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = false;
  bool notificationEnabled = true;

  int totalVehicles = 0;
  int totalCustomers = 0;
  int todayBookings = 0;

  Map<String, String> adminProfile = {
    'name': 'Admin',
    'email': '',
    'phone': '',
    'role': 'Workshop Administrator',
    'workshop': 'Eric Auto Service Centre',
    'workshopPhone': '',
    'address': 'Johor Bahru, Malaysia',
    'workingHours': '9:00 AM - 6:00 PM',
    'logoUrl': '',
  };

  @override
  void initState() {
    super.initState();
    loadAdminProfile();
  }

  Future<void> loadAdminProfile() async {
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Admin not logged in.');

      final response = await supabase
          .from('admins')
          .select()
          .eq('admin_id', user.id)
          .maybeSingle();

      final workshopResponse = await supabase
          .from('workshop_profile')
          .select()
          .eq('id', 1)
          .maybeSingle();

      if (response == null) throw Exception('Admin profile not found.');

      final vehiclesResponse =
      await supabase.from('vehicles').select('vehicle_id');
      final customersResponse =
      await supabase.from('customers').select('customer_id');

      final today = DateTime.now().toIso8601String().split('T').first;
      final bookingsResponse = await supabase
          .from('bookings')
          .select('booking_id')
          .eq('appointment_date', today);

      if (!mounted) return;

      setState(() {
        adminProfile = {
          'name': (response['name'] ?? 'Admin').toString(),
          'email': (response['email'] ?? user.email ?? '').toString(),
          'phone': (response['phone'] ?? '').toString(),
          'role':
          (response['role'] ?? 'Workshop Administrator').toString(),
          'workshop':
          (workshopResponse?['workshop_name'] ?? 'SF Service Centre')
              .toString(),
          'workshopPhone': (workshopResponse?['phone'] ?? '').toString(),
          'address':
          (workshopResponse?['address'] ?? 'Johor Bahru, Malaysia')
              .toString(),
          'workingHours':
          (workshopResponse?['working_hours'] ?? '9:00 AM - 6:00 PM')
              .toString(),
          'logoUrl': (workshopResponse?['logo_url'] ?? '').toString(),
        };

        notificationEnabled = response['notification_enabled'] ?? true;
        totalVehicles = vehiclesResponse.length;
        totalCustomers = customersResponse.length;
        todayBookings = bookingsResponse.length;
      });
    } catch (error) {
      showMessage('Failed to load admin profile: $error', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> openEditAdminProfilePage() async {
    final updatedProfile = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditAdminProfilePage(adminProfile: adminProfile),
      ),
    );

    if (updatedProfile == null || !mounted) return;

    setState(() {
      adminProfile = {...adminProfile, ...updatedProfile};
    });

    await loadAdminProfile();
  }

  Future<void> openWorkshopProfilePage() async {
    final updatedProfile = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkshopProfileSettingPage(
          adminProfile: adminProfile,
        ),
      ),
    );

    if (updatedProfile == null || !mounted) return;

    setState(() {
      adminProfile = {...adminProfile, ...updatedProfile};
    });

    await loadAdminProfile();
  }

  void showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor:
        isError ? Colors.red.shade600 : const Color(0xFF339BFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> updateNotificationSetting(bool value) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      showMessage('Admin is not logged in.', isError: true);
      return;
    }

    try {
      await supabase.from('admins').update({
        'notification_enabled': value,
      }).eq('admin_id', user.id);

      if (!mounted) return;

      setState(() {
        notificationEnabled = value;
      });

      showMessage(
        value ? 'Notifications turned on.' : 'Notifications turned off.',
      );
    } catch (error) {
      showMessage(
        'Failed to update notification setting: $error',
        isError: true,
      );
    }
  }

  Future<void> logoutAdmin() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token != null && token.isNotEmpty) {
        await supabase
            .from('admin_fcm_tokens')
            .delete()
            .eq('fcm_token', token);
      }

      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    } catch (error) {
      debugPrint('Logout error: $error');

      try {
        await supabase.auth.signOut();
      } catch (_) {}

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    }
  }

  void showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFEAEA),
                child: Icon(Icons.logout, color: Colors.red),
              ),
              SizedBox(width: 12),
              Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out from this admin account?',
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await logoutAdmin();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildStatisticCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFEAF4FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF339BFF), size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF339BFF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProfileInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF339BFF), size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value.isEmpty ? 'Not Provided' : value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF339BFF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF339BFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildAccountActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF339BFF),
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: iconColor),
          ],
        ),
      ),
    );
  }

  Widget buildNotificationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.notifications_rounded,
              color: Color(0xFF339BFF),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Receive booking, quotation and service updates',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Switch(
            value: notificationEnabled,
            activeColor: const Color(0xFF339BFF),
            onChanged: updateNotificationSetting,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Admin Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_rounded),
            tooltip: 'Workshop Settings',
            onPressed: isLoading ? null : openWorkshopProfilePage,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadAdminProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF339BFF), Color(0xFF5CB6FF)],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
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
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 51,
                          backgroundColor: Color(0xFFD7E5FA),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 64,
                            color: Color(0xFF339BFF),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      adminProfile['name'] ?? 'Admin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      adminProfile['email'] ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_user,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            adminProfile['role'] ??
                                'Workshop Administrator',
                            style: const TextStyle(
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workshop Overview',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: buildStatisticCard(
                            icon: Icons.directions_car,
                            title: 'Vehicles',
                            value: totalVehicles.toString(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildStatisticCard(
                            icon: Icons.people,
                            title: 'Customers',
                            value: totalCustomers.toString(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildStatisticCard(
                            icon: Icons.calendar_today,
                            title: 'Today',
                            value: todayBookings.toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Profile Information',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 14),
                    buildProfileInfoCard(
                      icon: Icons.person,
                      title: 'Admin Name',
                      value: adminProfile['name'] ?? '',
                      subtitle: 'Editable',
                      onTap: openEditAdminProfilePage,
                    ),
                    buildProfileInfoCard(
                      icon: Icons.email,
                      title: 'Email Address',
                      value: adminProfile['email'] ?? '',
                      subtitle: 'Read Only',
                      onTap: openEditAdminProfilePage,
                    ),
                    buildProfileInfoCard(
                      icon: Icons.phone,
                      title: 'Phone Number',
                      value: adminProfile['phone'] ?? '',
                      subtitle: 'Editable',
                      onTap: openEditAdminProfilePage,
                    ),
                    buildProfileInfoCard(
                      icon: Icons.admin_panel_settings,
                      title: 'Administrator Role',
                      value: adminProfile['role'] ?? '',
                      subtitle: 'Managed by Supabase',
                      onTap: openEditAdminProfilePage,
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Account Settings',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 14),
                    buildNotificationCard(),
                    buildAccountActionCard(
                      icon: Icons.lock_reset,
                      title: 'Change Password',
                      subtitle: 'Verify by password or email OTP',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminChangePasswordPage(),
                          ),
                        );
                      },
                    ),
                    buildAccountActionCard(
                      icon: Icons.logout,
                      title: 'Logout',
                      subtitle:
                      'Sign out from the current admin account',
                      iconColor: Colors.red,
                      onTap: showLogoutDialog,
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: openEditAdminProfilePage,
                        icon: const Icon(Icons.manage_accounts),
                        label: const Text(
                          'Edit Admin Profile',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF339BFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: openWorkshopProfilePage,
                        icon: const Icon(Icons.storefront_rounded),
                        label: const Text(
                          'Workshop Profile Settings',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(
                      thickness: 1,
                      color: Color(0xFFE5E5E5),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Column(
                        children: [
                          Text(
                            'SF Service App',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Workshop Management Mobile Application',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
