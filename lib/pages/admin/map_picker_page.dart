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

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: const Color(0xFFD7E5FA),
      appBar: AppBar(
        title: const Text('Choose Workshop Location'),
        centerTitle: true,
        backgroundColor: const Color(0xFF339BFF),
        foregroundColor: Colors.white,
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
            mapType: currentMapType,
            onMapCreated: (controller) {
              mapController = controller;
            },
            markers: {
              Marker(
                markerId: const MarkerId('selected-location'),
                position: selectedLocation,
                draggable: true,
                onDragEnd: (newPosition) async {
                  setState(() {
                    selectedLocation = newPosition;
                  });

                  await updateAddressFromLatLng(newPosition);
                },
              ),
            },
            onTap: (position) async {
              setState(() {
                selectedLocation = position;
              });

              await updateAddressFromLatLng(position);
            },
            onLongPress: (position) async {
              setState(() {
                selectedLocation = position;
              });

              await updateAddressFromLatLng(position);
            },
          ),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    color: Color(0xFF339BFF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: autoCompleteSearch,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => searchAddress(),
                      decoration: const InputDecoration(
                        hintText: 'Search address...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF339BFF),
                    onPressed: searchAddress,
                  ),
                ],
              ),
            ),
          ),
          if (placePredictions.isNotEmpty)
            Positioned(
              top: 82,
              left: 16,
              right: 16,
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 260,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: placePredictions.length,
                  itemBuilder: (context, index) {
                    final prediction = placePredictions[index];

                    return ListTile(
                      leading: const Icon(
                        Icons.location_on,
                        color: Color(0xFF339BFF),
                      ),
                      title: Text(
                        prediction['description'],
                      ),
                      onTap: () async {
                        await selectPlaceFromPrediction(prediction);
                      },
                    );
                  },
                ),
              ),
            ),
          if (isLoadingLocation)
            Container(
              color: Colors.white.withOpacity(0.75),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF339BFF),
                ),
              ),
            ),

          Positioned(
            right: 16,
            bottom: 300,
            child: FloatingActionButton(
              heroTag: 'mapTypeButton',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF339BFF),
              onPressed: () {
                setState(() {
                  if (currentMapType == MapType.normal) {
                    currentMapType = MapType.satellite;
                  } else if (currentMapType == MapType.satellite) {
                    currentMapType = MapType.terrain;
                  } else {
                    currentMapType = MapType.normal;
                  }
                });
              },
              child: const Icon(Icons.layers),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 230,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF339BFF),
              onPressed: () async {
                await loadCurrentLocation();
              },
              child: const Icon(Icons.my_location),
            ),
          ),
          if (!isKeyboardOpen)
            Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFEAF4FF),
                        child: Icon(
                          Icons.location_on,
                          color: Color(0xFF339BFF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Selected Location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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

                  const SizedBox(height: 12),

                  Text(
                    selectedAddress,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Latitude: ${selectedLocation.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Longitude: ${selectedLocation.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF339BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: saveLocation,
                      icon: const Icon(Icons.check),
                      label: const Text(
                        'Use This Location',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}