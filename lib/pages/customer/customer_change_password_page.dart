import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_service.dart';
import '../common/app_result_message.dart';

class CustomerChangePasswordPage extends StatefulWidget {
  const CustomerChangePasswordPage({super.key});

  @override
  State<CustomerChangePasswordPage> createState() =>
      _CustomerChangePasswordPageState();
}

class _CustomerChangePasswordPageState
    extends State<CustomerChangePasswordPage> {
  final currentPasswordController =
  TextEditingController();
  final otpController = TextEditingController();
  final newPasswordController =
  TextEditingController();
  final confirmPasswordController =
  TextEditingController();

  String verificationMethod = 'password';

  bool isVerified = false;
  bool isLoading = false;
  bool isOtpSent = false;

  bool hideCurrentPassword = true;
  bool hideNewPassword = true;
  bool hideConfirmPassword = true;

  String? currentPasswordError;
  String? otpError;
  String? newPasswordError;
  String? confirmPasswordError;

  int remainingSeconds = 0;
  Timer? resendTimer;

  String get customerEmail =>
      supabase.auth.currentUser?.email ?? '';

  String get newPassword =>
      newPasswordController.text;

  bool get hasMinimumLength =>
      newPassword.length >= 8;

  bool get hasLetter =>
      RegExp(r'[A-Za-z]').hasMatch(newPassword);

  bool get hasNumber =>
      RegExp(r'[0-9]').hasMatch(newPassword);

  bool get hasSymbol =>
      RegExp(r'[^A-Za-z0-9\s]')
          .hasMatch(newPassword);

  bool get isStrongPassword =>
      hasMinimumLength &&
          hasLetter &&
          hasNumber &&
          hasSymbol;

  @override
  void initState() {
    super.initState();

    newPasswordController.addListener(
      refreshPasswordRules,
    );
  }

  @override
  void dispose() {
    resendTimer?.cancel();

    newPasswordController.removeListener(
      refreshPasswordRules,
    );

    currentPasswordController.dispose();
    otpController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  void refreshPasswordRules() {
    if (!mounted) return;

    setState(() {});
  }

  void showMessage(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
      type: isError
          ? AppResultType.error
          : AppResultMessage.inferType(message),
    );
  }

  void switchVerificationMethod(
      String value,
      ) {
    resendTimer?.cancel();

    setState(() {
      verificationMethod = value;
      isVerified = false;
      isLoading = false;
      isOtpSent = false;
      remainingSeconds = 0;

      currentPasswordController.clear();
      otpController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      currentPasswordError = null;
      otpError = null;
      newPasswordError = null;
      confirmPasswordError = null;

      hideCurrentPassword = true;
      hideNewPassword = true;
      hideConfirmPassword = true;
    });
  }

  void startResendTimer() {
    resendTimer?.cancel();

    setState(() {
      remainingSeconds = 60;
    });

    resendTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (remainingSeconds <= 1) {
          timer.cancel();

          setState(() {
            remainingSeconds = 0;
          });
        } else {
          setState(() {
            remainingSeconds--;
          });
        }
      },
    );
  }

  Future<void> verifyCurrentPassword() async {
    final currentPassword =
        currentPasswordController.text;

    setState(() {
      currentPasswordError = null;
    });

    if (currentPassword.isEmpty) {
      setState(() {
        currentPasswordError =
        'Please enter your current password.';
      });
      return;
    }

    if (customerEmail.isEmpty) {
      setState(() {
        currentPasswordError =
        'Customer email is unavailable.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.signInWithPassword(
        email: customerEmail,
        password: currentPassword,
      );

      if (!mounted) return;

      setState(() {
        isVerified = true;
      });

      showMessage(
        'Current password verified successfully.',
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        currentPasswordError =
        error.message.toLowerCase().contains(
          'invalid login credentials',
        )
            ? 'The current password is incorrect.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        currentPasswordError =
        'The current password is incorrect.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> sendOtp() async {
    setState(() {
      otpError = null;
    });

    if (customerEmail.isEmpty) {
      setState(() {
        otpError =
        'Customer email is unavailable.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: customerEmail,
        shouldCreateUser: false,
      );

      if (!mounted) return;

      setState(() {
        isOtpSent = true;
      });

      startResendTimer();

      showMessage(
        'OTP code sent to $customerEmail.',
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        otpError = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        otpError =
        'Unable to send the OTP code.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();

    setState(() {
      otpError = null;
    });

    if (otp.length != 8 ||
        int.tryParse(otp) == null) {
      setState(() {
        otpError =
        'Please enter the 8-digit OTP code.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.verifyOTP(
        email: customerEmail,
        token: otp,
        type: OtpType.email,
      );

      if (!mounted) return;

      resendTimer?.cancel();

      setState(() {
        isVerified = true;
        remainingSeconds = 0;
      });

      showMessage(
        'OTP verified successfully.',
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        otpError = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        otpError =
        'The OTP code is incorrect or expired.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> changePassword() async {
    final newPassword =
    newPasswordController.text.trim();

    final confirmPassword =
    confirmPasswordController.text.trim();

    setState(() {
      newPasswordError = null;
      confirmPasswordError = null;
    });

    if (!isVerified) {
      showMessage(
        'Please verify your identity first.',
        isError: true,
      );
      return;
    }

    if (!isStrongPassword) {
      setState(() {
        newPasswordError =
        'Use at least 8 characters with a letter, number, and symbol.';
      });
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        confirmPasswordError =
        'Please confirm your new password.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        confirmPasswordError =
        'The passwords do not match.';
      });
      return;
    }

    if (verificationMethod == 'password' &&
        newPassword ==
            currentPasswordController.text) {
      setState(() {
        newPasswordError =
        'The new password must be different from the current password.';
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      if (verificationMethod == 'password') {
        await supabase.auth.signInWithPassword(
          email: customerEmail,
          password:
          currentPasswordController.text,
        );
      }

      await supabase.auth.updateUser(
        UserAttributes(
          password: newPassword,
        ),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
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
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:
                      const Color(0xFFE8F8EE),
                      borderRadius:
                      BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Password Changed',
                    style: TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Your customer account password has been updated successfully.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style:
                      ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF339BFF),
                        foregroundColor:
                        Colors.white,
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(
                            15,
                          ),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(
                          dialogContext,
                        );
                      },
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } on AuthException catch (error) {
      showMessage(
        'Failed to change password: ${error.message}',
        isError: true,
      );
    } catch (error) {
      showMessage(
        'Failed to change password: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  InputDecoration buildInputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF339BFF),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color:
          const Color(0xFF339BFF)
              .withOpacity(0.12),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color:
          const Color(0xFF339BFF)
              .withOpacity(0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF339BFF),
          width: 1.5,
        ),
      ),
    );
  }

  Widget buildMethodButton({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected =
        verificationMethod == value;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          switchVerificationMethod(value);
        },
        child: AnimatedContainer(
          duration:
          const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEAF4FF)
                : Colors.white,
            borderRadius:
            BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF339BFF)
                  : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF339BFF)
                      : const Color(0xFFF1F3F6),
                  borderRadius:
                  BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? Colors.white
                      : Colors.black45,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF339BFF)
                      : const Color(0xFF1F2937),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 9.5,
                  height: 1.2,
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
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Verify Your Identity',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Choose one verification method before creating a new password.',
            style: TextStyle(
              color: Colors.black45,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              buildMethodButton(
                value: 'password',
                icon: Icons.password_rounded,
                title: 'Current Password',
                subtitle:
                'Verify using your old password',
              ),
              const SizedBox(width: 10),
              buildMethodButton(
                value: 'otp',
                icon:
                Icons.mark_email_read_outlined,
                title: 'Email OTP',
                subtitle:
                'Receive a code by email',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (verificationMethod ==
              'password') ...[
            TextField(
              controller:
              currentPasswordController,
              obscureText: hideCurrentPassword,
              enabled: !isVerified,
              decoration:
              buildInputDecoration(
                label: 'Current Password',
                icon: Icons.lock_outline,
                errorText:
                currentPasswordError,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      hideCurrentPassword =
                      !hideCurrentPassword;
                    });
                  },
                  icon: Icon(
                    hideCurrentPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  isVerified
                      ? Colors.green
                      : const Color(
                    0xFF339BFF,
                  ),
                  foregroundColor:
                  Colors.white,
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                      15,
                    ),
                  ),
                ),
                onPressed:
                isVerified || isLoading
                    ? null
                    : verifyCurrentPassword,
                icon: Icon(
                  isVerified
                      ? Icons.check_circle
                      : Icons.verified_user_outlined,
                ),
                label: Text(
                  isVerified
                      ? 'Current Password Verified'
                      : 'Verify Current Password',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius:
                BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.email_outlined,
                    color: Color(0xFF339BFF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      customerEmail.isEmpty
                          ? 'Customer email is unavailable.'
                          : 'OTP will be sent to:\n$customerEmail',
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                isLoading ||
                    remainingSeconds > 0
                    ? null
                    : sendOtp,
                icon: const Icon(
                  Icons.send_outlined,
                ),
                label: Text(
                  remainingSeconds > 0
                      ? 'Resend OTP in ${remainingSeconds}s'
                      : isOtpSent
                      ? 'Resend OTP Code'
                      : 'Send OTP Code',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: otpController,
              keyboardType:
              TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter
                    .digitsOnly,
                LengthLimitingTextInputFormatter(
                  8,
                ),
              ],
              enabled: !isVerified,
              decoration:
              buildInputDecoration(
                label: '8-digit OTP Code',
                icon: Icons.password_rounded,
                errorText: otpError,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  isVerified
                      ? Colors.green
                      : const Color(
                    0xFF339BFF,
                  ),
                  foregroundColor:
                  Colors.white,
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                      15,
                    ),
                  ),
                ),
                onPressed:
                isVerified ||
                    isLoading ||
                    !isOtpSent
                    ? null
                    : verifyOtp,
                icon: Icon(
                  isVerified
                      ? Icons.check_circle
                      : Icons
                      .mark_email_read_outlined,
                ),
                label: Text(
                  isVerified
                      ? 'OTP Verified'
                      : 'Verify OTP Code',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildPasswordRule({
    required bool isMet,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),
      child: Row(
        children: [
          Icon(
            isMet
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: isMet
                ? Colors.green
                : Colors.black38,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isMet
                    ? Colors.green.shade700
                    : Colors.black54,
                fontSize: 11.5,
                fontWeight: isMet
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNewPasswordCard() {
    return AnimatedOpacity(
      duration:
      const Duration(milliseconds: 200),
      opacity: isVerified ? 1 : 0.52,
      child: IgnorePointer(
        ignoring: !isVerified,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color:
                Colors.black.withOpacity(0.045),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Text(
                'Create New Password',
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isVerified
                    ? 'Your identity is verified. Create a strong new password.'
                    : 'Complete identity verification to unlock this section.',
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller:
                newPasswordController,
                obscureText: hideNewPassword,
                decoration:
                buildInputDecoration(
                  label: 'New Password',
                  icon: Icons.lock_rounded,
                  errorText: newPasswordError,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        hideNewPassword =
                        !hideNewPassword;
                      });
                    },
                    icon: Icon(
                      hideNewPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller:
                confirmPasswordController,
                obscureText:
                hideConfirmPassword,
                decoration:
                buildInputDecoration(
                  label: 'Confirm New Password',
                  icon: Icons.lock_outline,
                  errorText:
                  confirmPasswordError,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        hideConfirmPassword =
                        !hideConfirmPassword;
                      });
                    },
                    icon: Icon(
                      hideConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius:
                  BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Password Requirements',
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildPasswordRule(
                      isMet: hasMinimumLength,
                      label:
                      'At least 8 characters',
                    ),
                    buildPasswordRule(
                      isMet: hasLetter,
                      label:
                      'At least one letter',
                    ),
                    buildPasswordRule(
                      isMet: hasNumber,
                      label:
                      'At least one number',
                    ),
                    buildPasswordRule(
                      isMet: hasSymbol,
                      label:
                      'At least one symbol, for example ! @ # \$ %',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    const Color(
                      0xFF339BFF,
                    ),
                    foregroundColor:
                    Colors.white,
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        15,
                      ),
                    ),
                  ),
                  onPressed:
                  isLoading
                      ? null
                      : changePassword,
                  icon: isLoading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(
                    Icons.lock_reset_rounded,
                  ),
                  label: Text(
                    isLoading
                        ? 'Processing...'
                        : 'Change Password',
                    style: const TextStyle(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor:
      const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Change Password'),
        centerTitle: true,
        backgroundColor:
        const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior
              .onDrag,
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.of(context)
                .viewInsets
                .bottom +
                30,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient:
                  const LinearGradient(
                    colors: [
                      Color(0xFF339BFF),
                      Color(0xFF63B3FF),
                    ],
                  ),
                  borderRadius:
                  BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color:
                      const Color(0xFF339BFF)
                          .withOpacity(0.20),
                      blurRadius: 16,
                      offset:
                      const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor:
                      Colors.white,
                      child: Icon(
                        Icons.security_rounded,
                        color:
                        Color(0xFF339BFF),
                        size: 38,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Secure Password Update',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Verify using your current password or an OTP sent to your email.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              buildVerificationCard(),
              const SizedBox(height: 18),
              buildNewPasswordCard(),
            ],
          ),
        ),
      ),
    );
  }
}
