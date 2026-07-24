import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/app_result_message.dart';
import 'customer_change_password_page.dart';


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

  final ImagePicker imagePicker = ImagePicker();

  bool isSaving = false;
  bool isPickingImage = false;

  Uint8List? selectedProfileImageBytes;
  String? selectedProfileImageContentType;
  String profileImageUrl = '';

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

    profileImageUrl =
        widget.customerProfile['profile_image_url']?.trim() ?? '';


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

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    scrollController.dispose();

    super.dispose();
  }

  bool get hasProfilePicture {
    return selectedProfileImageBytes != null ||
        profileImageUrl.trim().isNotEmpty;
  }

  Future<void> pickProfileImage(
      ImageSource source,
      ) async {
    if (isSaving || isPickingImage) return;

    setState(() {
      isPickingImage = true;
    });

    try {
      final pickedImage = await imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
        preferredCameraDevice: CameraDevice.front,
      );

      if (pickedImage == null) return;

      final fileName = pickedImage.name.toLowerCase();
      final detectedMimeType =
      pickedImage.mimeType?.toLowerCase();

      String? contentType;

      if (detectedMimeType == 'image/jpeg' ||
          detectedMimeType == 'image/jpg' ||
          fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (detectedMimeType == 'image/png' ||
          fileName.endsWith('.png')) {
        contentType = 'image/png';
      } else if (detectedMimeType == 'image/webp' ||
          fileName.endsWith('.webp')) {
        contentType = 'image/webp';
      }

      if (contentType == null) {
        showMessage(
          'Please select a JPG, PNG, or WEBP image.',
        );
        return;
      }

      final imageBytes =
      await pickedImage.readAsBytes();

      const maximumFileSize = 5 * 1024 * 1024;

      if (imageBytes.length > maximumFileSize) {
        showMessage(
          'Profile picture must be smaller than 5 MB.',
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        selectedProfileImageBytes = imageBytes;
        selectedProfileImageContentType =
            contentType;
      });

      showMessage(
        source == ImageSource.camera
            ? 'Photo captured successfully. Tap Save Profile to upload it.'
            : 'Profile picture selected. Tap Save Profile to upload it.',
      );
    } catch (error) {
      showMessage(
        source == ImageSource.camera
            ? 'Failed to take photo: $error'
            : 'Failed to select profile picture: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isPickingImage = false;
        });
      }
    }
  }

  void showProfilePictureOptions() {
    if (isSaving || isPickingImage) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              22,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius:
                    BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Profile Picture',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Choose how you want to update your photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 18),
                if (hasProfilePicture) ...[
                  _buildPhotoOptionTile(
                    icon: Icons.zoom_out_map_rounded,
                    title: 'View Profile Picture',
                    subtitle:
                    'Open the current picture in a larger view',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showProfileImagePreview();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                _buildPhotoOptionTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Take a Photo',
                  subtitle:
                  'Open the camera and take a new picture',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickProfileImage(
                      ImageSource.camera,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildPhotoOptionTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Choose from Gallery',
                  subtitle:
                  'Select an existing picture from your device',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickProfileImage(
                      ImageSource.gallery,
                    );
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                      const Color(0xFF1F2937),
                      side: const BorderSide(
                        color: Colors.black12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                    },
                    child: const Text(
                      'Cancel',
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
  }

  Widget _buildPhotoOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF339BFF)
                  .withOpacity(0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius:
                  BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF339BFF),
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
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
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProfileImage({
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (selectedProfileImageBytes != null) {
      return Image.memory(
        selectedProfileImageBytes!,
        width: width,
        height: height,
        fit: fit,
      );
    }

    if (profileImageUrl.isNotEmpty) {
      return Image.network(
        profileImageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (
            context,
            error,
            stackTrace,
            ) {
          return const Center(
            child: Icon(
              Icons.person,
              size: 70,
              color: Color(0xFF339BFF),
            ),
          );
        },
      );
    }

    return const Center(
      child: Icon(
        Icons.person,
        size: 70,
        color: Color(0xFF339BFF),
      ),
    );
  }

  void showProfileImagePreview() {
    if (!hasProfilePicture) {
      showProfilePictureOptions();
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final screenSize =
            MediaQuery.of(dialogContext).size;

        final previewSize =
        screenSize.width < 500
            ? screenSize.width - 36
            : 460.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Hero(
                tag: 'customer-profile-picture-preview',
                child: Container(
                  width: previewSize,
                  height: previewSize,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius:
                    BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(0.35),
                        blurRadius: 28,
                        offset:
                        const Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: buildProfileImage(
                      width: previewSize,
                      height: previewSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Pinch to zoom the picture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> uploadSelectedProfileImage(
      String authUserId,
      ) async {
    final imageBytes = selectedProfileImageBytes;
    final contentType = selectedProfileImageContentType;

    if (imageBytes == null || contentType == null) {
      return profileImageUrl;
    }

    const bucketName = 'customer-profile-images';
    final storagePath = '$authUserId/profile-image';

    await supabase.storage.from(bucketName).uploadBinary(
      storagePath,
      imageBytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: contentType,
        cacheControl: '3600',
      ),
    );

    final publicUrl = supabase.storage
        .from(bucketName)
        .getPublicUrl(storagePath);

    final cacheVersion =
        DateTime.now().millisecondsSinceEpoch;

    return '$publicUrl?v=$cacheVersion';
  }

  Widget buildProfilePicture() {
    return Column(
      children: [
        Hero(
          tag: 'customer-profile-picture-preview',
          child: Material(
            color: Colors.transparent,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: hasProfilePicture
                      ? showProfileImagePreview
                      : showProfilePictureOptions,
                  child: Container(
                    width: 116,
                    height: 116,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                        Colors.white.withOpacity(0.85),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(0.14),
                          blurRadius: 16,
                          offset:
                          const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color:
                        const Color(0xFFD7E5FA),
                        child: buildProfileImage(
                          width: 106,
                          height: 106,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: 3,
                  child: Material(
                    color: const Color(0xFF1F2937),
                    shape: const CircleBorder(),
                    elevation: 5,
                    child: InkWell(
                      customBorder:
                      const CircleBorder(),
                      onTap:
                      isSaving || isPickingImage
                          ? null
                          : showProfilePictureOptions,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: isPickingImage
                            ? const Padding(
                          padding:
                          EdgeInsets.all(10),
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor:
            Colors.white.withOpacity(0.14),
            padding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 9,
            ),
            shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(20),
              side: BorderSide(
                color:
                Colors.white.withOpacity(0.24),
              ),
            ),
          ),
          onPressed:
          isSaving || isPickingImage
              ? null
              : showProfilePictureOptions,
          icon: const Icon(
            Icons.add_a_photo_outlined,
            size: 18,
          ),
          label: Text(
            hasProfilePicture
                ? 'Manage Profile Picture'
                : 'Add Profile Picture',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasProfilePicture
              ? 'Tap the picture to view it larger'
              : 'Take a photo or choose one from your gallery',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10.8,
          ),
        ),
      ],
    );
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      showMessage(
        'Please complete name and phone number.',
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in.');
      }

      final updatedProfileImageUrl =
      await uploadSelectedProfileImage(
        user.id,
      );

      await supabase
          .from('customers')
          .update({
        'name': name,
        'phone': phone,
        'profile_image_url':
        updatedProfileImageUrl.isEmpty
            ? null
            : updatedProfileImageUrl,
      })
          .eq('auth_user_id', user.id);

      profileImageUrl =
          updatedProfileImageUrl;

      widget.onProfileUpdated({
        'name': name,
        'email':
        emailController.text.trim(),
        'phone': phone,
        'profile_image_url':
        profileImageUrl,
      });

      showMessage(
        'Profile updated successfully.',
      );

      if (!mounted) return;

      Navigator.pop(context);
    } catch (error) {
      showMessage(
        'Failed to update profile: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> openChangePasswordPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const CustomerChangePasswordPage(),
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
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

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius:
            BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF339BFF),
            size: 22,
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
                  buildProfilePicture(),

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
                        icon: Icons.security_outlined,
                        title: 'Security',
                        value: 'Protected',
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
                  _buildSectionHeader(
                    icon: Icons.badge_outlined,
                    title: 'Personal Information',
                    subtitle:
                    'Update your customer account details.',
                  ),

                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      14,
                      16,
                      14,
                      2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF339BFF)
                            .withOpacity(0.09),
                      ),
                    ),
                    child: Column(
                      children: [
                        buildInputBox(
                          controller: nameController,
                          label: 'Name',
                          icon: Icons.person_outline,
                        ),
                        buildInputBox(
                          controller: emailController,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          readOnly: true,
                        ),
                        buildInputBox(
                          controller: phoneController,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildSectionHeader(
                    icon: Icons.lock_reset_rounded,
                    title: 'Account Security',
                    subtitle:
                    'Change your password using secure identity verification.',
                  ),

                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                      Colors.white.withOpacity(0.78),
                      borderRadius:
                      BorderRadius.circular(22),
                      border: Border.all(
                        color:
                        const Color(0xFF339BFF)
                            .withOpacity(0.09),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                            const Color(0xFFEAF4FF),
                            borderRadius:
                            BorderRadius.circular(
                              17,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration:
                                BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                  BorderRadius.all(
                                    Radius.circular(13),
                                  ),
                                ),
                                child: Icon(
                                  Icons
                                      .verified_user_outlined,
                                  color:
                                  Color(0xFF339BFF),
                                  size: 23,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Text(
                                      'Two Verification Options',
                                      style: TextStyle(
                                        color:
                                        Color(0xFF1F2937),
                                        fontSize: 14,
                                        fontWeight:
                                        FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Verify using your current password, or request an OTP code through your registered email.',
                                      style: TextStyle(
                                        color:
                                        Colors.black54,
                                        fontSize: 11.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 13),
                        Container(
                          width: double.infinity,
                          padding:
                          const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color:
                            const Color(0xFFF7F9FC),
                            borderRadius:
                            BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Password Requirements',
                                style: TextStyle(
                                  color:
                                  Color(0xFF1F2937),
                                  fontSize: 12.5,
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '• At least 8 characters\n'
                                    '• At least one letter\n'
                                    '• At least one number\n'
                                    '• At least one symbol',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 11.5,
                                  height: 1.55,
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
                            style:
                            ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(
                                0xFF339BFF,
                              ),
                              foregroundColor:
                              Colors.white,
                              elevation: 0,
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  15,
                                ),
                              ),
                            ),
                            onPressed:
                            openChangePasswordPage,
                            icon: const Icon(
                              Icons.lock_reset_rounded,
                            ),
                            label: const Text(
                              'Change Password',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
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