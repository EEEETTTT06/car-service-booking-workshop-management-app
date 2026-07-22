import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_sidebar.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../common/app_result_message.dart';

class AdminServicesPage extends StatefulWidget {
  const AdminServicesPage({super.key});

  @override
  State<AdminServicesPage> createState() => _AdminServicesPageState();
}

class _AdminServicesPageState extends State<AdminServicesPage> {
  bool isLoading = false;
  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;
  List<Map<String, dynamic>> services = [];

  RealtimeChannel? servicesRealtimeChannel;
  bool isRealtimeRefreshing = false;

  @override
  void initState() {
    super.initState();

    fetchServices();
    setupRealtimeSubscription();

    scrollController.addListener(() {
      if (scrollController.offset > 350 && !showBackToTop) {
        setState(() => showBackToTop = true);
      } else if (scrollController.offset <= 350 && showBackToTop) {
        setState(() => showBackToTop = false);
      }
    });
  }

  @override
  void dispose() {
    final channel = servicesRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> fetchServices({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final response = await supabase
          .from('services')
          .select()
          .order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      setState(() {
        services = List<Map<String, dynamic>>.from(
          response,
        );
      });
    } catch (error) {
      if (showLoading) {
        showMessage(
          'Failed to load services: $error',
        );
      } else {
        debugPrint(
          'Realtime service refresh failed: $error',
        );
      }
    } finally {
      if (showLoading && mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void setupRealtimeSubscription() {
    if (servicesRealtimeChannel != null) {
      return;
    }

    servicesRealtimeChannel = supabase
        .channel(
      'admin-services-realtime',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'services',
      callback: (payload) {
        debugPrint(
          'Admin service changed: '
              '${payload.eventType}',
        );

        refreshServicesFromRealtime();
      },
    )
        .subscribe();
  }

  Future<void> refreshServicesFromRealtime() async {
    if (!mounted || isRealtimeRefreshing) {
      return;
    }

    isRealtimeRefreshing = true;

    try {
      await fetchServices(
        showLoading: false,
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  int get availableCount {
    return services.where((service) {
      return service['availability_status'] == 'Available';
    }).length;
  }

  Color getStatusColor(String status) {
    return status == 'Available' ? Colors.green : Colors.red;
  }

  Color getStatusBackgroundColor(String status) {
    return status == 'Available' ? Colors.green.shade50 : Colors.red.shade50;
  }

  Future<void> addService({
    required String name,
    required String description,
    required String price,
    required String status,
  }) async {
    final normalizedName =
    name.trim().toUpperCase();

    final normalizedDescription =
    description.trim();

    final parsedPrice =
    double.tryParse(price.trim());

    if (normalizedName.isEmpty) {
      showMessage(
        'Please enter the service name.',
      );
      return;
    }

    if (parsedPrice == null ||
        parsedPrice < 0) {
      showMessage(
        'Please enter a valid service price.',
      );
      return;
    }

    if (status != 'Available' &&
        status != 'Unavailable') {
      showMessage(
        'The selected service status is invalid.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_create_service',
        params: {
          'p_service_name':
          normalizedName,
          'p_description':
          normalizedDescription,
          'p_price':
          parsedPrice,
          'p_availability_status':
          status,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid service information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final serviceId =
      result['service_id']
          ?.toString();

      if (serviceId == null ||
          serviceId.isEmpty ||
          result['created'] != true) {
        throw Exception(
          'The service was not created correctly.',
        );
      }

      await fetchServices();

      showMessage(
        'Service added successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchServices();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin add service failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to add service: $error',
      );
    }
  }

  Future<void> updateService({
    required String serviceId,
    required String name,
    required String description,
    required String price,
    required String status,
  }) async {
    final normalizedServiceId =
    serviceId.trim();

    final normalizedName =
    name.trim().toUpperCase();

    final normalizedDescription =
    description.trim();

    final parsedPrice =
    double.tryParse(price.trim());

    if (normalizedServiceId.isEmpty) {
      showMessage(
        'Service information is missing.',
      );
      return;
    }

    if (normalizedName.isEmpty) {
      showMessage(
        'Please enter the service name.',
      );
      return;
    }

    if (parsedPrice == null ||
        parsedPrice < 0) {
      showMessage(
        'Please enter a valid service price.',
      );
      return;
    }

    if (status != 'Available' &&
        status != 'Unavailable') {
      showMessage(
        'The selected service status is invalid.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_update_service',
        params: {
          'p_service_id':
          normalizedServiceId,
          'p_service_name':
          normalizedName,
          'p_description':
          normalizedDescription,
          'p_price':
          parsedPrice,
          'p_availability_status':
          status,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid service information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedServiceId =
      result['service_id']
          ?.toString();

      if (returnedServiceId == null ||
          returnedServiceId.isEmpty ||
          result['updated'] != true) {
        throw Exception(
          'The service was not updated correctly.',
        );
      }

      await fetchServices();

      showMessage(
        'Service updated successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchServices();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin update service failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to update service: $error',
      );
    }
  }

  Future<void> deleteService(
      String serviceId,
      ) async {
    final normalizedServiceId =
    serviceId.trim();

    if (normalizedServiceId.isEmpty) {
      showMessage(
        'Service information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'admin_delete_service',
        params: {
          'p_service_id':
          normalizedServiceId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid service deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['deleted'] != true) {
        throw Exception(
          'The service was not deleted.',
        );
      }

      await fetchServices();

      showMessage(
        'Service deleted successfully.',
      );
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await fetchServices();
    } catch (error, stackTrace) {
      debugPrint(
        'Admin delete service failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to delete service: $error',
      );
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    AppResultMessage.show(
      context,
      message: message,
    );
  }

  Widget autoFitText(String text, {
    double fontSize = 17,
    FontWeight fontWeight = FontWeight.bold,
    Color color = Colors.black,
    int maxLines = 1,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double size = fontSize;

        if (text.length > 28) {
          size = fontSize - 3;
        } else if (text.length > 20) {
          size = fontSize - 2;
        } else if (text.length > 14) {
          size = fontSize - 1;
        }

        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: size,
            fontWeight: fontWeight,
            color: color,
          ),
        );
      },
    );
  }

  Widget buildSummaryCard({
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
              child: Icon(icon, color: const Color(0xFF339BFF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
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

  Widget buildServiceCard(Map<String, dynamic> service) {
    final status = service['availability_status'] ?? 'Available';
    final name = service['service_name'] ?? '';
    final description = service['description'] ?? '';

    return Container(
      height: 168,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          showServiceDialog(service: service);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFD7E5FA),
                child: Icon(
                  Icons.build,
                  color: Color(0xFF339BFF),
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    autoFitText(
                      name,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 6),
                    autoFitText(
                      description.isEmpty
                          ? 'No description provided'
                          : description,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          size: 16,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'RM ${service['price']}',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: getStatusBackgroundColor(status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: getStatusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () {
                  showDeleteServiceDialog(service['service_id'].toString());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDeleteServiceDialog(String serviceId) {
    final service = services.firstWhere(
          (item) => item['service_id'].toString() == serviceId,
      orElse: () => {},
    );

    final serviceName = service['service_name']?.toString() ?? 'this service';

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.red,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete Service',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Are you sure you want to delete "$serviceName"?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Services already used by booking records cannot be deleted. Set the service as Unavailable instead.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await deleteService(serviceId);
                        },
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: label.isEmpty ? null : label,
        prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF339BFF),
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  void showServiceDialog({Map<String, dynamic>? service}) {
    final bool isEdit = service != null;

    final nameController = TextEditingController(
      text: isEdit ? service['service_name'] ?? '' : '',
    );

    final descriptionController = TextEditingController(
      text: isEdit ? service['description'] ?? '' : '',
    );

    final priceController = TextEditingController(
      text: isEdit ? service['price'].toString() : '',
    );

    String selectedStatus =
    isEdit ? service['availability_status'] ?? 'Available' : 'Available';

    Widget fieldTitle(String title) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF339BFF), Color(0xFF63B3FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.car_repair_rounded,
                                color: Color(0xFF339BFF),
                                size: 38,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              isEdit ? 'Edit Service' : 'Add New Service',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isEdit
                                  ? 'Modify service information and pricing.'
                                  : 'Create a new workshop service for customers.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Service Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      fieldTitle('Service Type'),
                      const SizedBox(height: 8),
                      buildInputBox(
                        controller: nameController,
                        label: 'Enter service type',
                        icon: Icons.build,
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            return newValue.copyWith(
                              text: newValue.text.toUpperCase(),
                              selection: newValue.selection,
                            );
                          }),
                        ],
                      ),

                      const SizedBox(height: 16),

                      fieldTitle('Service Description'),
                      const SizedBox(height: 8),
                      buildInputBox(
                        controller: descriptionController,
                        label: 'Enter description',
                        icon: Icons.description_outlined,
                        maxLines: 2,
                      ),

                      const SizedBox(height: 18),

                      fieldTitle('Price (RM)'),
                      const SizedBox(height: 8),
                      buildInputBox(
                        controller: priceController,
                        label: '0.00',
                        icon: Icons.payments_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      fieldTitle('Service Status'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.info_outline,
                            color: Color(0xFF339BFF),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFF339BFF),
                              width: 2,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Available',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 18),
                                SizedBox(width: 8),
                                Text('Available'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Unavailable',
                            child: Row(
                              children: [
                                Icon(Icons.cancel, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text('Unavailable'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedStatus = value!;
                          });
                        },
                      ),

                      const SizedBox(height: 22),

                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Back'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF339BFF),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  final description =
                                  descriptionController.text.trim();
                                  final price = priceController.text.trim();

                                  if (name.isEmpty || price.isEmpty) {
                                    showMessage(
                                      'Please fill in service type and price.',
                                    );
                                    return;
                                  }

                                  if (double.tryParse(price) == null) {
                                    showMessage('Please enter a valid price.');
                                    return;
                                  }

                                  Navigator.pop(context);

                                  if (isEdit) {
                                    await updateService(
                                      serviceId: service['service_id'].toString(),
                                      name: name,
                                      description: description,
                                      price: price,
                                      status: selectedStatus,
                                    );
                                  } else {
                                    await addService(
                                      name: name,
                                      description: description,
                                      price: price,
                                      status: selectedStatus,
                                    );
                                  }
                                },
                                  child: Text(
                                    isEdit ? '✓ Save Changes' : '+ Create Service',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Service Management'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,

        leading: IconButton(
          onPressed: () {
            AdminSidebar.show(context);
          },
          icon: const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person,
              color: Color(0xFF339BFF),
            ),
          ),
        ),

        actions: const [
          NotificationBell(
            isAdmin: true,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => fetchServices(),
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF339BFF),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(26),
                    bottomRight: Radius.circular(26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workshop Services',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage service descriptions, pricing and availability',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.build,
                          title: 'Services',
                          value: '${services.length}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.check_circle,
                          title: 'Available',
                          value: '$availableCount',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              if (services.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No services found.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        return buildServiceCard(services[index]);
                      },
                      childCount: services.length,
                    ),
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showBackToTop)
            FloatingActionButton.small(
              heroTag: 'customerBackToTop',
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
          if (showBackToTop) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addService',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: () {
              showServiceDialog();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Service'),
          ),
        ],
      ),
    );
  }
}