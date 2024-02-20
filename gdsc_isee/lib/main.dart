import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String defaultLang =
      prefs.getString('defaultLang') ?? Platform.localeName.split('_')[0];
  runApp(MyApp(cameras: cameras, defaultLang: defaultLang));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final String defaultLang;

  const MyApp({Key? key, required this.cameras, required this.defaultLang})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initLocalization(), // Initialize localization
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else {
          return MaterialApp(
            title: 'Take Photo App',
            theme: ThemeData(
              primarySwatch: Colors.blue,
            ),
            debugShowCheckedModeBanner: false,
            locale: Locale(defaultLang),
            supportedLocales: [
              Locale('en'),
              Locale('ru'),
              Locale('uz'),
            ],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: TakePhotoScreen(cameras: cameras),
          );
        }
      },
    );
  }

  Future<void> _initLocalization() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}

class TakePhotoScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const TakePhotoScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _TakePhotoScreenState createState() => _TakePhotoScreenState();
}

class _TakePhotoScreenState extends State<TakePhotoScreen> {
  late CameraController _cameraController;
  File? _imageFile;
  final FlutterTts flutterTts = FlutterTts();
  final ImagePicker _picker = ImagePicker();
  bool _isCameraReady = false;
  bool _isSendingImage = false;
  String _selectedLanguage = 'en'; // Default selected language is English

  @override
  void initState() {
    super.initState();
    _initCamera();
    _setDefaultLanguage();
  }

  Future<void> _setDefaultLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage =
          prefs.getString('defaultLang') ?? Platform.localeName.split('_')[0];
    });
  }

  Future<void> _initCamera() async {
    _cameraController = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
    );
    await _cameraController.initialize();
    setState(() {
      _isCameraReady = true;
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      setState(() {
        _isSendingImage = true; // Start sending image
      });
      final XFile image = await _cameraController.takePicture();
      setState(() {
        _isSendingImage = false; // Finished sending image
        if (image != null) {
          _imageFile = File(image.path);
        }
      });

      // Send the image to the API if it's not null
      if (_imageFile != null) {
        await _sendImageToAPI(_imageFile!, _selectedLanguage);
      }

      // Navigate to the new page to display the taken image
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayImageScreen(imageFile: _imageFile!),
        ),
      );
    } catch (e) {
      print('Error taking photo: $e');
      setState(() {
        _isSendingImage = false; // Error occurred while sending image
      });
    }
  }

  Future<void> _sendImageToAPI(File imageFile, String lang) async {
    try {
      var uri = Uri.parse(
          'http://44.204.66.45/generate_image_description/?lang=$lang');
      var request = http.MultipartRequest('POST', uri);

      // Attach the image file to the request
      var fileStream = http.ByteStream(imageFile.openRead());
      var length = await imageFile.length();
      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        length,
        filename: imageFile.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Send the request
      var response = await request.send();

      // Handle response
      if (response.statusCode == 200) {
        // Successful API call
        final description = await response.stream.bytesToString();
        print('Image successfully sent to API.');
        print('API Response: $description');

        // Speak the description
        await _speakDescription(description, lang);
      } else {
        // Error in API call
        print(
            'Failed to send image to API. Status code: ${response.statusCode}');
        final errorResponse = await response.stream.bytesToString();
        print('Error response: $errorResponse');
      }
    } catch (e) {
      // Catch any exceptions
      print('Error: $e');
    }
  }

  Future<void> _speakDescription(String description, String lang) async {
    try {
      // Set language for TTS
      await flutterTts.setLanguage(lang);

      // Speak the description
      await flutterTts.speak(description);
      // Convert text to audio in Uzbek language
      if (lang == 'uz') {
        await _convertTextToAudio(description);
      }
    } catch (e) {
      print('Error in TTS: $e');
    }
  }

  Future<void> _convertTextToAudio(String text) async {
    try {
      var url = "https://mohir.ai/api/v1/tts";
      var headers = {
        "Authorization":
            "6bdcaf97-b043-42da-a989-895154595a4c:437ccdbd-4cc6-4cf9-b4e6-0fc7274e30e3",
        "Content-Type": "application/json",
      };

      var data = {
        "text": text,
        "model": "davron",
        "mood": "neutral",
        "blocking": "true",
        "webhook_notification_url": "",
      };

      var response = await http.post(Uri.parse(url),
          headers: headers, body: json.encode(data));

      if (response.statusCode == 200) {
        print('Text converted to audio successfully.');
        // Play the audio (implement your audio player logic)
      } else {
        print(
            'Failed to convert text to audio. Status code: ${response.statusCode}');
        print('Error response: ${response.body}');
      }
    } catch (e) {
      print('Error converting text to audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final navigationBarHeight = screenHeight * 0.30; // 30% of screen height
    final bodyHeight = screenHeight * 0.70; // 70% of screen height

    // Define language labels for accessibility
    final Map<String, String> languageAccessibilityLabels = {
      'en': 'English',
      'ru': 'Русский',
      'uz': 'Oʻzbekcha',
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        bottomOpacity: 0,
        elevation: 0,
        actions: [
          _buildLanguageAction(languageAccessibilityLabels['en']!, 'en'),
          SizedBox(width: 20),
          _buildLanguageAction(languageAccessibilityLabels['ru']!, 'ru'),
          SizedBox(width: 20),
          _buildLanguageAction(languageAccessibilityLabels['uz']!, 'uz'),
          SizedBox(width: 20),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              height: bodyHeight,
              child: Center(
                child: _isCameraReady
                    ? CameraPreview(_cameraController)
                    : CircularProgressIndicator(),
              ),
            ),
          ),
          Container(
            height: navigationBarHeight,
            color: Colors.blueGrey,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  color: Colors.blue,
                  width: MediaQuery.of(context).size.width / 2,
                  height: double.infinity,
                  child: IconButton(
                    onPressed: () {
                      print('Call button pressed');
                    },
                    icon: Icon(Icons.phone, size: 50),
                    color: Colors.white,
                    tooltip: _selectedLanguage == 'ru'
                        ? 'Звонить'
                        : (_selectedLanguage == 'uz' ? 'Qoʻngʻiroq' : 'Call'),
                  ),
                ),
                Container(
                  color: _isCameraReady && !_isSendingImage
                      ? Colors.red
                      : Colors.grey,
                  width: MediaQuery.of(context).size.width / 2,
                  height: double.infinity,
                  child: IconButton(
                    onPressed:
                        _isCameraReady && !_isSendingImage ? _takePhoto : null,
                    icon: Icon(Icons.camera, size: 50),
                    color: Colors.white,
                    tooltip: _selectedLanguage == 'ru'
                        ? 'Снять фото'
                        : (_selectedLanguage == 'uz'
                            ? 'Rasm olmoq'
                            : 'Take a photo'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageAction(String label, String langCode) {
    return InkWell(
      onTap: () async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('defaultLang', langCode);
        setState(() {
          _selectedLanguage = langCode;
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Semantics(
          label: label, // Accessibility label
          child: Text(
            langCode.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 30,
              color:
                  _selectedLanguage == langCode ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class DisplayImageScreen extends StatelessWidget {
  final File imageFile;

  const DisplayImageScreen({Key? key, required this.imageFile})
      : super(key: key);

  // Method to stop speaking
  Future<void> _stopSpeaking() async {
    final FlutterTts flutterTts = FlutterTts();
    await flutterTts.stop();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = screenHeight * 0.05; // 10% of screen height
    final imageHeight = screenHeight * 0.50; // 50% of screen height
    final chatHeight = screenHeight * 0.45;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: AppBar(
          title: Text('Taken Image'),
          leading: IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () {
              _stopSpeaking(); // Stop speaking when exit icon is pressed
              Navigator.pop(context); // Navigate back when exit icon is pressed
            },
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: screenWidth, // Set width to screen width
            height: imageHeight,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: FileImage(imageFile),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(
            width: screenWidth, // Set width to screen width
            height: screenHeight * .40,
            color: Colors.red, // Set background color here
          ),
        ],
      ),
    );
  }
}
