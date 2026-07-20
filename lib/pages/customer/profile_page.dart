import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  String customerName = 'Customer';
  String customerEmail = '';
  String customerPhone = 'Not Provided';
  int totalVehicles = 0;

  String workshopName = 'SF Service Centre';
  String workshopAddress = 'Loading workshop address...';
  String workingHours = '9:00 AM - 6:00 PM';
  double? workshopLatitude;
  double? workshopLongitude;
  List<Map<String, dynamic>> workshopPhotos = [];

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Customer not logged in.');
      }

      final customerResponse = await supabase
          .from('customers')
          .select()
          .eq('customer_id', user.id)
          .maybeSingle();

      final vehiclesResponse = await supabase
          .from('vehicles')
          .select('vehicle_id')
          .eq('user_id', user.id);

      final workshopResponse = await supabase
          .from('workshop_profile')
          .select()
          .eq('id', 1)
          .maybeSingle();
      final photosResponse = await supabase
          .from('workshop_photos')
          .select()
          .order('display_order', ascending: true);

      setState(() {
        customerName = (customerResponse?['name'] ??
            user.userMetadata?['name'] ??
            'Customer')
            .toString();

        customerEmail = (customerResponse?['email'] ?? user.email ?? '')
            .toString();

        customerPhone =
            (customerResponse?['phone'] ?? 'Not Provided').toString();

        totalVehicles = vehiclesResponse.length;

        workshopName =
            (workshopResponse?['workshop_name'] ?? 'SF Service Centre')
                .toString();

        workshopAddress =
            (workshopResponse?['address'] ?? 'Workshop address not available')
                .toString();

        workshopPhotos = List<Map<String, dynamic>>.from(photosResponse);

        workingHours =
            (workshopResponse?['working_hours'] ?? '9:00 AM - 6:00 PM')
                .toString();

        workshopLatitude = workshopResponse?['latitude'] == null
            ? null
            : double.tryParse(workshopResponse!['latitude'].toString());

        workshopLongitude = workshopResponse?['longitude'] == null
            ? null
            : double.tryParse(workshopResponse!['longitude'].toString());
      });
    } catch (error) {
      showMessage('Failed to load profile: $error');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: const Color(0xFF339BFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> openGoogleMaps() async {
    if (workshopLatitude == null || workshopLongitude == null) {
      showMessage('Workshop location is not available.');
      return;
    }

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$workshopLatitude,$workshopLongitude&travelmode=driving',
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> openWaze() async {
    if (workshopLatitude == null || workshopLongitude == null) {
      showMessage('Workshop location is not available.');
      return;
    }

    final wazeUrl = Uri.parse(
      'waze://?ll=$workshopLatitude,$workshopLongitude&navigate=yes',
    );

    final fallbackUrl = Uri.parse(
      'https://waze.com/ul?ll=$workshopLatitude,$workshopLongitude&navigate=yes',
    );

    if (await canLaunchUrl(wazeUrl)) {
      await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }

  void showNavigationOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 45,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Navigate to Workshop',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEAF4FF),
                  child: Icon(Icons.map, color: Color(0xFF339BFF)),
                ),
                title: const Text('Google Maps'),
                subtitle: const Text('Open route in Google Maps'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  openGoogleMaps();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEAF4FF),
                  child: Icon(Icons.directions_car, color: Color(0xFF339BFF)),
                ),
                title: const Text('Waze'),
                subtitle: const Text('Open route in Waze'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  openWaze();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEAF4FF),
            child: Icon(icon, color: const Color(0xFF339BFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showCustomerPhotoPreview(Map<String, dynamic> photo) {
    final imageUrl = photo['image_url'].toString();
    final title = (photo['title'] ?? photo['caption'] ?? 'Workshop Photo')
        .toString();

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
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),

                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 28,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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

  Widget buildWorkshopGallery() {
    if (workshopPhotos.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Workshop Photos',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: workshopPhotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final photo = workshopPhotos[index];

              return GestureDetector(
                onTap: () => showCustomerPhotoPreview(photo),
                child: Container(
                  width: 190,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          photo['image_url'],
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            color: Colors.black.withOpacity(0.45),
                            child: Text(
                              (photo['title'] ??
                                  photo['caption'] ??
                                  'Workshop Photo')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
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
            },
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget buildWorkshopCard() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(Icons.store, color: Color(0xFF339BFF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  workshopName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, color: Color(0xFF339BFF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  workshopAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, color: Color(0xFF339BFF)),
              const SizedBox(width: 10),
              Text(
                workingHours,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF339BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: showNavigationOptions,
              icon: const Icon(Icons.navigation),
              label: const Text(
                'Navigate to Workshop',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await supabase.auth.signOut();

                if (!mounted) return;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginPage(),
                  ),
                      (route) => false,
                );
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadProfileData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
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
                      customerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      customerEmail,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildInfoCard(
                      icon: Icons.phone,
                      title: 'Phone Number',
                      subtitle: customerPhone,
                    ),
                    buildInfoCard(
                      icon: Icons.directions_car,
                      title: 'Total Vehicles',
                      subtitle: '$totalVehicles vehicles',
                    ),
                    buildInfoCard(
                      icon: Icons.verified_user,
                      title: 'Account Status',
                      subtitle: 'Active Customer',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Workshop Information',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    buildWorkshopCard(),
                    buildWorkshopGallery(),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          showLogoutDialog(context);
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'Logout',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}