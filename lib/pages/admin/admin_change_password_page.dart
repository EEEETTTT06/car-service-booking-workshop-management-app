import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';

class AdminChangePasswordPage extends StatefulWidget {
  const AdminChangePasswordPage({super.key});

  @override
  State<AdminChangePasswordPage> createState() =>
      _AdminChangePasswordPageState();
}

class _AdminChangePasswordPageState
    extends State<AdminChangePasswordPage> {
  final currentPasswordController = TextEditingController();
  final otpController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String method = 'password';
  bool verified = false;
  bool loading = false;
  bool otpSent = false;

  bool hideCurrent = true;
  bool hideNew = true;
  bool hideConfirm = true;

  String? currentPasswordError;
  String? otpError;
  String? newPasswordError;
  String? confirmPasswordError;

  int remainingSeconds = 0;
  Timer? timer;

  String get email => supabase.auth.currentUser?.email ?? '';

  @override
  void dispose() {
    timer?.cancel();
    currentPasswordController.dispose();
    otpController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor:
        error ? Colors.red.shade600 : const Color(0xFF339BFF),
        content: Text(message),
      ),
    );
  }

  bool isValidPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  void switchMethod(String value) {
    timer?.cancel();

    setState(() {
      method = value;
      verified = false;
      loading = false;
      otpSent = false;
      remainingSeconds = 0;

      currentPasswordController.clear();
      otpController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      currentPasswordError = null;
      otpError = null;
      newPasswordError = null;
      confirmPasswordError = null;
    });
  }

  void startTimer() {
    timer?.cancel();

    setState(() {
      remainingSeconds = 60;
    });

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (remainingSeconds <= 1) {
        timer.cancel();
        setState(() => remainingSeconds = 0);
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  Future<void> verifyCurrentPassword() async {
    final password = currentPasswordController.text;

    setState(() {
      currentPasswordError = null;
    });

    if (password.isEmpty) {
      setState(() {
        currentPasswordError = 'Please enter your current password.';
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        currentPasswordError = 'Admin email is unavailable.';
      });
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      setState(() => verified = true);
      showMessage('Current password verified.');
    } on AuthException catch (error) {
      setState(() {
        currentPasswordError = error.message;
      });
    } catch (_) {
      setState(() {
        currentPasswordError = 'Incorrect current password.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendOtp() async {
    setState(() {
      otpError = null;
    });

    if (email.isEmpty) {
      setState(() {
        otpError = 'Admin email is unavailable.';
      });
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );

      if (!mounted) return;

      setState(() => otpSent = true);
      startTimer();
      showMessage('OTP code sent to $email.');
    } on AuthException catch (error) {
      setState(() {
        otpError = error.message;
      });
    } catch (_) {
      setState(() {
        otpError = 'Unable to send OTP code.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();

    setState(() {
      otpError = null;
    });

    if (otp.length != 8 || int.tryParse(otp) == null) {
      setState(() {
        otpError = 'Please enter the 8-digit OTP code.';
      });
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );

      if (!mounted) return;

      timer?.cancel();

      setState(() => verified = true);
      showMessage('OTP verified successfully.');
    } on AuthException catch (error) {
      setState(() {
        otpError = error.message;
      });
    } catch (_) {
      setState(() {
        otpError = 'Wrong or expired OTP code.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changePassword() async {
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    setState(() {
      newPasswordError = null;
      confirmPasswordError = null;
    });

    if (!verified) {
      showMessage('Please verify your identity first.', error: true);
      return;
    }

    if (!isValidPassword(newPassword)) {
      setState(() {
        newPasswordError =
        'Use at least 8 characters with letters and numbers.';
      });
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        confirmPasswordError = 'Please confirm your new password.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        confirmPasswordError = 'Passwords do not match.';
      });
      return;
    }

    if (method == 'password' &&
        newPassword == currentPasswordController.text) {
      setState(() {
        newPasswordError =
        'The new password must be different from the old password.';
      });
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text(
              'Password Changed',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Your admin password has been changed successfully.',
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF339BFF),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          );
        },
      );

      if (mounted) Navigator.pop(context);
    } on AuthException catch (error) {
      showMessage(
        'Failed to change password: ${error.message}',
        error: true,
      );
    } catch (_) {
      showMessage(
        'Failed to change password. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget buildMethodButton({
    required String value,
    required IconData icon,
    required String title,
  }) {
    final selected = method == value;

    return Expanded(
      child: InkWell(
        onTap: () => switchMethod(value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
            selected ? const Color(0xFFEAF4FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF339BFF)
                  : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? const Color(0xFF339BFF)
                    : Colors.black45,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? const Color(0xFF339BFF)
                      : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildVerificationCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose Verification Method',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              buildMethodButton(
                value: 'password',
                icon: Icons.password,
                title: 'Current Password',
              ),
              const SizedBox(width: 12),
              buildMethodButton(
                value: 'otp',
                icon: Icons.mark_email_read,
                title: 'Email OTP',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (method == 'password') ...[
            TextField(
              controller: currentPasswordController,
              obscureText: hideCurrent,
              enabled: !verified,
              decoration: inputDecoration(
                label: 'Current Password',
                icon: Icons.lock_outline,
                errorText: currentPasswordError,
                suffix: IconButton(
                  onPressed: () {
                    setState(() => hideCurrent = !hideCurrent);
                  },
                  icon: Icon(
                    hideCurrent
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                verified || loading ? null : verifyCurrentPassword,
                icon: const Icon(Icons.verified_user),
                label: Text(
                  verified
                      ? 'Current Password Verified'
                      : 'Verify Current Password',
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'OTP will be sent to:\n$email',
                style: const TextStyle(height: 1.4),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: loading || remainingSeconds > 0
                    ? null
                    : sendOtp,
                icon: const Icon(Icons.send),
                label: Text(
                  remainingSeconds > 0
                      ? 'Resend OTP in ${remainingSeconds}s'
                      : otpSent
                      ? 'Resend OTP Code'
                      : 'Send OTP Code',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 8,
              enabled: !verified,
              decoration: inputDecoration(
                label: '8-digit OTP Code',
                icon: Icons.password,
                errorText: otpError,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: verified || loading || !otpSent
                    ? null
                    : verifyOtp,
                icon: const Icon(Icons.mark_email_read),
                label: Text(
                  verified ? 'OTP Verified' : 'Verify OTP Code',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildNewPasswordCard() {
    return Opacity(
      opacity: verified ? 1 : 0.5,
      child: IgnorePointer(
        ignoring: !verified,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Create New Password',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: newPasswordController,
                obscureText: hideNew,
                decoration: inputDecoration(
                  label: 'New Password',
                  icon: Icons.lock,
                  errorText: newPasswordError,
                  suffix: IconButton(
                    onPressed: () {
                      setState(() => hideNew = !hideNew);
                    },
                    icon: Icon(
                      hideNew
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmPasswordController,
                obscureText: hideConfirm,
                decoration: inputDecoration(
                  label: 'Confirm New Password',
                  icon: Icons.lock_outline,
                  errorText: confirmPasswordError,
                  suffix: IconButton(
                    onPressed: () {
                      setState(() => hideConfirm = !hideConfirm);
                    },
                    icon: Icon(
                      hideConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Password must contain at least 8 characters, one letter and one number.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF339BFF),
                    foregroundColor: Colors.white,
                  ),
                  icon: loading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.lock_reset),
                  label: Text(
                    loading
                        ? 'Processing...'
                        : 'Change Password',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Change Password'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 30,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF339BFF),
                      Color(0xFF5CB6FF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.security,
                        color: Color(0xFF339BFF),
                        size: 38,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Secure Password Update',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Verify using your current password or email OTP.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              buildVerificationCard(),
              const SizedBox(height: 20),
              buildNewPasswordCard(),
            ],
          ),
        ),
      ),
    );
  }
}
