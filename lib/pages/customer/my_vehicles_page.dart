import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'book_service_page.dart';
import 'service_records_page.dart';
import '../../services/supabase_service.dart';
import '../common/notification_bell.dart';
import '../common/app_result_message.dart';

class MyVehiclesPage extends StatefulWidget {
  const MyVehiclesPage({super.key});

  @override
  State<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends State<MyVehiclesPage>
    with WidgetsBindingObserver {
  bool isLoading = false;

  final ImagePicker imagePicker = ImagePicker();

  final ScrollController scrollController = ScrollController();
  bool showBackToTop = false;
  String searchText = '';

  Map<String, dynamic>? currentCustomer;
  List<Map<String, dynamic>> vehicles = [];
  Map<String, Map<String, dynamic>> vehicleBookings = {};

  RealtimeChannel? vehiclesRealtimeChannel;
  Timer? realtimeRefreshTimer;
  bool isRealtimeRefreshing = false;
  bool realtimeRefreshQueued = false;
  bool realtimeSubscriptionReady = false;
  bool isSchedulingReconnect = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    loadData();

    scrollController.addListener(() {
      if (scrollController.offset > 350 && !showBackToTop) {
        setState(() {
          showBackToTop = true;
        });
      } else if (scrollController.offset <= 350 && showBackToTop) {
        setState(() {
          showBackToTop = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    realtimeRefreshTimer?.cancel();

    final channel = vehiclesRealtimeChannel;

    if (channel != null) {
      unawaited(
        supabase.removeChannel(channel),
      );
    }

    scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    // Always refresh when the app returns to the foreground. This is a
    // fallback for mobile networks that temporarily pause Realtime sockets.
    scheduleVehicleRefresh();

    if (!realtimeSubscriptionReady) {
      scheduleRealtimeReconnect();
    }
  }

  void scrollToTop() {
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);

    try {
      await fetchCurrentCustomer();
      await fetchVehicles();
      await fetchVehicleBookings();
      setupRealtimeSubscription();
    } catch (error) {
      showMessage('Failed to load vehicles: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> fetchCurrentCustomer() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User not logged in.');
    }

    final response = await supabase
        .from('customers')
        .select()
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (response == null) {
      throw Exception('Customer profile not found.');
    }

    currentCustomer = Map<String, dynamic>.from(response);
  }

  Future<void> fetchVehicles() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('vehicles')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .order('created_at', ascending: false);

    vehicles = List<Map<String, dynamic>>.from(response);
  }

  Future<void> fetchVehicleBookings() async {
    if (currentCustomer == null) return;

    final response = await supabase
        .from('bookings')
        .select()
        .eq('customer_id', currentCustomer!['customer_id'])
        .neq('status', 'Cancelled')
        .gte('appointment_date', toSqlDate(DateTime.now()))
        .order('appointment_date', ascending: true);

    final Map<String, Map<String, dynamic>> temp = {};

    for (final booking in response) {
      final vehicleId = booking['vehicle_id'].toString();

      if (!temp.containsKey(vehicleId)) {
        temp[vehicleId] = Map<String, dynamic>.from(booking);
      }
    }

    vehicleBookings = temp;
  }

  void setupRealtimeSubscription() {
    if (currentCustomer == null) return;

    if (vehiclesRealtimeChannel != null) {
      return;
    }

    final customerId =
    currentCustomer!['customer_id'].toString();

    realtimeSubscriptionReady = false;

    vehiclesRealtimeChannel = supabase
        .channel(
      'customer-vehicles-$customerId',
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'vehicles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        debugPrint(
          'Customer vehicle changed: '
              '${payload.eventType}',
        );

        scheduleVehicleRefresh();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'customer_id',
        value: customerId,
      ),
      callback: (payload) {
        debugPrint(
          'Customer vehicle booking changed: '
              '${payload.eventType}',
        );

        scheduleVehicleRefresh();
      },
    )
        .subscribe(
          (status, error) {
        debugPrint(
          'Customer vehicle Realtime status: '
              '$status${error == null ? '' : ' - $error'}',
        );

        realtimeSubscriptionReady =
            status == RealtimeSubscribeStatus.subscribed;

        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          scheduleRealtimeReconnect();
        }
      },
    );
  }

  void scheduleVehicleRefresh() {
    realtimeRefreshTimer?.cancel();

    realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 300),
          () {
        unawaited(
          refreshVehiclesFromRealtime(),
        );
      },
    );
  }

  void scheduleRealtimeReconnect() {
    if (!mounted || isSchedulingReconnect) {
      return;
    }

    isSchedulingReconnect = true;

    Future<void>.delayed(
      const Duration(seconds: 2),
          () async {
        try {
          if (!mounted) return;

          final oldChannel = vehiclesRealtimeChannel;
          vehiclesRealtimeChannel = null;
          realtimeSubscriptionReady = false;

          if (oldChannel != null) {
            await supabase.removeChannel(oldChannel);
          }

          if (!mounted) return;

          setupRealtimeSubscription();
          scheduleVehicleRefresh();
        } catch (error) {
          debugPrint(
            'Customer vehicle Realtime reconnect failed: '
                '$error',
          );
        } finally {
          isSchedulingReconnect = false;
        }
      },
    );
  }

  Future<void> refreshVehiclesFromRealtime() async {
    if (!mounted) {
      return;
    }

    if (isRealtimeRefreshing) {
      // Do not lose a second event while the first refresh is running.
      realtimeRefreshQueued = true;
      return;
    }

    isRealtimeRefreshing = true;

    try {
      do {
        realtimeRefreshQueued = false;

        await fetchVehicles();
        await fetchVehicleBookings();

        if (mounted) {
          setState(() {});
        }
      } while (mounted && realtimeRefreshQueued);
    } catch (error) {
      debugPrint(
        'Realtime vehicle refresh failed: $error',
      );
    } finally {
      isRealtimeRefreshing = false;
    }
  }

  String toSqlDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String formatDate(String date) {
    final parsedDate = DateTime.parse(date);
    return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year}';
  }

  String getDisplayStatus(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return 'Link Record';
    }

    return 'Pending Claim';
  }

  Color getStatusColor(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return Colors.green;
    }

    return Colors.orange;
  }

  Color getStatusBackgroundColor(String status) {
    if (status == 'Link Record' || status == 'Verified') {
      return Colors.green.shade50;
    }

    return Colors.orange.shade50;
  }

  int get pendingClaimCount {
    return vehicles.where((vehicle) {
      final status = vehicle['verification_status'] ?? 'Pending Claim';
      return status != 'Link Record' && status != 'Verified';
    }).length;
  }

  List<Map<String, dynamic>> get filteredVehicles {
    final search = searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return vehicles;
    }

    return vehicles.where((vehicle) {
      final plate =
      (vehicle['plate_number'] ?? '').toString().toLowerCase();

      final model =
      (vehicle['car_model'] ?? '').toString().toLowerCase();

      final status =
      getDisplayStatus(
        vehicle['verification_status'] ?? 'Pending Claim',
      ).toLowerCase();

      return plate.contains(search) ||
          model.contains(search) ||
          status.contains(search);
    }).toList();
  }

  void goToServiceRecords(String plate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceRecordsPage(initialPlate: plate),
      ),
    );
  }

  void goToBookingPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BookServicePage(),
      ),
    );
  }

  Future<void> pickVehiclePhotos({
    required ImageSource source,
    required List<XFile> targetPhotos,
    required StateSetter setDialogState,
  }) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1800,
        );

        if (photo == null) return;

        setDialogState(() {
          targetPhotos.add(photo);
        });

        return;
      }

      final selectedPhotos =
      await imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1800,
      );

      if (selectedPhotos.isEmpty) return;

      setDialogState(() {
        final existingPaths = targetPhotos
            .map((photo) => photo.path)
            .toSet();

        for (final photo in selectedPhotos) {
          if (existingPaths.add(photo.path)) {
            targetPhotos.add(photo);
          }
        }
      });
    } catch (error) {
      showMessage(
        'Unable to select photos: $error',
      );
    }
  }

  String getVehiclePhotoExtension(
      XFile photo,
      ) {
    final mimeType =
    photo.mimeType?.toLowerCase();

    if (mimeType == 'image/jpeg') {
      return 'jpg';
    }

    if (mimeType == 'image/png') {
      return 'png';
    }

    if (mimeType == 'image/webp') {
      return 'webp';
    }

    final fileName = photo.name.toLowerCase();
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex >= 0 &&
        dotIndex < fileName.length - 1) {
      final extension = fileName
          .substring(dotIndex + 1)
          .toLowerCase();

      if (extension == 'jpg' ||
          extension == 'jpeg') {
        return 'jpg';
      }

      if (extension == 'png') {
        return 'png';
      }

      if (extension == 'webp') {
        return 'webp';
      }
    }

    throw Exception(
      '${photo.name}: only JPG, PNG or WEBP images are supported.',
    );
  }

  String getVehiclePhotoContentType(
      String extension,
      ) {
    if (extension == 'png') {
      return 'image/png';
    }

    if (extension == 'webp') {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  Future<Map<String, int>> uploadVehiclePhotos({
    required String vehicleId,
    required List<XFile> vocPhotos,
    required List<XFile> vehiclePhotos,
  }) async {
    final totalPhotoCount =
        vocPhotos.length + vehiclePhotos.length;

    final customerId = currentCustomer?['customer_id']
        ?.toString()
        .trim();

    if (customerId == null ||
        customerId.isEmpty) {
      return {
        'uploaded': 0,
        'failed': totalPhotoCount,
      };
    }

    int uploadedCount = 0;
    int failedCount = 0;

    Future<void> uploadPhotoGroup({
      required List<XFile> photos,
      required String imageType,
    }) async {
      for (
      int index = 0;
      index < photos.length;
      index++
      ) {
        final photo = photos[index];
        String? storagePath;

        try {
          final fileSize = await photo.length();

          if (fileSize > 10 * 1024 * 1024) {
            throw Exception(
              '${photo.name} is larger than 10 MB.',
            );
          }

          final extension =
          getVehiclePhotoExtension(photo);

          final contentType =
          getVehiclePhotoContentType(
            extension,
          );

          final bytes = await photo.readAsBytes();

          final timestamp = DateTime.now()
              .microsecondsSinceEpoch;

          storagePath =
          '$customerId/'
              '$vehicleId/'
              '$imageType/'
              '${timestamp}_$index.$extension';

          await supabase.storage
              .from('vehicle-photos')
              .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: contentType,
            ),
          );

          await supabase
              .from('vehicle_images')
              .insert({
            'vehicle_id': vehicleId,
            'customer_id': customerId,
            'image_type': imageType,
            'storage_path': storagePath,
          });

          uploadedCount++;
        } catch (error, stackTrace) {
          failedCount++;

          debugPrint(
            'Vehicle photo upload failed: $error',
          );

          debugPrint(
            stackTrace.toString(),
          );

          /*
         * If Storage upload succeeded but the
         * vehicle_images insert failed, remove
         * the uploaded Storage file.
         */
          if (storagePath != null) {
            try {
              await supabase.storage
                  .from('vehicle-photos')
                  .remove([storagePath]);
            } catch (cleanupError) {
              debugPrint(
                'Vehicle photo cleanup failed: '
                    '$cleanupError',
              );
            }
          }
        }
      }
    }

    await uploadPhotoGroup(
      photos: vocPhotos,
      imageType: 'voc',
    );

    await uploadPhotoGroup(
      photos: vehiclePhotos,
      imageType: 'vehicle',
    );

    return {
      'uploaded': uploadedCount,
      'failed': failedCount,
    };
  }

  Future<List<Map<String, dynamic>>> fetchVehicleImages(
      String vehicleId,
      ) async {
    final response = await supabase
        .from('vehicle_images')
        .select(
      'image_id, vehicle_id, customer_id, image_type, storage_path, created_at',
    )
        .eq('vehicle_id', vehicleId)
        .order('created_at', ascending: true);

    final rows =
    List<Map<String, dynamic>>.from(response);

    final images = <Map<String, dynamic>>[];

    for (final row in rows) {
      final image =
      Map<String, dynamic>.from(row);

      final storagePath =
      image['storage_path']
          ?.toString()
          .trim();

      if (storagePath == null ||
          storagePath.isEmpty) {
        image['signed_url'] = null;
        images.add(image);
        continue;
      }

      try {
        final signedUrl = await supabase.storage
            .from('vehicle-photos')
            .createSignedUrl(
          storagePath,
          3600,
        );

        image['signed_url'] = signedUrl;
      } catch (error) {
        debugPrint(
          'Create customer vehicle image URL failed: $error',
        );

        image['signed_url'] = null;
      }

      images.add(image);
    }

    return images;
  }

  Future<Map<String, int>> deleteVehicleImages(
      List<Map<String, dynamic>> images,
      ) async {
    int deletedCount = 0;
    int failedCount = 0;

    for (final image in images) {
      final imageId =
      image['image_id']?.toString().trim();

      final storagePath =
      image['storage_path']
          ?.toString()
          .trim();

      if (imageId == null ||
          imageId.isEmpty) {
        failedCount++;
        continue;
      }

      try {
        await supabase
            .from('vehicle_images')
            .delete()
            .eq('image_id', imageId);

        /*
       * The database record is removed first.
       * If Storage cleanup fails, the deleted
       * photo will still disappear from the app.
       */
        if (storagePath != null &&
            storagePath.isNotEmpty) {
          try {
            await supabase.storage
                .from('vehicle-photos')
                .remove([storagePath]);
          } catch (storageError) {
            debugPrint(
              'Vehicle photo Storage cleanup failed: '
                  '$storageError',
            );
          }
        }

        deletedCount++;
      } catch (error, stackTrace) {
        failedCount++;

        debugPrint(
          'Delete vehicle image failed: $error',
        );

        debugPrint(stackTrace.toString());
      }
    }

    return {
      'deleted': deletedCount,
      'failed': failedCount,
    };
  }

  void showVehicleImagePreview({
    required String imageUrl,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 28,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: double.infinity,
            height:
            MediaQuery.of(dialogContext)
                .size
                .height *
                0.75,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    6,
                    8,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F2937),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (
                            context,
                            child,
                            progress,
                            ) {
                          if (progress == null) {
                            return child;
                          }

                          return const Center(
                            child:
                            CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (
                            context,
                            error,
                            stackTrace,
                            ) {
                          return const Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 55,
                                color: Colors.white54,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Unable to display photo.',
                                style: TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          );
                        },
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

  Future<void> notifyAdminsVehicleClaim({
    required String vehicleId,
    required String plate,
    required String model,
  }) async {
    try {
      final normalizedVehicleId =
      vehicleId.trim();

      final customerId =
      currentCustomer?['customer_id']
          ?.toString()
          .trim();

      if (normalizedVehicleId.isEmpty ||
          customerId == null ||
          customerId.isEmpty) {
        debugPrint(
          'Vehicle claim notification skipped because routing information is missing.',
        );
        return;
      }

      final customerName =
          currentCustomer?['name'] ??
              'A customer';

      const title =
          'New Vehicle Claim Request';

      const notificationType =
          'vehicle_claim';

      const targetPage =
          'vehicle_management';

      final body =
          '$customerName submitted a vehicle claim request for $plate - $model.';

      final admins = await supabase
          .from('admins')
          .select(
        'admin_id, notification_enabled',
      );

      for (final admin in admins) {
        await supabase
            .from('admin_notifications')
            .insert({
          'admin_id': admin['admin_id'],
          'title': title,
          'message': body,
          'is_read': false,
          'notification_type':
          notificationType,
          'target_page': targetPage,
          'vehicle_id':
          normalizedVehicleId,
          'customer_id': customerId,
        });
      }

      /*
       * Admin device tokens are private and must
       * not be selected by a Customer account.
       * send-fcm now resolves enabled Admin tokens
       * securely with the Service Role key.
       */
      final response =
      await supabase.functions.invoke(
        'send-fcm',
        body: {
          'audience': 'admins',
          'title': title,
          'body': body,
          'data': {
            'target_page': targetPage,
            'notification_type':
            notificationType,
            'vehicle_id':
            normalizedVehicleId,
            'customer_id': customerId,
          },
        },
      );

      debugPrint(
        'Admin Vehicle Claim FCM response: '
            '${response.data}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Vehicle claim notify admin error: '
            '$error',
      );

      debugPrint(
        stackTrace.toString(),
      );
    }
  }

  Future<void> addVehicle({
    required String plate,
    required String model,
    required List<XFile> vocPhotos,
    required List<XFile> vehiclePhotos,
  }) async {
    final upperPlate =
    plate.trim().toUpperCase();

    final upperModel =
    model.trim().toUpperCase();

    if (upperPlate.isEmpty ||
        upperModel.isEmpty) {
      showMessage(
        'Please complete vehicle information.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_add_vehicle',
        params: {
          'p_plate_number': upperPlate,
          'p_car_model': upperModel,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle information was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      final vehicleId = result['vehicle_id']
          ?.toString()
          .trim();

      final returnedPlate =
      result['plate_number']
          ?.toString()
          .trim();

      final returnedModel =
      result['car_model']
          ?.toString()
          .trim();

      if (vehicleId == null ||
          vehicleId.isEmpty) {
        throw Exception(
          'Vehicle ID was not returned.',
        );
      }

      final totalPhotoCount =
          vocPhotos.length +
              vehiclePhotos.length;

      Map<String, int> uploadResult = {
        'uploaded': 0,
        'failed': 0,
      };

      if (totalPhotoCount > 0) {
        uploadResult =
        await uploadVehiclePhotos(
          vehicleId: vehicleId,
          vocPhotos: vocPhotos,
          vehiclePhotos: vehiclePhotos,
        );
      }

      try {
        await notifyAdminsVehicleClaim(
          vehicleId: vehicleId,
          plate:
          returnedPlate == null ||
              returnedPlate.isEmpty
              ? upperPlate
              : returnedPlate,
          model:
          returnedModel == null ||
              returnedModel.isEmpty
              ? upperModel
              : returnedModel,
        );
      } catch (
      notificationError,
      stackTrace
      ) {
        debugPrint(
          'Vehicle claim notification failed: '
              '$notificationError',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }

      await loadData();

      final uploadedCount =
          uploadResult['uploaded'] ?? 0;

      final failedCount =
          uploadResult['failed'] ?? 0;

      if (totalPhotoCount == 0) {
        showMessage(
          'Vehicle added successfully. '
              'Photos can be added later.',
        );
      } else if (failedCount == 0) {
        showMessage(
          'Vehicle and $uploadedCount '
              'photo(s) added successfully.',
        );
      } else {
        showMessage(
          'Some photos could not be uploaded. '
              'The vehicle was added successfully. '
              '$uploadedCount photo(s) uploaded and '
              '$failedCount failed.',
        );
      }
    } on PostgrestException catch (error) {
      showMessage(error.message);
      await loadData();
    } catch (error, stackTrace) {
      debugPrint(
        'Add customer vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      showMessage(
        'Failed to add vehicle: $error',
      );
    }
  }

  Future<void> updateVehicle({
    required String vehicleId,
    required String plate,
    required String model,
    required List<XFile> vocPhotos,
    required List<XFile> vehiclePhotos,
    required List<Map<String, dynamic>> removedExistingPhotos,
  }) async {
    final normalizedVehicleId = vehicleId.trim();
    final upperPlate = plate.trim().toUpperCase();
    final upperModel = model.trim().toUpperCase();

    if (normalizedVehicleId.isEmpty) {
      AppResultMessage.warning(
        context,
        message: 'Vehicle information is missing.',
      );
      return;
    }

    if (upperPlate.isEmpty || upperModel.isEmpty) {
      AppResultMessage.warning(
        context,
        message: 'Please complete vehicle information.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_update_vehicle',
        params: {
          'p_vehicle_id': normalizedVehicleId,
          'p_plate_number': upperPlate,
          'p_car_model': upperModel,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid vehicle information was returned.',
        );
      }

      final result = Map<String, dynamic>.from(
        rpcResult,
      );

      final returnedVehicleId =
      result['vehicle_id']?.toString().trim();

      final returnedPlate =
      result['plate_number']?.toString().trim();

      final returnedModel =
      result['car_model']?.toString().trim();

      final verificationStatus =
      result['verification_status']?.toString().trim();

      final detailsChanged =
          result['details_changed'] == true;

      if (returnedVehicleId == null ||
          returnedVehicleId.isEmpty) {
        throw Exception(
          'Vehicle ID was not returned.',
        );
      }

      if (verificationStatus == null ||
          verificationStatus.isEmpty) {
        throw Exception(
          'Vehicle verification status was not returned.',
        );
      }

      final uploadResult = await uploadVehiclePhotos(
        vehicleId: returnedVehicleId,
        vocPhotos: vocPhotos,
        vehiclePhotos: vehiclePhotos,
      );

      final deleteResult = await deleteVehicleImages(
        removedExistingPhotos,
      );

      if (verificationStatus == 'Pending Claim') {
        try {
          await notifyAdminsVehicleClaim(
            vehicleId: returnedVehicleId,
            plate: returnedPlate == null ||
                returnedPlate.isEmpty
                ? upperPlate
                : returnedPlate,
            model: returnedModel == null ||
                returnedModel.isEmpty
                ? upperModel
                : returnedModel,
          );
        } catch (notificationError, stackTrace) {
          debugPrint(
            'Vehicle update notification failed: '
                '$notificationError',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      await loadData();

      if (!mounted) return;

      final uploadedCount =
          uploadResult['uploaded'] ?? 0;

      final uploadFailed =
          uploadResult['failed'] ?? 0;

      final deletedCount =
          deleteResult['deleted'] ?? 0;

      final deleteFailed =
          deleteResult['failed'] ?? 0;

      final photoChangesMade =
          uploadedCount > 0 || deletedCount > 0;

      final totalFailed =
          uploadFailed + deleteFailed;

      if (totalFailed > 0) {
        AppResultMessage.warning(
          context,
          message:
          'Vehicle information was updated, but '
              'some photo changes failed. '
              '$uploadedCount uploaded, '
              '$deletedCount removed, '
              '$totalFailed failed.',
          duration: const Duration(seconds: 5),
        );
        return;
      }

      if (detailsChanged &&
          verificationStatus == 'Pending Claim') {
        AppResultMessage.success(
          context,
          message:
          'Vehicle details updated successfully. '
              'The vehicle is now pending admin verification. '
              '$uploadedCount photo(s) uploaded and '
              '$deletedCount photo(s) removed.',
          duration: const Duration(seconds: 4),
        );
        return;
      }

      if (photoChangesMade) {
        AppResultMessage.success(
          context,
          message:
          'Vehicle photos updated successfully. '
              '$uploadedCount photo(s) uploaded and '
              '$deletedCount photo(s) removed.',
        );
        return;
      }

      AppResultMessage.info(
        context,
        message:
        'No vehicle or photo changes were made.',
      );
    } on PostgrestException catch (error) {
      if (mounted) {
        AppResultMessage.error(
          context,
          message: error.message,
        );
      }

      await loadData();
    } catch (error, stackTrace) {
      debugPrint(
        'Update customer vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppResultMessage.error(
        context,
        message:
        'Failed to update vehicle: $error',
      );
    }
  }


  List<String> getStoragePathsFromDeletionResult(
      Map<String, dynamic> result,
      ) {
    final rawPaths = result['storage_paths'];

    if (rawPaths is! List) {
      return <String>[];
    }

    final uniquePaths = <String>{};

    for (final rawPath in rawPaths) {
      final path = rawPath?.toString().trim() ?? '';

      if (path.isNotEmpty) {
        uniquePaths.add(path);
      }
    }

    return uniquePaths.toList();
  }

  Future<Map<String, int>> removeVehicleStorageFiles(
      List<String> storagePaths,
      ) async {
    if (storagePaths.isEmpty) {
      return {
        'deleted': 0,
        'failed': 0,
      };
    }

    int deletedCount = 0;
    int failedCount = 0;
    const chunkSize = 100;

    for (
    int start = 0;
    start < storagePaths.length;
    start += chunkSize
    ) {
      final end = (start + chunkSize) > storagePaths.length
          ? storagePaths.length
          : start + chunkSize;

      final chunk = storagePaths.sublist(
        start,
        end,
      );

      try {
        await supabase.storage
            .from('vehicle-photos')
            .remove(chunk);

        deletedCount += chunk.length;
      } catch (error, stackTrace) {
        failedCount += chunk.length;

        debugPrint(
          'Vehicle Storage cleanup failed: $error',
        );

        debugPrint(
          stackTrace.toString(),
        );
      }
    }

    return {
      'deleted': deletedCount,
      'failed': failedCount,
    };
  }

  Future<void> deleteVehicle(
      String vehicleId,
      ) async {
    final normalizedVehicleId =
    vehicleId.trim();

    if (normalizedVehicleId.isEmpty) {
      AppResultMessage.warning(
        context,
        message:
        'Vehicle information is missing.',
      );
      return;
    }

    try {
      final rpcResult = await supabase.rpc(
        'customer_delete_vehicle',
        params: {
          'p_vehicle_id':
          normalizedVehicleId,
        },
      );

      if (rpcResult is! Map) {
        throw Exception(
          'Invalid deletion result was returned.',
        );
      }

      final result =
      Map<String, dynamic>.from(
        rpcResult,
      );

      if (result['deleted'] != true) {
        throw Exception(
          'The vehicle was not deleted.',
        );
      }

      final storagePaths =
      getStoragePathsFromDeletionResult(
        result,
      );

      final cleanupResult =
      await removeVehicleStorageFiles(
        storagePaths,
      );

      try {
        await fetchVehicles();
        await fetchVehicleBookings();

        if (mounted) {
          setState(() {});
        }
      } catch (refreshError) {
        debugPrint(
          'Refresh vehicles after deletion failed: '
              '$refreshError',
        );
      }

      if (!mounted) return;

      final deletedPhotoCount =
          cleanupResult['deleted'] ?? 0;

      final failedPhotoCount =
          cleanupResult['failed'] ?? 0;

      if (failedPhotoCount > 0) {
        AppResultMessage.warning(
          context,
          message:
          'Vehicle deleted, but '
              '$failedPhotoCount photo(s) could not '
              'be removed from Storage. '
              '$deletedPhotoCount photo(s) were removed.',
          duration:
          const Duration(seconds: 5),
        );
      } else if (deletedPhotoCount > 0) {
        AppResultMessage.success(
          context,
          message:
          'Vehicle and $deletedPhotoCount '
              'photo(s) deleted successfully.',
        );
      } else {
        AppResultMessage.success(
          context,
          message:
          'Vehicle deleted successfully.',
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        AppResultMessage.error(
          context,
          message: error.message,
        );
      }

      try {
        await fetchVehicles();
        await fetchVehicleBookings();

        if (mounted) {
          setState(() {});
        }
      } catch (refreshError) {
        debugPrint(
          'Refresh vehicles after failed deletion: '
              '$refreshError',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Delete customer vehicle failed: $error',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppResultMessage.error(
        context,
        message:
        'Failed to delete vehicle: $error',
      );
    }
  }


  void showAddVehicleDialog() {
    final plateController =
    TextEditingController();

    final modelController =
    TextEditingController();

    showVehicleFormDialog(
      title: 'Add Vehicle',
      subtitle:
      'Enter your vehicle information. '
          'Photos are optional but recommended.',
      plateController: plateController,
      modelController: modelController,
      buttonText: 'Add Vehicle',
      existingVocPhotos: const [],
      existingVehiclePhotos: const [],
      onSave: (
          vocPhotos,
          vehiclePhotos,
          removedExistingPhotos,
          ) async {
        await addVehicle(
          plate: plateController.text,
          model: modelController.text,
          vocPhotos: vocPhotos,
          vehiclePhotos: vehiclePhotos,
        );
      },
    );
  }

  Future<void> showEditVehicleDialog(
      Map<String, dynamic> vehicle,
      ) async {
    final vehicleId =
    vehicle['vehicle_id']
        ?.toString()
        .trim();

    if (vehicleId == null ||
        vehicleId.isEmpty) {
      showMessage(
        'Vehicle information is missing.',
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                    'Loading vehicle photos...',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final allImages =
      await fetchVehicleImages(vehicleId);

      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      final existingVocPhotos = allImages
          .where(
            (image) =>
        image['image_type']
            ?.toString() ==
            'voc',
      )
          .map(
            (image) =>
        Map<String, dynamic>.from(
          image,
        ),
      )
          .toList();

      final existingVehiclePhotos =
      allImages
          .where(
            (image) =>
        image['image_type']
            ?.toString() ==
            'vehicle',
      )
          .map(
            (image) =>
        Map<String, dynamic>.from(
          image,
        ),
      )
          .toList();

      final plateController =
      TextEditingController(
        text:
        vehicle['plate_number']
            ?.toString() ??
            '',
      );

      final modelController =
      TextEditingController(
        text:
        vehicle['car_model']
            ?.toString() ??
            '',
      );

      final currentVerificationStatus =
          vehicle['verification_status']
              ?.toString() ??
              'Pending Claim';

      final isLinkedRecord =
          currentVerificationStatus == 'Verified' ||
              currentVerificationStatus ==
                  'Link Record';

      showVehicleFormDialog(
        title: 'Edit Vehicle',
        subtitle: isLinkedRecord
            ? 'You can add or remove photos without changing the verified status. '
            'Changing the plate number or car model will return this vehicle '
            'to Pending Claim for admin verification.'
            : 'Update vehicle information and manage uploaded photos.',
        plateController: plateController,
        modelController: modelController,
        buttonText: 'Save Changes',
        existingVocPhotos:
        existingVocPhotos,
        existingVehiclePhotos:
        existingVehiclePhotos,
        onSave: (
            newVocPhotos,
            newVehiclePhotos,
            removedExistingPhotos,
            ) async {
          await updateVehicle(
            vehicleId: vehicleId,
            plate: plateController.text,
            model: modelController.text,
            vocPhotos: newVocPhotos,
            vehiclePhotos:
            newVehiclePhotos,
            removedExistingPhotos:
            removedExistingPhotos,
          );
        },
      );
    } catch (error) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();

        showMessage(
          'Failed to load vehicle photos: '
              '$error',
        );
      }
    }
  }

  Widget buildPhotoPickerSection({
    required String title,
    required String description,
    required List<Map<String, dynamic>>
    existingPhotos,
    required List<XFile> photos,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required ValueChanged<int>
    onRemoveExisting,
    required ValueChanged<int> onRemoveNew,
  }) {
    final totalCount =
        existingPhotos.length + photos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: const Text(
                  'Optional • Recommended',
                  style: TextStyle(
                    color: Color(0xFF339BFF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Text(
            description,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),

          if (totalCount > 0) ...[
            const SizedBox(height: 12),

            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: totalCount,
                separatorBuilder: (
                    context,
                    index,
                    ) {
                  return const SizedBox(
                    width: 10,
                  );
                },
                itemBuilder: (
                    context,
                    index,
                    ) {
                  final isExisting =
                      index <
                          existingPhotos.length;

                  if (isExisting) {
                    final image =
                    existingPhotos[index];

                    final signedUrl =
                    image['signed_url']
                        ?.toString()
                        .trim();

                    final canOpen =
                        signedUrl != null &&
                            signedUrl.isNotEmpty;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                          onTap: canOpen
                              ? () {
                            showVehicleImagePreview(
                              imageUrl:
                              signedUrl,
                              title:
                              '$title ${index + 1}',
                            );
                          }
                              : null,
                          child: ClipRRect(
                            borderRadius:
                            BorderRadius.circular(
                              12,
                            ),
                            child: canOpen
                                ? Image.network(
                              signedUrl,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              loadingBuilder: (
                                  context,
                                  child,
                                  progress,
                                  ) {
                                if (progress ==
                                    null) {
                                  return child;
                                }

                                return Container(
                                  width: 88,
                                  height: 88,
                                  color: Colors
                                      .grey
                                      .shade200,
                                  child:
                                  const Center(
                                    child:
                                    CircularProgressIndicator(
                                      strokeWidth:
                                      2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (
                                  context,
                                  error,
                                  stackTrace,
                                  ) {
                                return Container(
                                  width: 88,
                                  height: 88,
                                  color: Colors
                                      .grey
                                      .shade200,
                                  child:
                                  const Icon(
                                    Icons
                                        .broken_image,
                                  ),
                                );
                              },
                            )
                                : Container(
                              width: 88,
                              height: 88,
                              color: Colors
                                  .grey
                                  .shade200,
                              child:
                              const Icon(
                                Icons
                                    .broken_image,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration:
                            BoxDecoration(
                              color: Colors.black
                                  .withOpacity(0.65),
                              borderRadius:
                              BorderRadius.circular(
                                6,
                              ),
                            ),
                            child: const Text(
                              'Uploaded',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          right: -6,
                          top: -6,
                          child: InkWell(
                            onTap: () {
                              onRemoveExisting(
                                index,
                              );
                            },
                            child:
                            const CircleAvatar(
                              radius: 11,
                              backgroundColor:
                              Colors.red,
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final newIndex =
                      index -
                          existingPhotos.length;

                  final photo =
                  photos[newIndex];

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                        child:
                        FutureBuilder<Uint8List>(
                          future:
                          photo.readAsBytes(),
                          builder: (
                              context,
                              snapshot,
                              ) {
                            if (snapshot.hasData) {
                              return Image.memory(
                                snapshot.data!,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                              );
                            }

                            return Container(
                              width: 88,
                              height: 88,
                              color:
                              Colors.grey.shade200,
                              child: const Center(
                                child:
                                CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF339BFF,
                            ).withOpacity(0.88),
                            borderRadius:
                            BorderRadius.circular(
                              6,
                            ),
                          ),
                          child: const Text(
                            'New',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        right: -6,
                        top: -6,
                        child: InkWell(
                          onTap: () {
                            onRemoveNew(newIndex);
                          },
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor:
                            Colors.red,
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(
                    Icons.camera_alt,
                    size: 18,
                  ),
                  label:
                  const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(
                    Icons.photo_library,
                    size: 18,
                  ),
                  label:
                  const Text('Gallery'),
                ),
              ),
            ],
          ),

          if (totalCount > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$totalCount photo(s)',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void showVehicleFormDialog({
    required String title,
    required String subtitle,
    required TextEditingController
    plateController,
    required TextEditingController
    modelController,
    required String buttonText,
    required List<Map<String, dynamic>>
    existingVocPhotos,
    required List<Map<String, dynamic>>
    existingVehiclePhotos,
    required Future<void> Function(
        List<XFile> vocPhotos,
        List<XFile> vehiclePhotos,
        List<Map<String, dynamic>>
        removedExistingPhotos,
        ) onSave,
  }) {
    final List<XFile> vocPhotos = [];
    final List<XFile> vehiclePhotos = [];

    final currentExistingVocPhotos =
    existingVocPhotos
        .map(
          (image) =>
      Map<String, dynamic>.from(
        image,
      ),
    )
        .toList();

    final currentExistingVehiclePhotos =
    existingVehiclePhotos
        .map(
          (image) =>
      Map<String, dynamic>.from(
        image,
      ),
    )
        .toList();

    final removedExistingPhotos =
    <Map<String, dynamic>>[];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              dialogContext,
              setDialogState,
              ) {
            return Dialog(
              insetPadding:
              const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 28,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(26),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding:
                  const EdgeInsets.fromLTRB(
                    22,
                    22,
                    22,
                    18,
                  ),
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(
                          18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFD7E5FA,
                          ),
                          borderRadius:
                          BorderRadius.circular(
                            22,
                          ),
                        ),
                        child: Column(
                          children: [
                            const CircleAvatar(
                              radius: 32,
                              backgroundColor:
                              Color(
                                0xFF339BFF,
                              ),
                              child: Icon(
                                Icons.directions_car,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(
                              height: 14,
                            ),
                            Text(
                              title,
                              style:
                              const TextStyle(
                                fontSize: 22,
                                fontWeight:
                                FontWeight.bold,
                                color:
                                Color(
                                  0xFF1F2937,
                                ),
                              ),
                            ),
                            const SizedBox(
                              height: 6,
                            ),
                            Text(
                              subtitle,
                              textAlign:
                              TextAlign.center,
                              style:
                              const TextStyle(
                                color:
                                Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      buildInputBox(
                        controller:
                        plateController,
                        label:
                        'Vehicle Plate Number',
                        hintText:
                        'Example: JSA9259',
                        icon:
                        Icons.confirmation_number,
                      ),

                      const SizedBox(height: 16),

                      buildInputBox(
                        controller:
                        modelController,
                        label: 'Car Model',
                        hintText:
                        'Example: HONDA CITY',
                        icon:
                        Icons.directions_car,
                      ),

                      const SizedBox(height: 16),

                      buildPhotoPickerSection(
                        title: 'VOC Photos',
                        description:
                        'Upload ownership document photos to help the admin verify the vehicle.',
                        existingPhotos:
                        currentExistingVocPhotos,
                        photos: vocPhotos,
                        onCamera: () {
                          unawaited(
                            pickVehiclePhotos(
                              source:
                              ImageSource.camera,
                              targetPhotos:
                              vocPhotos,
                              setDialogState:
                              setDialogState,
                            ),
                          );
                        },
                        onGallery: () {
                          unawaited(
                            pickVehiclePhotos(
                              source:
                              ImageSource.gallery,
                              targetPhotos:
                              vocPhotos,
                              setDialogState:
                              setDialogState,
                            ),
                          );
                        },
                        onRemoveExisting:
                            (index) {
                          setDialogState(() {
                            final removed =
                            currentExistingVocPhotos
                                .removeAt(
                              index,
                            );

                            removedExistingPhotos
                                .add(removed);
                          });
                        },
                        onRemoveNew: (index) {
                          setDialogState(() {
                            vocPhotos.removeAt(
                              index,
                            );
                          });
                        },
                      ),

                      const SizedBox(height: 14),

                      buildPhotoPickerSection(
                        title: 'Vehicle Photos',
                        description:
                        'Upload exterior, interior or vehicle condition photos.',
                        existingPhotos:
                        currentExistingVehiclePhotos,
                        photos: vehiclePhotos,
                        onCamera: () {
                          unawaited(
                            pickVehiclePhotos(
                              source:
                              ImageSource.camera,
                              targetPhotos:
                              vehiclePhotos,
                              setDialogState:
                              setDialogState,
                            ),
                          );
                        },
                        onGallery: () {
                          unawaited(
                            pickVehiclePhotos(
                              source:
                              ImageSource.gallery,
                              targetPhotos:
                              vehiclePhotos,
                              setDialogState:
                              setDialogState,
                            ),
                          );
                        },
                        onRemoveExisting:
                            (index) {
                          setDialogState(() {
                            final removed =
                            currentExistingVehiclePhotos
                                .removeAt(
                              index,
                            );

                            removedExistingPhotos
                                .add(removed);
                          });
                        },
                        onRemoveNew: (index) {
                          setDialogState(() {
                            vehiclePhotos.removeAt(
                              index,
                            );
                          });
                        },
                      ),

                      const SizedBox(height: 14),

                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                          Colors.orange.shade50,
                          borderRadius:
                          BorderRadius.circular(
                            16,
                          ),
                          border: Border.all(
                            color: Colors.orange
                                .withOpacity(0.35),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Photos are optional. Clear VOC and vehicle photos are recommended to help the admin verify the vehicle.',
                                style: TextStyle(
                                  color:
                                  Colors.black87,
                                  fontSize: 12,
                                  height: 1.35,
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
                            child: SizedBox(
                              height: 50,
                              child:
                              OutlinedButton(
                                style:
                                OutlinedButton
                                    .styleFrom(
                                  foregroundColor:
                                  const Color(
                                    0xFF339BFF,
                                  ),
                                  side:
                                  const BorderSide(
                                    color: Color(
                                      0xFF339BFF,
                                    ),
                                  ),
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius
                                        .circular(
                                      16,
                                    ),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.pop(
                                    dialogContext,
                                  );
                                },
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontWeight:
                                    FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child:
                              ElevatedButton(
                                style:
                                ElevatedButton
                                    .styleFrom(
                                  backgroundColor:
                                  const Color(
                                    0xFF339BFF,
                                  ),
                                  foregroundColor:
                                  Colors.white,
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius
                                        .circular(
                                      16,
                                    ),
                                  ),
                                ),
                                onPressed: () async {
                                  final plate =
                                  plateController
                                      .text
                                      .trim();

                                  final model =
                                  modelController
                                      .text
                                      .trim();

                                  if (plate.isEmpty ||
                                      model.isEmpty) {
                                    showMessage(
                                      'Please complete vehicle information.',
                                    );
                                    return;
                                  }

                                  final selectedVocPhotos =
                                  List<XFile>.from(
                                    vocPhotos,
                                  );

                                  final selectedVehiclePhotos =
                                  List<XFile>.from(
                                    vehiclePhotos,
                                  );

                                  final selectedRemovedPhotos =
                                  removedExistingPhotos
                                      .map(
                                        (image) =>
                                    Map<String,
                                        dynamic>.from(
                                      image,
                                    ),
                                  )
                                      .toList();

                                  Navigator.pop(
                                    dialogContext,
                                  );

                                  await onSave(
                                    selectedVocPhotos,
                                    selectedVehiclePhotos,
                                    selectedRemovedPhotos,
                                  );
                                },
                                child: Text(
                                  buttonText,
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight.bold,
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

  Widget buildUploadedPhotoSection({
    required String title,
    required List<Map<String, dynamic>>
    images,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color:
                  const Color(0xFFD7E5FA),
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  '${images.length}',
                  style: const TextStyle(
                    color: Color(0xFF339BFF),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (images.isEmpty)
            const Text(
              'No photos uploaded.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            )
          else
            SizedBox(
              height: 95,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (
                    context,
                    index,
                    ) {
                  return const SizedBox(
                    width: 10,
                  );
                },
                itemBuilder: (
                    context,
                    index,
                    ) {
                  final url =
                  images[index]['signed_url']
                      ?.toString()
                      .trim();

                  final canOpen =
                      url != null &&
                          url.isNotEmpty;

                  return InkWell(
                    borderRadius:
                    BorderRadius.circular(12),
                    onTap: canOpen
                        ? () {
                      showVehicleImagePreview(
                        imageUrl: url,
                        title:
                        '$title ${index + 1}',
                      );
                    }
                        : null,
                    child: ClipRRect(
                      borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                      child: canOpen
                          ? Image.network(
                        url,
                        width: 100,
                        height: 90,
                        fit: BoxFit.cover,
                        loadingBuilder: (
                            context,
                            child,
                            progress,
                            ) {
                          if (progress ==
                              null) {
                            return child;
                          }

                          return Container(
                            width: 100,
                            height: 90,
                            color: Colors
                                .grey
                                .shade200,
                            child:
                            const Center(
                              child:
                              CircularProgressIndicator(
                                strokeWidth:
                                2,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (
                            context,
                            error,
                            stackTrace,
                            ) {
                          return Container(
                            width: 100,
                            height: 90,
                            color: Colors
                                .grey
                                .shade200,
                            child:
                            const Icon(
                              Icons
                                  .broken_image,
                            ),
                          );
                        },
                      )
                          : Container(
                        width: 100,
                        height: 90,
                        color:
                        Colors.grey.shade200,
                        child: const Icon(
                          Icons.broken_image,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void showVehicleDetailDialog(
      Map<String, dynamic> vehicle,
      ) {
    final vehicleId =
        vehicle['vehicle_id']
            ?.toString()
            .trim() ??
            '';

    final booking =
    vehicleBookings[vehicleId];

    final status =
        vehicle['verification_status'] ??
            'Pending Claim';

    final imagesFuture =
    fetchVehicleImages(vehicleId);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
          const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 28,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
              MediaQuery.of(dialogContext)
                  .size
                  .height *
                  0.84,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding:
                const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding:
                      const EdgeInsets.all(
                        16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFD7E5FA,
                        ),
                        borderRadius:
                        BorderRadius.circular(
                          18,
                        ),
                      ),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor:
                            Color(
                              0xFF339BFF,
                            ),
                            child: Icon(
                              Icons.directions_car,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            vehicle['plate_number']
                                ?.toString() ??
                                '',
                            style:
                            const TextStyle(
                              fontSize: 20,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                          Text(
                            vehicle['car_model']
                                ?.toString() ??
                                '',
                            style:
                            const TextStyle(
                              color:
                              Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    buildDetailRow(
                      'Plate Number',
                      vehicle['plate_number'] ??
                          '',
                    ),

                    buildDetailRow(
                      'Car Model',
                      vehicle['car_model'] ??
                          '',
                    ),

                    buildDetailRow(
                      'Record Status',
                      getDisplayStatus(
                        status.toString(),
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Align(
                      alignment:
                      Alignment.centerLeft,
                      child: Text(
                        'Uploaded Photos',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    FutureBuilder<
                        List<
                            Map<String,
                                dynamic>>>(
                      future: imagesFuture,
                      builder: (
                          context,
                          snapshot,
                          ) {
                        if (snapshot
                            .connectionState ==
                            ConnectionState
                                .waiting) {
                          return const Padding(
                            padding:
                            EdgeInsets.all(22),
                            child:
                            CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets
                                .all(12),
                            decoration:
                            BoxDecoration(
                              color:
                              Colors.red.shade50,
                              borderRadius:
                              BorderRadius
                                  .circular(12),
                            ),
                            child: Text(
                              'Unable to load photos: '
                                  '${snapshot.error}',
                              style:
                              const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }

                        final allImages =
                            snapshot.data ?? [];

                        final vocImages =
                        allImages
                            .where(
                              (image) =>
                          image['image_type']
                              ?.toString() ==
                              'voc',
                        )
                            .toList();

                        final vehiclePhotos =
                        allImages
                            .where(
                              (image) =>
                          image['image_type']
                              ?.toString() ==
                              'vehicle',
                        )
                            .toList();

                        return Column(
                          children: [
                            buildUploadedPhotoSection(
                              title:
                              'VOC Photos',
                              images:
                              vocImages,
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            buildUploadedPhotoSection(
                              title:
                              'Vehicle Photos',
                              images:
                              vehiclePhotos,
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 8),

                    const Align(
                      alignment:
                      Alignment.centerLeft,
                      child: Text(
                        'Appointment Information',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (booking != null)
                      buildDetailRow(
                        'Appointment Date',
                        formatDate(
                          booking[
                          'appointment_date']
                              .toString(),
                        ),
                      )
                    else
                      const Align(
                        alignment:
                        Alignment.centerLeft,
                        child: Text(
                          'Appointment: None',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child:
                          ElevatedButton.icon(
                            style:
                            ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              const Color(
                                0xFF339BFF,
                              ),
                              foregroundColor:
                              Colors.white,
                            ),
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );

                              unawaited(
                                showEditVehicleDialog(
                                  vehicle,
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.edit,
                              size: 18,
                            ),
                            label: const Text(
                              'Edit / Photos',
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child:
                          OutlinedButton.icon(
                            style: OutlinedButton
                                .styleFrom(
                              foregroundColor:
                              Colors.red,
                              side:
                              const BorderSide(
                                color: Colors.red,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                              );

                              showDeleteVehicleDialog(
                                vehicleId,
                              );
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                            ),
                            label: const Text(
                              'Delete',
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        child:
                        const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  void showDeleteVehicleDialog(String vehicleId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Vehicle'),
          content: const Text('Are you sure you want to delete this vehicle?'),
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
                Navigator.pop(context);
                await deleteVehicle(vehicleId);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Widget buildInputBox({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
  }) {
    return SizedBox(
      height: 76,
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            return newValue.copyWith(
              text: newValue.text.toUpperCase(),
              selection: newValue.selection,
            );
          }),
        ],
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, color: const Color(0xFF339BFF)),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildDetailRow(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$title:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value.toString())),
        ],
      ),
    );
  }

  Widget buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding:
        const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
          Colors.white.withOpacity(
            0.97,
          ),
          borderRadius:
          BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:
              Colors.black.withOpacity(
                0.05,
              ),
              blurRadius: 9,
              offset:
              const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                const Color(0xFFEAF4FF),
                borderRadius:
                BorderRadius.circular(
                  13,
                ),
              ),
              child: Icon(
                icon,
                color:
                const Color(0xFF339BFF),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style:
                    const TextStyle(
                      color:
                      Color(0xFF1F2937),
                      fontSize: 21,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    const TextStyle(
                      color:
                      Colors.black54,
                      fontSize: 11.5,
                      fontWeight:
                      FontWeight.w600,
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

  Widget buildAppointmentText(Map<String, dynamic>? booking) {
    if (booking == null) {
      return const Text(
        'Appointment: None',
        style: TextStyle(
          color: Colors.black54,
          fontSize: 13,
        ),
      );
    }

    return Text(
      'Appointment Date: ${formatDate(booking['appointment_date'].toString())}',
      style: const TextStyle(
        color: Color(0xFF339BFF),
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
            onPressed == null ? Colors.grey.shade300 : const Color(0xFF339BFF),
            foregroundColor: onPressed == null ? Colors.black45 : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildVehicleCard(
      Map<String, dynamic> vehicle,
      ) {
    final status =
        vehicle['verification_status'] ??
            'Pending Claim';

    final displayStatus =
    getDisplayStatus(
      status.toString(),
    );

    final isLinked =
        displayStatus == 'Link Record';

    final vehicleId =
        vehicle['vehicle_id']
            ?.toString() ??
            '';

    final plateNumber =
        vehicle['plate_number']
            ?.toString()
            .trim() ??
            '';

    final carModel =
        vehicle['car_model']
            ?.toString()
            .trim() ??
            '';

    final booking =
    vehicleBookings[vehicleId];

    return Container(
      margin:
      const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: isLinked
              ? Colors.green
              .withOpacity(0.12)
              : Colors.orange
              .withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(
              0.06,
            ),
            blurRadius: 12,
            offset:
            const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(22),
        onTap: () {
          showVehicleDetailDialog(
            vehicle,
          );
        },
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color:
                      const Color(
                        0xFFEAF4FF,
                      ),
                      borderRadius:
                      BorderRadius.circular(
                        18,
                      ),
                    ),
                    child: const Icon(
                      Icons
                          .directions_car_rounded,
                      color: Color(
                        0xFF339BFF,
                      ),
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          plateNumber.isEmpty
                              ? 'Plate Not Provided'
                              : plateNumber,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            color: Color(
                              0xFF1F2937,
                            ),
                            fontSize: 18,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          carModel.isEmpty
                              ? 'Model Not Provided'
                              : carModel,
                          maxLines: 1,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            color:
                            Colors.black54,
                            fontSize: 12.5,
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                        const SizedBox(
                          height: 9,
                        ),
                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration:
                          BoxDecoration(
                            color:
                            getStatusBackgroundColor(
                              status.toString(),
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              20,
                            ),
                          ),
                          child: Row(
                            mainAxisSize:
                            MainAxisSize.min,
                            children: [
                              Icon(
                                isLinked
                                    ? Icons
                                    .verified_rounded
                                    : Icons
                                    .pending_actions_rounded,
                                color:
                                getStatusColor(
                                  status.toString(),
                                ),
                                size: 14,
                              ),
                              const SizedBox(
                                width: 5,
                              ),
                              Text(
                                displayStatus,
                                style:
                                TextStyle(
                                  color:
                                  getStatusColor(
                                    status.toString(),
                                  ),
                                  fontWeight:
                                  FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons
                        .chevron_right_rounded,
                    size: 23,
                    color: Colors.black38,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.all(
                  12,
                ),
                decoration: BoxDecoration(
                  color: booking == null
                      ? const Color(
                    0xFFF7F9FC,
                  )
                      : const Color(
                    0xFFEAF4FF,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    15,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      booking == null
                          ? Icons
                          .event_available_outlined
                          : Icons
                          .calendar_month_rounded,
                      color: booking == null
                          ? Colors.black45
                          : const Color(
                        0xFF339BFF,
                      ),
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child:
                      buildAppointmentText(
                        booking,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLinked) ...[
                const SizedBox(height: 11),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(
                    11,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    Colors.orange.shade50,
                    borderRadius:
                    BorderRadius.circular(
                      14,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons
                            .info_outline_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Admin verification is pending. Clear VOC and vehicle photos can help the review.',
                          style: TextStyle(
                            color:
                            Color(0xFF374151),
                            fontSize: 11,
                            height: 1.35,
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 13),
              Row(
                children: [
                  buildActionButton(
                    icon:
                    Icons.history_rounded,
                    label:
                    'Service Record',
                    onPressed: () {
                      goToServiceRecords(
                        plateNumber,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  buildActionButton(
                    icon: Icons
                        .calendar_month_rounded,
                    label: 'Book Service',
                    onPressed:
                    goToBookingPage,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  const Icon(
                    Icons.touch_app_outlined,
                    color:
                    Color(0xFF339BFF),
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Tap the card to view vehicle details and photos',
                      style: TextStyle(
                        color: Colors.black45,
                        fontSize: 10.5,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    isLinked
                        ? 'Verified'
                        : 'Reviewing',
                    style: TextStyle(
                      color: isLinked
                          ? Colors.green
                          : Colors.orange,
                      fontSize: 10.5,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final displayVehicles = filteredVehicles;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('My Vehicles'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [
          NotificationBell(
            isAdmin: false,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: loadData,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  20,
                ),
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
                      'My Vehicle List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage your vehicles, service records and appointments',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        buildSummaryCard(
                          icon: Icons.directions_car,
                          title: 'Vehicles',
                          value: '${vehicles.length}',
                        ),
                        const SizedBox(width: 12),
                        buildSummaryCard(
                          icon: Icons.pending_actions,
                          title: 'Pending',
                          value: '$pendingClaimCount',
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons
                                .verified_user_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Pending Claim means the admin is reviewing the vehicle. Link Record means the vehicle has been verified and linked to your account.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                height: 1.4,
                                fontWeight:
                                FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText:
                        'Search by plate, model or status',
                        prefixIcon: const Icon(
                          Icons.search,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                          BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),

            if (displayVehicles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Container(
                    margin:
                    const EdgeInsets.all(24),
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 34,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(
                        22,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFF339BFF,
                        ).withOpacity(0.10),
                      ),
                    ),
                    child: Column(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration:
                          BoxDecoration(
                            color: const Color(
                              0xFFEAF4FF,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              24,
                            ),
                          ),
                          child: const Icon(
                            Icons
                                .directions_car_outlined,
                            color: Color(
                              0xFF339BFF,
                            ),
                            size: 37,
                          ),
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        Text(
                          searchText.trim().isEmpty
                              ? 'No Vehicles Yet'
                              : 'No Matching Vehicles',
                          textAlign:
                          TextAlign.center,
                          style:
                          const TextStyle(
                            color: Color(
                              0xFF1F2937,
                            ),
                            fontSize: 18,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 7,
                        ),
                        Text(
                          searchText.trim().isEmpty
                              ? 'Add your first vehicle to manage photos, service records, and appointments.'
                              : 'Try another plate number, model, or claim status.',
                          textAlign:
                          TextAlign.center,
                          style:
                          const TextStyle(
                            color:
                            Colors.black54,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        if (searchText
                            .trim()
                            .isEmpty) ...[
                          const SizedBox(
                            height: 17,
                          ),
                          ElevatedButton.icon(
                            style:
                            ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              const Color(
                                0xFF339BFF,
                              ),
                              foregroundColor:
                              Colors.white,
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  14,
                                ),
                              ),
                            ),
                            onPressed:
                            showAddVehicleDialog,
                            icon: const Icon(
                              Icons.add_rounded,
                            ),
                            label: const Text(
                              'Add First Vehicle',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  100,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return buildVehicleCard(
                        displayVehicles[index],
                      );
                    },
                    childCount: displayVehicles.length,
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
              heroTag: 'myVehiclesBackToTop',
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: scrollToTop,
              child: const Icon(
                Icons.keyboard_arrow_up,
              ),
            ),

          if (showBackToTop)
            const SizedBox(height: 12),

          FloatingActionButton.extended(
            heroTag: 'myVehiclesAddVehicle',
            backgroundColor: const Color(0xFF339BFF),
            foregroundColor: Colors.white,
            onPressed: showAddVehicleDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    );
  }
}