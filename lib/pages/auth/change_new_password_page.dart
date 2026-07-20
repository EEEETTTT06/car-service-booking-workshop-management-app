import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import '../../services/supabase_service.dart';

class ChangeNewPasswordPage extends StatefulWidget {
  const ChangeNewPasswordPage({super.key});

  @override
  State<ChangeNewPasswordPage> createState() => _ChangeNewPasswordPageState();
}

class _ChangeNewPasswordPageState extends State<ChangeNewPasswordPage> {
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool hideNewPassword = true;
  bool hideConfirmPassword = true;

  String? passwordError;
  String? confirmPasswordError;

  bool isValidPassword(String password) {
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return password.length >= 8 && hasLetter && hasNumber;
  }

  Future<void> changePassword() async {
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    setState(() {
      passwordError = null;
      confirmPasswordError = null;
    });

    if (newPassword.isEmpty) {
      setState(() {
        passwordError = 'Please enter a new password.';
      });
      return;
    }

    if (!isValidPassword(newPassword)) {
      setState(() {
        passwordError =
        'Password must be at least 8 characters and include letters and numbers.';
      });
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        confirmPasswordError = 'Please confirm your password.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        confirmPasswordError = 'Password does not match.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      await supabase.auth.signOut();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Success'),
          content: const Text(
            'Your password has been changed successfully.\n\nPlease login again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginPage(),
                  ),
                      (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      setState(() {
        passwordError = 'Failed to change password. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Widget buildPasswordInput({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggle,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF339BFF),
              Color(0xFFB9D9FF),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.password, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'Create New Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              buildPasswordInput(
                controller: newPasswordController,
                hintText: 'New password',
                icon: Icons.lock,
                obscureText: hideNewPassword,
                errorText: passwordError,
                onToggle: () {
                  setState(() {
                    hideNewPassword = !hideNewPassword;
                  });
                },
              ),

              const SizedBox(height: 8),

              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Password must be at least 8 characters and include letters and numbers.',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              buildPasswordInput(
                controller: confirmPasswordController,
                hintText: 'Confirm new password',
                icon: Icons.lock_outline,
                obscureText: hideConfirmPassword,
                errorText: confirmPasswordError,
                onToggle: () {
                  setState(() {
                    hideConfirmPassword = !hideConfirmPassword;
                  });
                },
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD54F),
                    foregroundColor: const Color(0xFF0F4C81),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: isLoading ? null : changePassword,
                  child: Text(
                    isLoading ? 'Changing...' : 'Confirm',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}