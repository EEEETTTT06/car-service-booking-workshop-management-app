import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/supabase_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();

  bool isLoading = false;
  bool hidePassword = true;
  bool hideConfirmPassword = true;

  String? nameError;
  String? emailError;
  String? passwordError;
  String? confirmPasswordError;
  String? phoneError;

  bool isValidPassword(String password) {
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return password.length >= 6 &&
        hasUppercase &&
        hasLowercase &&
        hasNumber;
  }

  Future<void> registerCustomer() async {
    final name = fullNameController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final phone = phoneController.text.trim();

    setState(() {
      nameError = null;
      emailError = null;
      passwordError = null;
      confirmPasswordError = null;
      phoneError = null;
    });

    bool hasError = false;

    if (name.isEmpty) {
      nameError = 'Full name is required';
      hasError = true;
    }

    if (email.isEmpty) {
      emailError = 'Email is required';
      hasError = true;
    } else if (!email.contains('@') || !email.contains('.')) {
      emailError = 'Please enter a valid email address';
      hasError = true;
    }

    if (password.isEmpty) {
      passwordError = 'Password is required';
      hasError = true;
    } else if (!isValidPassword(password)) {
      passwordError =
      'Password must be at least 6 characters and include uppercase, lowercase and number.';
      hasError = true;
    }

    if (confirmPassword.isEmpty) {
      confirmPasswordError = 'Confirm password is required';
      hasError = true;
    } else if (password != confirmPassword) {
      confirmPasswordError = 'Password does not match';
      hasError = true;
    }

    if (phone.isEmpty) {
      phoneError = 'Phone number is required';
      hasError = true;
    } else if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      phoneError = 'Phone number must contain numbers only';
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'phone': phone,
          'role': 'customer',
        },
      );

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
            'Your account has been successfully created.\n\nPlease login to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      print('==========================');
      print('Register error: $error');
      print('==========================');

      final errorText = error.toString().toLowerCase();

      setState(() {
        if (errorText.contains('already') ||
            errorText.contains('registered') ||
            errorText.contains('user already') ||
            errorText.contains('already been registered')) {
          emailError = 'Email has been used';
        } else if (errorText.contains('password')) {
          passwordError =
          'Password must include uppercase, lowercase and number.';
        } else {
          emailError = error.toString();
        }
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
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    String? errorText,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: onTogglePassword,
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 10),

                const Text(
                  'Register Customer Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Please fill in your information',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 30),

                buildInputBox(
                  controller: fullNameController,
                  hintText: 'Full name',
                  icon: Icons.person,
                  errorText: nameError,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                          (oldValue, newValue) {
                        return newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                          selection: newValue.selection,
                          composing: TextRange.empty,
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                buildInputBox(
                  controller: emailController,
                  hintText: 'Email',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  errorText: emailError,
                ),

                const SizedBox(height: 18),

                buildInputBox(
                  controller: passwordController,
                  hintText: 'Password',
                  icon: Icons.lock,
                  isPassword: true,
                  obscureText: hidePassword,
                  errorText: passwordError,
                  onTogglePassword: () {
                    setState(() {
                      hidePassword = !hidePassword;
                    });
                  },
                ),

                const SizedBox(height: 6),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text(
                      'Password must include uppercase, lowercase and number.',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                buildInputBox(
                  controller: confirmPasswordController,
                  hintText: 'Confirm password',
                  icon: Icons.lock,
                  isPassword: true,
                  obscureText: hideConfirmPassword,
                  errorText: confirmPasswordError,
                  onTogglePassword: () {
                    setState(() {
                      hideConfirmPassword = !hideConfirmPassword;
                    });
                  },
                ),

                const SizedBox(height: 18),

                buildInputBox(
                  controller: phoneController,
                  hintText: 'Phone number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  errorText: phoneError,
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: const Color(0xFF0F4C81),
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: isLoading ? null : registerCustomer,
                    child: isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                      ),
                    )
                        : const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}