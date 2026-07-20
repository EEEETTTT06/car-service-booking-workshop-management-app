import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class CustomerEditProfilePage extends StatefulWidget {
  final Map<String, String> customerProfile;
  final Function(Map<String, String>) onProfileUpdated;

  const CustomerEditProfilePage({
    super.key,
    required this.customerProfile,
    required this.onProfileUpdated,
  });

  @override
  State<CustomerEditProfilePage> createState() =>
      _CustomerEditProfilePageState();
}

class _CustomerEditProfilePageState extends State<CustomerEditProfilePage> {
  final supabase = Supabase.instance.client;

  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController passwordController;

  bool obscurePassword = true;
  bool isSaving = false;

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.customerProfile['name'] ?? '',
    );
    emailController = TextEditingController(
      text: widget.customerProfile['email'] ?? '',
    );
    phoneController = TextEditingController(
      text: widget.customerProfile['phone'] ?? '',
    );

    passwordController = TextEditingController();

    scrollController.addListener(() {
      if (!mounted) return;

      final shouldShow = scrollController.offset > 180;

      if (shouldShow != showBackToTop) {
        setState(() {
          showBackToTop = shouldShow;
        });
      }
    });

    nameController.addListener(refreshHeader);
    phoneController.addListener(refreshHeader);
    passwordController.addListener(refreshHeader);
  }

  void refreshHeader() {
    if (!mounted) return;

    setState(() {});
  }

  void scrollToTop() {
    if (!scrollController.hasClients) return;

    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    nameController.removeListener(refreshHeader);
    phoneController.removeListener(refreshHeader);
    passwordController.removeListener(refreshHeader);

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    scrollController.dispose();

    super.dispose();
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final newPassword = passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      showMessage('Please complete name and phone number.');
      return;
    }

    if (newPassword.isNotEmpty && newPassword.length < 6) {
      showMessage('Password must be at least 6 characters.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in.');
      }

      await supabase.from('customers').update({
        'name': name,
        'phone': phone,
      }).eq('auth_user_id', user.id);

      if (newPassword.isNotEmpty) {
        await supabase.auth.updateUser(
          UserAttributes(
            password: newPassword,
          ),
        );
      }

      widget.onProfileUpdated({
        'name': name,
        'email': emailController.text.trim(),
        'phone': phone,
      });

      showMessage('Profile updated successfully.');

      if (!mounted) return;

      Navigator.pop(context);
    } catch (error) {
      showMessage('Failed to update profile: $error');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: const Color(0xFF339BFF),
          ),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: readOnly ? Colors.grey.shade200 : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildSummaryBox({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFD7E5FA),
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
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
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    value.isEmpty ? 'Not Provided' : value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                20,
                24,
                20,
                28,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF339BFF),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 52,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 47,
                      backgroundColor: Color(0xFFD7E5FA),
                      child: Icon(
                        Icons.person,
                        size: 58,
                        color: Color(0xFF339BFF),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    nameController.text.trim().isEmpty
                        ? 'Customer'
                        : nameController.text.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    emailController.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      buildSummaryBox(
                        icon: Icons.phone,
                        title: 'Phone',
                        value: phoneController.text.trim(),
                      ),
                      const SizedBox(width: 12),
                      buildSummaryBox(
                        icon: Icons.lock,
                        title: 'Password',
                        value: passwordController.text.isEmpty
                            ? 'No Change'
                            : 'Will Change',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile Information',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 14),

                  buildInputBox(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                  ),

                  buildInputBox(
                    controller: emailController,
                    label: 'Email',
                    icon: Icons.email,
                    readOnly: true,
                  ),

                  buildInputBox(
                    controller: phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone,
                  ),

                  buildInputBox(
                    controller: passwordController,
                    label: 'New Password (optional)',
                    icon: Icons.lock,
                    obscureText: obscurePassword,
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF339BFF),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Leave the password empty if you do not want to change it. A new password must contain at least 6 characters.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                      isSaving ? null : saveProfile,
                      icon: isSaving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.save),
                      label: Text(
                        isSaving
                            ? 'Saving...'
                            : 'Save Profile',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: showBackToTop
          ? FloatingActionButton.small(
        heroTag: 'customerEditProfileBackToTop',
        backgroundColor:
        const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: scrollToTop,
        child: const Icon(
          Icons.keyboard_arrow_up,
        ),
      )
          : null,
    );
  }
}