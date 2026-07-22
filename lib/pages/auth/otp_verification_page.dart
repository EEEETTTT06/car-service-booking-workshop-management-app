import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'change_new_password_page.dart';
import '../../services/supabase_service.dart';
import '../common/app_result_message.dart';

class OtpVerificationPage extends StatefulWidget {
  final String email;

  const OtpVerificationPage({
    super.key,
    required this.email,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final otpController = TextEditingController();

  bool isVerifying = false;
  bool isResending = false;
  String? otpError;

  int remainingSeconds = 60;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    startCountdown();
  }

  void startCountdown() {
    remainingSeconds = 60;
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds == 0) {
        timer.cancel();
      } else {
        setState(() {
          remainingSeconds--;
        });
      }
    });
  }

  Future<void> resendOtp() async {
    if (remainingSeconds > 0) return;

    setState(() {
      isResending = true;
      otpError = null;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: widget.email,
        shouldCreateUser: false,
      );

      startCountdown();

      if (!mounted) return;
      AppResultMessage.success(
        context,
        message: 'OTP code has been resent.',
      );
    } catch (error) {
      setState(() {
        otpError = 'Unable to resend OTP. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isResending = false;
        });
      }
    }
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();

    setState(() {
      otpError = null;
    });

    if (otp.isEmpty) {
      setState(() {
        otpError = 'Please enter the OTP code.';
      });
      return;
    }

    if (otp.length != 8) {
      setState(() {
        otpError = 'Please enter the 8-digit OTP code.';
      });
      return;
    }

    setState(() {
      isVerifying = true;
    });

    try {
      await supabase.auth.verifyOTP(
        email: widget.email,
        token: otp,
        type: OtpType.email,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ChangeNewPasswordPage(),
        ),
      );
    } catch (error) {
      print('Verify OTP error: $error');

      setState(() {
        otpError = 'Wrong OTP code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isVerifying = false;
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    otpController.dispose();
    super.dispose();
  }

  Widget buildOtpInputBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter OTP code',
            prefixIcon: const Icon(Icons.password),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (otpError != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Text(
              otpError!,
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
    final canResend = remainingSeconds == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify OTP'),
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
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.mark_email_read, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              'Enter OTP Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'OTP has been sent to\n${widget.email}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 30),
            buildOtpInputBox(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: canResend && !isResending ? resendOtp : null,
                  child: Text(
                    canResend
                        ? 'Resend OTP'
                        : 'Resend OTP (${remainingSeconds}s)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                onPressed: isVerifying ? null : verifyOtp,
                child: Text(
                  isVerifying ? 'Verifying...' : 'Verify OTP Code',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}