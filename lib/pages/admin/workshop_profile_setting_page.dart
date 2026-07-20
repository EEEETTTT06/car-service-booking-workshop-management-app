import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'map_picker_page.dart';

class WorkshopProfileSettingPage extends StatefulWidget {
  final Map<String, String> adminProfile;

  const WorkshopProfileSettingPage({
    super.key,
    required this.adminProfile,
  });

  @override
  State<WorkshopProfileSettingPage> createState() =>
      _WorkshopProfileSettingPageState();
}

class _WorkshopProfileSettingPageState
    extends State<WorkshopProfileSettingPage> {
  final supabase = Supabase.instance.client;
  final ImagePicker imagePicker = ImagePicker();

  late Map<String, String> adminProfile;
  late TextEditingController workshopNameController;
  late TextEditingController workshopPhoneController;
  late TextEditingController workshopAddressController;

  String? workshopLogoUrl;
  List<Map<String, dynamic>> workshopPhotos = [];

  String selectedPlaceName = '';
  double? selectedLatitude;
  double? selectedLongitude;

  TimeOfDay openingTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay closingTime = const TimeOfDay(hour: 18, minute: 0);

  bool isLoading = true;
  bool isSaving = false;
  bool isUploadingLogo = false;
  bool isLoadingPhotos = false;

  @override
  void initState() {
    super.initState();

    adminProfile = Map<String, String>.from(widget.adminProfile);

    workshopNameController = TextEditingController(
      text: adminProfile['workshop'] ?? '',
    );

    workshopPhoneController = TextEditingController(
      text: adminProfile['workshopPhone'] ?? '',
    );

    workshopAddressController = TextEditingController(
      text: adminProfile['address'] ?? '',
    );

    loadWorkshopProfile();
    loadWorkshopPhotos();
  }

  @override
  void dispose() {
    workshopNameController.dispose();
    workshopPhoneController.dispose();
    workshopAddressController.dispose();
    super.dispose();
  }

  void showMessage(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor:
        isError ? Colors.red.shade600 : const Color(0xFF339BFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  TimeOfDay parseTime(String value) {
    final cleanValue = value.trim();
    final period = cleanValue.substring(cleanValue.length - 2).toUpperCase();
    final timePart = cleanValue.substring(0, cleanValue.length - 3);
    final pieces = timePart.split(':');

    int hour = int.parse(pieces[0]);
    final minute = int.parse(pieces[1]);

    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  void loadWorkingHours(String value) {
    try {
      if (!value.contains('-')) return;

      final parts = value.split('-');
      openingTime = parseTime(parts[0]);
      closingTime = parseTime(parts[1]);
    } catch (_) {
      openingTime = const TimeOfDay(hour: 9, minute: 0);
      closingTime = const TimeOfDay(hour: 18, minute: 0);
    }
  }

  Future<void> loadWorkshopProfile() async {
    try {
      final response = await supabase
          .from('workshop_profile')
          .select()
          .eq('id', 1)
          .maybeSingle();

      if (response == null) {
        throw Exception('Workshop profile not found.');
      }

      final workshopName =
      (response['workshop_name'] ?? 'SF Service Centre').toString();
      final phone = (response['phone'] ?? '').toString();
      final address = (response['address'] ?? '').toString();
      final workingHours =
      (response['working_hours'] ?? '9:00 AM - 6:00 PM').toString();

      if (!mounted) return;

      setState(() {
        workshopLogoUrl = response['logo_url']?.toString();

        selectedPlaceName = (response['place_name'] ?? '').toString();
        selectedLatitude = response['latitude'] == null
            ? null
            : double.tryParse(response['latitude'].toString());
        selectedLongitude = response['longitude'] == null
            ? null
            : double.tryParse(response['longitude'].toString());

        workshopNameController.text = workshopName;
        workshopPhoneController.text = phone;
        workshopAddressController.text = address;

        adminProfile['workshop'] = workshopName;
        adminProfile['workshopPhone'] = phone;
        adminProfile['address'] = address;
        adminProfile['workingHours'] = workingHours;
        adminProfile['logoUrl'] = workshopLogoUrl ?? '';

        loadWorkingHours(workingHours);
        isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }

      showMessage(
        'Failed to load workshop profile: $error',
        isError: true,
      );
    }
  }

  Future<void> saveWorkshopProfile() async {
    if (isSaving) return;

    final workshopName = workshopNameController.text.trim();
    final phone = workshopPhoneController.text.trim();
    final address = workshopAddressController.text.trim();

    if (workshopName.isEmpty || phone.isEmpty || address.isEmpty) {
      showMessage(
        'Please complete all workshop information.',
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

    if (closingTime.hour * 60 + closingTime.minute <=
        openingTime.hour * 60 + openingTime.minute) {
      showMessage(
        'Closing time must be later than opening time.',
        isError: true,
      );
      return;
    }

    final workingHours =
        '${formatTime(openingTime)} - ${formatTime(closingTime)}';

    setState(() {
      isSaving = true;
    });

    try {
      await supabase.from('workshop_profile').update({
        'workshop_name': workshopName,
        'phone': phone,
        'address': address,
        'working_hours': workingHours,
        'place_name': selectedPlaceName,
        'latitude': selectedLatitude,
        'longitude': selectedLongitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', 1);

      if (!mounted) return;

      setState(() {
        adminProfile['workshop'] = workshopName;
        adminProfile['workshopPhone'] = phone;
        adminProfile['address'] = address;
        adminProfile['workingHours'] = workingHours;
      });

      showMessage('Workshop profile updated successfully.');
    } catch (error) {
      showMessage(
        'Failed to update workshop profile: $error',
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

  Future<void> chooseWorkshopLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initialLatitude: selectedLatitude,
          initialLongitude: selectedLongitude,
          initialAddress: workshopAddressController.text.trim(),
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      workshopAddressController.text =
          (result['address'] ?? workshopAddressController.text).toString();
      selectedPlaceName = (result['placeName'] ?? '').toString();
      selectedLatitude = result['latitude'] == null
          ? null
          : double.tryParse(result['latitude'].toString());
      selectedLongitude = result['longitude'] == null
          ? null
          : double.tryParse(result['longitude'].toString());
    });

    showMessage('Workshop location selected.');
  }

  Future<void> pickOpeningTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: openingTime,
    );

    if (picked == null || !mounted) return;

    setState(() {
      openingTime = picked;
    });
  }

  Future<void> pickClosingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: closingTime,
    );

    if (picked == null || !mounted) return;

    setState(() {
      closingTime = picked;
    });
  }

  Future<void> pickAndUploadWorkshopLogo() async {
    try {
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      setState(() {
        isUploadingLogo = true;
      });

      final file = File(pickedFile.path);
      final extension = path.extension(pickedFile.path);
      final fileName =
          'workshop_logo_${DateTime.now().millisecondsSinceEpoch}$extension';

      await supabase.storage.from('workshop-logos').upload(
        fileName,
        file,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl =
      supabase.storage.from('workshop-logos').getPublicUrl(fileName);

      await supabase.from('workshop_profile').update({
        'logo_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', 1);

      if (!mounted) return;

      setState(() {
        workshopLogoUrl = publicUrl;
        adminProfile['logoUrl'] = publicUrl;
      });

      showMessage('Workshop logo uploaded successfully.');
    } catch (error) {
      showMessage(
        'Failed to upload workshop logo: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingLogo = false;
        });
      }
    }
  }

  void showWorkshopLogoPreview() {
    if (workshopLogoUrl == null || workshopLogoUrl!.isEmpty) {
      showMessage(
        'No workshop logo uploaded yet.',
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.network(
                      workshopLogoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 80,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        pickAndUploadWorkshopLogo();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text(
                        'Change Logo',
                        style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> loadWorkshopPhotos() async {
    try {
      setState(() {
        isLoadingPhotos = true;
      });

      final response = await supabase
          .from('workshop_photos')
          .select()
          .order('display_order', ascending: true);

      if (!mounted) return;

      setState(() {
        workshopPhotos = List<Map<String, dynamic>>.from(response);
        isLoadingPhotos = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          isLoadingPhotos = false;
        });
      }

      showMessage(
        'Failed to load workshop photos: $error',
        isError: true,
      );
    }
  }

  Future<void> pickAndUploadWorkshopPhoto() async {
    final titleController = TextEditingController();

    final selectedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(
                  Icons.add_photo_alternate,
                  color: Color(0xFF339BFF),
                ),
              ),
              SizedBox(width: 12),
              Text('Add Workshop Photo'),
            ],
          ),
          content: TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: 'Photo title',
              hintText: 'Example: Front Shop',
              filled: true,
              fillColor: const Color(0xFFF5F8FD),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();

                if (title.isEmpty) return;

                Navigator.pop(dialogContext, title);
              },
              child: const Text('Choose Photo'),
            ),
          ],
        );
      },
    );

    titleController.dispose();

    if (selectedTitle == null || selectedTitle.isEmpty) return;

    try {
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      setState(() {
        isLoadingPhotos = true;
      });

      final file = File(pickedFile.path);
      final extension = path.extension(pickedFile.path);
      final fileName =
          'workshop_photo_${DateTime.now().millisecondsSinceEpoch}$extension';

      await supabase.storage.from('workshop-photos').upload(
        fileName,
        file,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl =
      supabase.storage.from('workshop-photos').getPublicUrl(fileName);

      await supabase.from('workshop_photos').insert({
        'image_url': publicUrl,
        'caption': selectedTitle,
        'title': selectedTitle,
        'display_order': workshopPhotos.length + 1,
      });

      await loadWorkshopPhotos();

      showMessage('Workshop photo uploaded successfully.');
    } catch (error) {
      showMessage(
        'Failed to upload workshop photo: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoadingPhotos = false;
        });
      }
    }
  }

  Future<void> updateWorkshopPhotoTitle(
      String photoId,
      String currentTitle,
      ) async {
    final controller = TextEditingController(text: currentTitle);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Edit Photo Title'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Photo title',
              filled: true,
              fillColor: const Color(0xFFF5F8FD),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newTitle == null || newTitle.isEmpty) return;

    try {
      await supabase
          .from('workshop_photos')
          .update({
        'title': newTitle,
        'caption': newTitle,
      })
          .eq('photo_id', photoId);

      await loadWorkshopPhotos();

      showMessage('Photo title updated.');
    } catch (error) {
      showMessage(
        'Failed to update photo title: $error',
        isError: true,
      );
    }
  }

  Future<void> deleteWorkshopPhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFEAEA),
                child: Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
              ),
              SizedBox(width: 12),
              Text('Delete Photo'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this workshop photo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('workshop_photos')
          .delete()
          .eq('photo_id', photoId);

      await loadWorkshopPhotos();

      showMessage('Workshop photo deleted.');
    } catch (error) {
      showMessage(
        'Failed to delete workshop photo: $error',
        isError: true,
      );
    }
  }

  void showWorkshopPhotoPreview(Map<String, dynamic> photo) {
    final imageUrl = (photo['image_url'] ?? '').toString();
    final title =
    (photo['title'] ?? photo['caption'] ?? 'Workshop Photo').toString();

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                updateWorkshopPhotoTitle(
                                  photo['photo_id'].toString(),
                                  title,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF339BFF),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.edit),
                              label: const Text('Rename'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                deleteWorkshopPhoto(
                                  photo['photo_id'].toString(),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.delete),
                              label: const Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF339BFF),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: maxLines == 1
                ? Icon(
              icon,
              color: const Color(0xFF339BFF),
            )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFD),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
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

  Widget buildTimeCard({
    required String title,
    required TimeOfDay time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF339BFF),
              ),
            ),
            const SizedBox(width: 13),
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
                  const SizedBox(height: 4),
                  Text(
                    formatTime(time),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_rounded,
              color: Color(0xFF339BFF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildWorkshopInformationCard() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader(
            icon: Icons.storefront_rounded,
            title: 'Workshop Information',
            subtitle:
            'Update the information shown to customers in the application.',
          ),
          const SizedBox(height: 22),
          buildInputField(
            controller: workshopNameController,
            label: 'Workshop Name',
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 16),
          buildInputField(
            controller: workshopPhoneController,
            label: 'Workshop Phone',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          buildInputField(
            controller: workshopAddressController,
            label: 'Workshop Address',
            icon: Icons.location_on_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: chooseWorkshopLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF339BFF),
                side: const BorderSide(
                  color: Color(0xFF339BFF),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.map_rounded),
              label: const Text(
                'Choose Location on Map',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (selectedLatitude != null && selectedLongitude != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFF339BFF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedPlaceName.isNotEmpty
                          ? selectedPlaceName
                          : '${selectedLatitude!.toStringAsFixed(6)}, '
                          '${selectedLongitude!.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Working Hours',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          buildTimeCard(
            title: 'Opening Time',
            time: openingTime,
            icon: Icons.login_rounded,
            onTap: pickOpeningTime,
          ),
          const SizedBox(height: 12),
          buildTimeCard(
            title: 'Closing Time',
            time: closingTime,
            icon: Icons.logout_rounded,
            onTap: pickClosingTime,
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveWorkshopProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF339BFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: isSaving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.save_rounded),
              label: Text(
                isSaving ? 'Saving...' : 'Save Workshop Changes',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildGallerySection() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader(
            icon: Icons.photo_library_rounded,
            title: 'Workshop Gallery',
            subtitle:
            'Upload and manage the workshop photos shown to customers.',
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
              isLoadingPhotos ? null : pickAndUploadWorkshopPhoto,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF339BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text(
                'Upload Workshop Photo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (isLoadingPhotos)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (workshopPhotos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 34,
                horizontal: 18,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: Colors.black38,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No workshop photos uploaded.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              itemCount: workshopPhotos.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.90,
              ),
              itemBuilder: (context, index) {
                final photo = workshopPhotos[index];
                final title = (photo['title'] ??
                    photo['caption'] ??
                    'Workshop Photo')
                    .toString();

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => showWorkshopPhotoPreview(photo),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFD),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            child: Image.network(
                              (photo['image_url'] ?? '').toString(),
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Container(
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.black38,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            10,
                            8,
                            6,
                            8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Rename',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    updateWorkshopPhotoTitle(
                                      photo['photo_id'].toString(),
                                      title,
                                    ),
                                icon: const Icon(
                                  Icons.edit_rounded,
                                  color: Color(0xFF339BFF),
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget buildLogoHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
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
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: showWorkshopLogoPreview,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 58,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: const Color(0xFFD7E5FA),
                    backgroundImage: workshopLogoUrl != null &&
                        workshopLogoUrl!.isNotEmpty
                        ? NetworkImage(workshopLogoUrl!)
                        : null,
                    child:
                    workshopLogoUrl == null || workshopLogoUrl!.isEmpty
                        ? const Icon(
                      Icons.storefront_rounded,
                      size: 60,
                      color: Color(0xFF339BFF),
                    )
                        : null,
                  ),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: isUploadingLogo
                      ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(
                    Icons.camera_alt_rounded,
                    size: 19,
                    color: Color(0xFF339BFF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            workshopNameController.text.trim().isEmpty
                ? 'Workshop Profile'
                : workshopNameController.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Manage workshop business information',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 175,
            height: 44,
            child: ElevatedButton.icon(
              onPressed:
              isUploadingLogo ? null : pickAndUploadWorkshopLogo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF339BFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: isUploadingLogo
                  ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.camera_alt_rounded),
              label: const Text(
                'Change Logo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void goBackWithUpdatedProfile() {
    Navigator.pop(context, adminProfile);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        goBackWithUpdatedProfile();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFD7E5FA),
        appBar: AppBar(
          title: const Text('Workshop Settings'),
          centerTitle: true,
          backgroundColor: const Color(0xFF339BFF),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            onPressed: goBackWithUpdatedProfile,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: isLoading
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : RefreshIndicator(
          onRefresh: () async {
            await loadWorkshopProfile();
            await loadWorkshopPhotos();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                buildLogoHeader(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      buildWorkshopInformationCard(),
                      const SizedBox(height: 20),
                      buildGallerySection(),
                      const SizedBox(height: 22),
                      const Center(
                        child: Column(
                          children: [
                            Text(
                              'SF Service App',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Workshop Profile Management',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
