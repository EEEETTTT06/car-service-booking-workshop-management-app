import 'package:flutter/material.dart';
import '../customer/navigation_control.dart';
import '../admin/admin_main_page.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import '../../services/supabase_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;
  bool rememberMe = false;
  static const String rememberMeKey = 'remember_me';
  static const String rememberedRoleKey = 'remembered_role';
  String? emailError;
  String? passwordError;

  Future<void> saveRememberMeSetting({
    required String role,
  }) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.setBool(
        rememberMeKey,
        rememberMe,
      );

      if (rememberMe) {
        await preferences.setString(
          rememberedRoleKey,
          role,
        );
      } else {
        await preferences.remove(
          rememberedRoleKey,
        );
      }

      debugPrint(
        'Remember Me: $rememberMe, Role: $role',
      );
    } catch (error) {
      debugPrint(
        'Failed to save Remember Me setting: $error',
      );
    }
  }

  Future<void> loginCustomer() async {
    await loginUser(isAdminLogin: false);
  }

  Future<void> loginAdmin() async {
    await loginUser(isAdminLogin: true);
  }

  Future<void> loginUser({required bool isAdminLogin}) async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    setState(() {
      emailError = null;
      passwordError = null;
    });

    if (email.isEmpty) {
      setState(() => emailError = 'Please enter your email.');
      return;
    }

    if (password.isEmpty) {
      setState(() => passwordError = 'Please enter your password.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        setState(() => emailError = 'This email has not been registered.');
        return;
      }

      if (isAdminLogin) {
        final adminData = await supabase
            .from('admins')
            .select()
            .eq('admin_id', user.id)
            .maybeSingle();

        if (adminData == null) {
          await supabase.auth.signOut();

          if (!mounted) return;
          setState(() {
            emailError = 'This account is not an admin account.';
          });

          return;
        }

        await saveRememberMeSetting(
          role: 'admin',
        );

        await updateAdminFcmToken(user.id);

        debugPrint('Admin login successful');

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminMainPage()),
        );
      } else {
        var customerData = await supabase
            .from('customers')
            .select()
            .eq('customer_id', user.id)
            .maybeSingle();

        customerData ??= await supabase
            .from('customers')
            .select()
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (customerData == null) {
          await supabase.auth.signOut();

          if (!mounted) return;
          setState(() {
            emailError =
            'Unable to access this section with the current account.';
          });

          return;
        }

        await saveRememberMeSetting(
          role: 'customer',
        );

        await updateCustomerFcmToken(
          customerId:
          customerData['customer_id'].toString(),
        );

        debugPrint('Customer login successful');

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NavigationControl()),
        );
      }
    } catch (error) {
      final errorText = error.toString().toLowerCase();

      if (!mounted) return;
      setState(() {
        if (errorText.contains('invalid login credentials') ||
            errorText.contains('invalid credentials')) {
          passwordError = 'Incorrect email or password.';
        } else if (errorText.contains('email not confirmed')) {
          emailError = 'Please verify your email before login.';
        } else {
          passwordError = 'Login failed. Please try again.';
        }
      });

      debugPrint('Login error: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> updateAdminFcmToken(String userId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Admin FCM token is empty or unavailable.');
        return;
      }

      await supabase.from('admin_fcm_tokens').upsert(
        {
          'admin_id': userId,
          'fcm_token': fcmToken,
          'platform': 'Android',
          'device_name': 'Admin Device',
          'last_login': DateTime.now().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );

      debugPrint('Admin device registered.');
    } catch (e) {
      debugPrint('Admin FCM token error: $e');
    }
  }
  Future<void> updateCustomerFcmToken({
    required String customerId,
  }) async {
    try {
      final fcmToken =
      await FirebaseMessaging.instance.getToken();

      if (fcmToken == null ||
          fcmToken.trim().isEmpty) {
        debugPrint(
          'Customer FCM token is empty or unavailable.',
        );
        return;
      }

      // Save each customer device separately.
      await supabase
          .from('customer_fcm_tokens')
          .upsert(
        {
          'customer_id': customerId,
          'fcm_token': fcmToken,
          'platform': 'Android',
          'device_name': 'Customer Device',
          'last_login':
          DateTime.now().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );

      // Keep the old token column temporarily.
      // Some existing notification code may still use it.
      await supabase
          .from('customers')
          .update({
        'fcm_token': fcmToken,
      }).eq(
        'customer_id',
        customerId,
      );

      debugPrint(
        'Customer device registered successfully.',
      );
    } catch (error) {
      debugPrint(
        'Customer FCM token registration error: $error',
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: isPassword ? hidePassword : false,
          keyboardType:
          isPassword ? TextInputType.text : TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(
                hidePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  hidePassword = !hidePassword;
                });
              },
            )
                : null,
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF339BFF),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 120,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'Car Service App',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Workshop Management System',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 40),
                  buildInputBox(
                    controller: emailController,
                    hintText: 'Enter your email',
                    icon: Icons.email,
                    errorText: emailError,
                  ),
                  const SizedBox(height: 20),
                  buildInputBox(
                    controller: passwordController,
                    hintText: 'Enter your password',
                    icon: Icons.lock,
                    isPassword: true,
                    errorText: passwordError,
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberMe,
                        activeColor: const Color(0xFF339BFF),
                        onChanged: isLoading
                            ? null
                            : (value) {
                          setState(() {
                            rememberMe = value ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'Remember Me',
                          style: TextStyle(
                            color: Color(0xFF0F4C81),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                              const ForgotPasswordPage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.lightBlue,
                            fontSize: 14,
                            decoration:
                            TextDecoration.underline,
                            decorationColor:
                            Colors.lightBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFDBC0E),
                        foregroundColor: const Color(0xFF0F4C81),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: isLoading ? null : loginCustomer,
                      child: isLoading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                          : const Text(
                        'Login as Customer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F4C81),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: isLoading ? null : loginAdmin,
                      child: const Text(
                        'Login as Admin',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'Create new account',
                      style: TextStyle(
                        color: Colors.lightBlue,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
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
  }
}