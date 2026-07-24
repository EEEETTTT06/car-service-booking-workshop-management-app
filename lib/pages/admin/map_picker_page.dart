import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapPickerPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const MapPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const String googleApiKey =
      'AIzaSyDSHoyToObC5Y7BKO0n72MLSDHZ4UsJwEE';
  GoogleMapController? mapController;
  final searchController = TextEditingController();
  List<dynamic> placePredictions = [];

  bool isSearching = false;

  LatLng selectedLocation = const LatLng(1.4927, 103.7414);
  String selectedAddress = 'Johor Bahru, Malaysia';
  String placeName = 'Selected Workshop Location';

  bool isLoadingLocation = true;
  bool isLoadingAddress = false;
  MapType currentMapType = MapType.normal;
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    if (widget.initialLatitude != null &&
        widget.initialLongitude != null) {
      selectedLocation = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );

      selectedAddress =
          widget.initialAddress ?? 'Selected Workshop Location';

      isLoadingLocation = false;
    } else {
      loadCurrentLocation();
    }
  }

  Future<void> loadCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          isLoadingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final currentLatLng = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        selectedLocation = currentLatLng;
      });

      await updateAddressFromLatLng(currentLatLng);

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLatLng, 16),
      );
    } catch (_) {
      setState(() {
        isLoadingLocation = false;
      });
    }
  }

  Future<void> updateAddressFromLatLng(LatLng position) async {
    setState(() {
      isLoadingAddress = true;
    });

    try {
      final placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        final addressParts = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ].where((item) => item != null && item.toString().trim().isNotEmpty);

        setState(() {
          placeName = place.name?.isNotEmpty == true
              ? place.name!
              : 'Selected Workshop Location';
          selectedAddress = addressParts.join(', ');
        });
      }
    } catch (_) {
      setState(() {
        selectedAddress =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });
    } finally {
      setState(() {
        isLoadingLocation = false;
        isLoadingAddress = false;
      });
    }
  }

  Future<void> searchAddress() async {
    final query = searchController.text.trim();

    if (query.isEmpty) {
      return;
    }

    setState(() {
      isLoadingAddress = true;
    });

    try {
      final locations = await geo.locationFromAddress(query);

      if (locations.isNotEmpty) {
        final location = locations.first;

        final newLatLng = LatLng(
          location.latitude,
          location.longitude,
        );

        setState(() {
          selectedLocation = newLatLng;
        });

        await updateAddressFromLatLng(newLatLng);

        mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(newLatLng, 16),
        );
      }
    } catch (_) {
      setState(() {
        selectedAddress = 'Address not found. Please try again.';
        isLoadingAddress = false;
      });
    }
  }

  Future<void> autoCompleteSearch(String value) async {
    if (value.isEmpty) {
      setState(() {
        placePredictions = [];
      });
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$value'
        '&key=$googleApiKey'
        '&components=country:my';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        placePredictions = data['predictions'];
      });
    }
  }

  Future<void> selectPlaceFromPrediction(dynamic prediction) async {
    final placeId = prediction['place_id'];

    if (placeId == null) return;

    final url =
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&key=$googleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final result = data['result'];

      if (result != null) {
        final location = result['geometry']['location'];

        final newLatLng = LatLng(
          location['lat'],
          location['lng'],
        );

        setState(() {
          selectedLocation = newLatLng;
          selectedAddress = result['formatted_address'] ?? prediction['description'];
          placeName = result['name'] ?? 'Selected Workshop Location';
          placePredictions = [];
          searchController.text = selectedAddress;
        });

        FocusScope.of(context).unfocus();

        mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(newLatLng, 16),
        );
      }
    }
  }

  void saveLocation() {
    Navigator.pop(context, {
      'placeName': placeName,
      'address': selectedAddress,
      'latitude': selectedLocation.latitude,
      'longitude': selectedLocation.longitude,
    });
  }


  String get currentMapTypeLabel {
    if (currentMapType == MapType.satellite) {
      return 'Satellite';
    }

    if (currentMapType == MapType.terrain) {
      return 'Terrain';
    }

    return 'Normal';
  }

  Widget buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 5,
      shadowColor: Colors.black.withOpacity(0.18),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Icon(
              icon,
              color: const Color(0xFF339BFF),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        14,
        4,
        6,
        4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Color(0xFFEAF4FF),
              borderRadius: BorderRadius.all(
                Radius.circular(12),
              ),
            ),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF339BFF),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {});
                autoCompleteSearch(value);
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => searchAddress(),
              decoration: const InputDecoration(
                hintText: 'Search workshop address',
                hintStyle: TextStyle(
                  color: Colors.black38,
                  fontSize: 13.5,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (searchController.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear Search',
              onPressed: () {
                searchController.clear();

                setState(() {
                  placePredictions = [];
                });

                FocusScope.of(context).unfocus();
              },
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.black45,
                size: 21,
              ),
            ),
          IconButton(
            tooltip: 'Search',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF339BFF),
              foregroundColor: Colors.white,
            ),
            onPressed: searchAddress,
            icon: const Icon(
              Icons.arrow_forward_rounded,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPredictionList() {
    return Container(
      constraints: const BoxConstraints(
        maxHeight: 260,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFF339BFF).withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(
            vertical: 6,
          ),
          itemCount: placePredictions.length,
          separatorBuilder: (_, __) {
            return const Divider(
              height: 1,
              indent: 58,
            );
          },
          itemBuilder: (context, index) {
            final prediction = placePredictions[index];

            final structured =
            prediction['structured_formatting'];

            final mainText =
            structured is Map
                ? structured['main_text']?.toString()
                : null;

            final secondaryText =
            structured is Map
                ? structured['secondary_text']?.toString()
                : null;

            final description =
                prediction['description']?.toString() ??
                    'Location';

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF339BFF),
                  size: 20,
                ),
              ),
              title: Text(
                mainText?.trim().isNotEmpty == true
                    ? mainText!
                    : description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: secondaryText?.trim().isNotEmpty == true
                  ? Text(
                secondaryText!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 11.5,
                ),
              )
                  : null,
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.black38,
              ),
              onTap: () async {
                await selectPlaceFromPrediction(prediction);
              },
            );
          },
        ),
      ),
    );
  }

  Widget buildCoordinateChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF339BFF),
              size: 16,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
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

  Widget buildSelectedLocationPanel(
      BuildContext context,
      ) {
    final screenHeight =
        MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.38,
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF339BFF).withOpacity(0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF339BFF),
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Location',
                          style: TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Confirm the workshop location below.',
                          style: TextStyle(
                            color: Colors.black45,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLoadingAddress)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF339BFF),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 13),
              if (placeName.trim().isNotEmpty)
                Text(
                  placeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (placeName.trim().isNotEmpty)
                const SizedBox(height: 5),
              Text(
                selectedAddress,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selectedAddress
                      .toLowerCase()
                      .contains('not found')
                      ? Colors.red
                      : Colors.black54,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  buildCoordinateChip(
                    icon: Icons.north_rounded,
                    label: 'LATITUDE',
                    value: selectedLocation.latitude
                        .toStringAsFixed(6),
                  ),
                  const SizedBox(width: 9),
                  buildCoordinateChip(
                    icon: Icons.east_rounded,
                    label: 'LONGITUDE',
                    value: selectedLocation.longitude
                        .toStringAsFixed(6),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      color: Color(0xFF339BFF),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap the map or drag the marker to adjust the location.',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 10.8,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 13),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF339BFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed:
                  isLoadingAddress ? null : saveLocation,
                  icon: const Icon(
                    Icons.check_circle_outline,
                    size: 21,
                  ),
                  label: const Text(
                    'Use This Location',
                    style: TextStyle(
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
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen =
        mediaQuery.viewInsets.bottom > 0;

    final controlBottom =
    isKeyboardOpen ? 24.0 : mediaQuery.size.height * 0.39;

    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Choose Workshop Location'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: selectedLocation,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            mapType: currentMapType,
            onMapCreated: (controller) {
              mapController = controller;
            },
            markers: {
              Marker(
                markerId: const MarkerId(
                  'selected-location',
                ),
                position: selectedLocation,
                draggable: true,
                infoWindow: InfoWindow(
                  title: placeName,
                  snippet: selectedAddress,
                ),
                onDragEnd: (newPosition) async {
                  setState(() {
                    selectedLocation = newPosition;
                  });

                  await updateAddressFromLatLng(
                    newPosition,
                  );
                },
              ),
            },
            onTap: (position) async {
              FocusScope.of(context).unfocus();

              setState(() {
                selectedLocation = position;
                placePredictions = [];
              });

              await updateAddressFromLatLng(
                position,
              );
            },
            onLongPress: (position) async {
              FocusScope.of(context).unfocus();

              setState(() {
                selectedLocation = position;
                placePredictions = [];
              });

              await updateAddressFromLatLng(
                position,
              );
            },
          ),

          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: buildSearchBar(),
            ),
          ),

          if (placePredictions.isNotEmpty)
            Positioned(
              top: 82,
              left: 14,
              right: 14,
              child: buildPredictionList(),
            ),

          Positioned(
            right: 14,
            bottom: controlBottom + 64,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:
                        Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    currentMapTypeLabel,
                    style: const TextStyle(
                      color: Color(0xFF339BFF),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                buildMapControlButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'Change Map Type',
                  onPressed: () {
                    setState(() {
                      if (currentMapType == MapType.normal) {
                        currentMapType = MapType.satellite;
                      } else if (currentMapType ==
                          MapType.satellite) {
                        currentMapType = MapType.terrain;
                      } else {
                        currentMapType = MapType.normal;
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                buildMapControlButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Use Current Location',
                  onPressed: () async {
                    await loadCurrentLocation();
                  },
                ),
              ],
            ),
          ),

          if (!isKeyboardOpen)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: buildSelectedLocationPanel(
                  context,
                ),
              ),
            ),

          if (isLoadingAddress && !isLoadingLocation)
            const Positioned(
              top: 88,
              right: 24,
              child: Material(
                color: Colors.white,
                elevation: 4,
                borderRadius: BorderRadius.all(
                  Radius.circular(20),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF339BFF),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Updating address...',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (isLoadingLocation)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.82),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Color(0xFFEAF4FF),
                          borderRadius: BorderRadius.all(
                            Radius.circular(22),
                          ),
                        ),
                        child: Icon(
                          Icons.my_location_rounded,
                          color: Color(0xFF339BFF),
                          size: 34,
                        ),
                      ),
                      SizedBox(height: 16),
                      CircularProgressIndicator(
                        color: Color(0xFF339BFF),
                      ),
                      SizedBox(height: 13),
                      Text(
                        'Finding your current location...',
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
