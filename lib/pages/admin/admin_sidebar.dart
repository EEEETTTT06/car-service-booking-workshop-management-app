import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_page.dart';
import 'admin_profile_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../common/app_result_message.dart';

class AdminSidebar {
  static bool notificationOn = true;

  static void show(BuildContext context) {
    final supabase = Supabase.instance.client;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Admin Menu',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (
          dialogContext,
          animation,
          secondaryAnimation,
          ) {
        final screenWidth =
            MediaQuery.of(dialogContext).size.width;

        final sidebarWidth =
        screenWidth < 380
            ? screenWidth * 0.90
            : 330.0;

        return FutureBuilder<Map<String, dynamic>>(
          future: _loadSidebarData(supabase),
          builder: (dialogContext, snapshot) {
            final data = snapshot.data ??
                {
                  'name': 'Admin',
                  'email': '',
                  'role': 'Workshop Administrator',
                  'vehicles': '0',
                  'customers': '0',
                  'todayBookings': '0',
                };

            final isLoading =
                snapshot.connectionState ==
                    ConnectionState.waiting;

            return Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: sidebarWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 24,
                        offset: const Offset(8, 0),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            18,
                            12,
                            12,
                            10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color:
                                  const Color(0xFFEAF4FF),
                                  borderRadius:
                                  BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.dashboard_customize_outlined,
                                  color: Color(0xFF339BFF),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Admin Menu',
                                      style: TextStyle(
                                        color: Color(0xFF1F2937),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Workshop management',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                  const Color(0xFFEAF4FF),
                                  foregroundColor:
                                  const Color(0xFF339BFF),
                                ),
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),

                        Expanded(
                          child: SingleChildScrollView(
                            physics:
                            const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              18,
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient:
                                    const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF248CF2),
                                        Color(0xFF63B3FF),
                                      ],
                                    ),
                                    borderRadius:
                                    BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                        const Color(0xFF339BFF)
                                            .withOpacity(0.24),
                                        blurRadius: 16,
                                        offset:
                                        const Offset(0, 7),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding:
                                        const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: const CircleAvatar(
                                          radius: 34,
                                          backgroundColor:
                                          Colors.white,
                                          child: Icon(
                                            Icons
                                                .admin_panel_settings_rounded,
                                            size: 39,
                                            color:
                                            Color(0xFF339BFF),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 13),
                                      Text(
                                        isLoading
                                            ? 'Loading...'
                                            : data['name']
                                            .toString(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow:
                                        TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        data['email']
                                            .toString()
                                            .trim()
                                            .isEmpty
                                            ? 'No Email'
                                            : data['email']
                                            .toString(),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow:
                                        TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      const SizedBox(height: 13),
                                      Container(
                                        padding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 13,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withOpacity(0.18),
                                          borderRadius:
                                          BorderRadius.circular(20),
                                          border: Border.all(
                                            color: Colors.white
                                                .withOpacity(0.32),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize:
                                          MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.verified_user,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                data['role']
                                                    .toString(),
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis,
                                                style:
                                                const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                  FontWeight.bold,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                const _SidebarSectionTitle(
                                  title: 'Quick Summary',
                                  subtitle:
                                  'Current workshop overview',
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    _overviewMiniCard(
                                      icon: Icons.directions_car,
                                      title: 'Vehicles',
                                      value:
                                      data['vehicles'].toString(),
                                    ),
                                    const SizedBox(width: 10),
                                    _overviewMiniCard(
                                      icon: Icons.people_outline,
                                      title: 'Customers',
                                      value:
                                      data['customers'].toString(),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                _fullOverviewCard(
                                  icon: Icons.calendar_month_outlined,
                                  title: 'Today Bookings',
                                  value: data['todayBookings']
                                      .toString(),
                                ),

                                const SizedBox(height: 20),

                                const _SidebarSectionTitle(
                                  title: 'Account & Settings',
                                  subtitle:
                                  'Manage admin preferences',
                                ),
                                const SizedBox(height: 10),

                                _sidebarItem(
                                  context: dialogContext,
                                  icon: Icons.person_outline,
                                  title: 'Admin Profile',
                                  subtitle:
                                  'View and edit your information',
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const AdminProfilePage(),
                                      ),
                                    );
                                  },
                                ),

                                _sidebarItem(
                                  context: dialogContext,
                                  icon:
                                  Icons.notifications_outlined,
                                  title: 'Notification Setting',
                                  subtitle:
                                  'Turn admin notifications on or off',
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    _showNotificationDialog(
                                      context,
                                    );
                                  },
                                ),

                                const SizedBox(height: 8),

                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                    BorderRadius.circular(18),
                                    border: Border.all(
                                      color:
                                      Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color:
                                          Color(0xFFEAF4FF),
                                          borderRadius:
                                          BorderRadius.all(
                                            Radius.circular(12),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons
                                              .car_repair_outlined,
                                          color:
                                          Color(0xFF339BFF),
                                          size: 21,
                                        ),
                                      ),
                                      SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                          children: [
                                            Text(
                                              'Workshop Management System',
                                              style: TextStyle(
                                                color:
                                                Color(0xFF1F2937),
                                                fontSize: 12.5,
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(height: 3),
                                            Text(
                                              'Version 1.0.0',
                                              style: TextStyle(
                                                color:
                                                Colors.black45,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),

                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    style:
                                    OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: BorderSide(
                                        color: Colors.red
                                            .withOpacity(0.65),
                                      ),
                                      shape:
                                      RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(15),
                                      ),
                                    ),
                                    onPressed: () {
                                      _showLogoutDialog(
                                        dialogContext,
                                        supabase,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.logout,
                                      size: 20,
                                    ),
                                    label: const Text(
                                      'Logout',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
        );
      },
      transitionBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
          ) {
        final curvedAnimation =
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: child,
          ),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFF339BFF)
              .withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF339BFF),
            size: 22,
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black45,
            fontSize: 11,
            height: 1.3,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 21,
          color: Color(0xFF339BFF),
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: const Color(0xFF339BFF)
                .withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _fullOverviewCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFF339BFF)
              .withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: const Color(0xFF339BFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Appointments scheduled today',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF339BFF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showNotificationDialog(
      BuildContext context,
      ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool tempNotification =
            notificationOn;

        return StatefulBuilder(
          builder: (
              dialogContext,
              setDialogState,
              ) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
              const EdgeInsets.symmetric(
                horizontal: 22,
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                  BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(0.12),
                      blurRadius: 24,
                      offset:
                      const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color:
                        const Color(0xFFEAF4FF),
                        borderRadius:
                        BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons
                            .notifications_active_outlined,
                        color:
                        Color(0xFF339BFF),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Notification Setting',
                      style: TextStyle(
                        color:
                        Color(0xFF1F2937),
                        fontSize: 20,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose whether this admin device should receive workshop notifications.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tempNotification
                            ? const Color(0xFFEAF8EF)
                            : const Color(0xFFF5F7FA),
                        borderRadius:
                        BorderRadius.circular(18),
                      ),
                      child: SwitchListTile(
                        contentPadding:
                        EdgeInsets.zero,
                        activeColor:
                        const Color(0xFF339BFF),
                        title: Text(
                          tempNotification
                              ? 'Notifications On'
                              : 'Notifications Off',
                          style: const TextStyle(
                            color:
                            Color(0xFF1F2937),
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          tempNotification
                              ? 'Admin notifications are enabled.'
                              : 'Admin notifications are disabled.',
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                        ),
                        value:
                        tempNotification,
                        onChanged: (value) {
                          setDialogState(() {
                            tempNotification =
                                value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child:
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );
                            },
                            child:
                            const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child:
                          ElevatedButton(
                            style:
                            ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(
                                0xFF339BFF,
                              ),
                              foregroundColor:
                              Colors.white,
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                vertical: 13,
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  14,
                                ),
                              ),
                            ),
                            onPressed: () {
                              notificationOn =
                                  tempNotification;

                              Navigator.pop(
                                dialogContext,
                              );

                              AppResultMessage
                                  .success(
                                context,
                                message:
                                notificationOn
                                    ? 'Notification turned on.'
                                    : 'Notification turned off.',
                              );
                            },
                            child:
                            const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
          const EdgeInsets.symmetric(
            horizontal: 22,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(0.14),
                  blurRadius: 24,
                  offset:
                  const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFFFE8E8),
                    borderRadius:
                    BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color:
                    Color(0xFF1F2937),
                    fontSize: 21,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Are you sure you want to logout from the admin account on this device?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFFFF7F7),
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons
                            .phonelink_erase_outlined,
                        color: Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'This device will stop receiving admin push notifications after logout.',
                          style: TextStyle(
                            color:
                            Colors.black54,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        child:
                        const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child:
                      ElevatedButton.icon(
                        style:
                        ElevatedButton.styleFrom(
                          backgroundColor:
                          Colors.red,
                          foregroundColor:
                          Colors.white,
                          padding:
                          const EdgeInsets
                              .symmetric(
                            vertical: 13,
                          ),
                          shape:
                          RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius
                                .circular(
                              14,
                            ),
                          ),
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
                        icon: const Icon(
                          Icons.logout,
                          size: 19,
                        ),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SidebarSectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF339BFF),
            borderRadius:
            BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
