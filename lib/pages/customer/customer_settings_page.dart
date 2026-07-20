import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class CustomerSettingsPage extends StatefulWidget {
  final bool notificationOn;
  final Function(bool) onNotificationChanged;

  const CustomerSettingsPage({
    super.key,
    required this.notificationOn,
    required this.onNotificationChanged,
  });

  @override
  State<CustomerSettingsPage> createState() => _CustomerSettingsPageState();
}

class _CustomerSettingsPageState extends State<CustomerSettingsPage> {
  late bool notificationOn;
  bool isUpdating = false;
  @override
  void initState() {
    super.initState();
    notificationOn = widget.notificationOn;
  }

  Future<void> updateNotification(bool value) async {
    if (isUpdating) return;

    setState(() {
      isUpdating = true;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in.');
      }

      await supabase.from('customers').update({
        'notification_enabled': value,
      }).eq('auth_user_id', user.id);

      if (!mounted) return;

      setState(() {
        notificationOn = value;
      });

      widget.onNotificationChanged(value);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Notifications turned on.'
                : 'Notifications turned off.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update notification setting: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),

      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            decoration: const BoxDecoration(
              color: Color(0xFF339BFF),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: const Column(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.settings,
                    size: 52,
                    color: Color(0xFF339BFF),
                  ),
                ),

                SizedBox(height: 14),

                Text(
                  'Customer Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 6),

                Text(
                  'Manage your app preferences',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Notification Setting',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                Container(
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
                  child: SwitchListTile(
                    activeColor: const Color(0xFF339BFF),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    secondary: const CircleAvatar(
                      backgroundColor: Color(0xFFD7E5FA),
                      child: Icon(
                        Icons.notifications,
                        color: Color(0xFF339BFF),
                      ),
                    ),
                    title: const Text(
                      'Notifications',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      notificationOn
                          ? 'Receive booking, quotation and service updates.'
                          : 'Notifications are turned off.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: notificationOn,
                    onChanged: isUpdating
                        ? null
                        : updateNotification,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}