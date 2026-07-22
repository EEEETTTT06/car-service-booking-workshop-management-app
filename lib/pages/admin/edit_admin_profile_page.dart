import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/app_result_message.dart';

class EditAdminProfilePage extends StatefulWidget {
  final Map<String, String> adminProfile;

  const EditAdminProfilePage({
    super.key,
    required this.adminProfile,
  });

  @override
  State<EditAdminProfilePage> createState() =>
      _EditAdminProfilePageState();
}

class _EditAdminProfilePageState extends State<EditAdminProfilePage> {
  final supabase = Supabase.instance.client;

  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController roleController;

  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.adminProfile['name'] ?? '',
    );

    emailController = TextEditingController(
      text: widget.adminProfile['email'] ?? '',
    );

    phoneController = TextEditingController(
      text: widget.adminProfile['phone'] ?? '',
    );

    roleController = TextEditingController(
      text: widget.adminProfile['role'] ?? 'Workshop Administrator',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    roleController.dispose();
    super.dispose();
  }

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
      type: isError ? AppResultType.error : AppResultMessage.inferType(message),
    );
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty) {
      showMessage(
        'Please enter the admin name.',
        isError: true,
      );
      return;
    }

    if (phone.isEmpty) {
      showMessage(
        'Please enter the phone number.',
        isError: true,
      );
      return;
    }

    if (!RegExp(r'^01[0-9]{8,9}$').hasMatch(phone)) {
      showMessage(
        'Please enter a valid Malaysia phone number.',
        isError: true,
      );
      return;
    }

    final user = supabase.auth.currentUser;

    if (user == null) {
      showMessage(
        'Admin is not logged in.',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await supabase
          .from('admins')
          .update({
        'name': name,
        'phone': phone,
      })
          .eq('admin_id', user.id);

      final updatedProfile = Map<String, String>.from(
        widget.adminProfile,
      );

      updatedProfile['name'] = name;
      updatedProfile['email'] = emailController.text.trim();
      updatedProfile['phone'] = phone;
      updatedProfile['role'] = roleController.text.trim();

      if (!mounted) return;

      showMessage('Admin profile updated successfully.');

      await Future.delayed(
        const Duration(milliseconds: 400),
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        updatedProfile,
      );
    } catch (error) {
      showMessage(
        'Failed to update admin profile: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Widget buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 4,
            bottom: 8,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          decoration: InputDecoration(
            prefixIcon: Icon(
              icon,
              color: const Color(0xFF339BFF),
            ),
            suffixIcon: readOnly
                ? const Icon(
              Icons.lock_outline,
              color: Colors.black38,
              size: 20,
            )
                : null,
            filled: true,
            fillColor:
            readOnly ? Colors.grey.shade200 : Colors.white,
            hintText: 'Enter $label',
            helperText: helperText,
            helperMaxLines: 2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFF339BFF),
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildReadOnlyNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.20),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Color(0xFF339BFF),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Email and role cannot be changed here. '
                  'The administrator role can only be managed through Supabase.',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                height: 1.4,
              ),
            ),
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
        title: const Text('Edit Admin Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                20,
                22,
                20,
                28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF339BFF),
                    Color(0xFF5CB6FF),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
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
                      radius: 48,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 43,
                        backgroundColor: Color(0xFFD7E5FA),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 54,
                          color: Color(0xFF339BFF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    nameController.text.isEmpty
                        ? 'Administrator'
                        : nameController.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    emailController.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white38,
                      ),
                    ),
                    child: Text(
                      roleController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Admin Account Information',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Update the administrator’s personal account information.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    buildInputField(
                      controller: nameController,
                      label: 'Admin Name',
                      icon: Icons.person,
                    ),
                    const SizedBox(height: 16),
                    buildInputField(
                      controller: emailController,
                      label: 'Email Address',
                      icon: Icons.email,
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),
                    buildInputField(
                      controller: phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      helperText:
                      'Example: 0123456789 or 01112345678',
                    ),
                    const SizedBox(height: 16),
                    buildInputField(
                      controller: roleController,
                      label: 'Admin Role',
                      icon: Icons.verified_user,
                      readOnly: true,
                    ),
                    const SizedBox(height: 18),
                    buildReadOnlyNotice(),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed:
                        isSaving ? null : saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          const Color(0xFF339BFF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                          Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: isSaving
                            ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.save),
                        label: Text(
                          isSaving
                              ? 'Saving...'
                              : 'Save Admin Profile',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}