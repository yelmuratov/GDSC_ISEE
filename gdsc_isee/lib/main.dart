import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:share/share.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:audioplayers/audioplayers.dart';

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
          builder: (context) => DisplayImageScreen(imageFile: _imageFile!, description: '',),
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

class DisplayImageScreen extends StatefulWidget {
  final File imageFile;
  final String description;

  const DisplayImageScreen({Key? key, required this.imageFile, required this.description})
      : super(key: key);

  @override
  _DisplayImageScreenState createState() => _DisplayImageScreenState();
}

class _DisplayImageScreenState extends State<DisplayImageScreen> {
  final TextEditingController _textEditingController = TextEditingController();
  final List<Message> messages = [];
  bool _isTyping = false;
  final AudioPlayer audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    messages.add(Message(text: widget.description, isOutgoing: false));
    _textEditingController.addListener(() {
      setState(() {
        _isTyping = _textEditingController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Message copied to clipboard'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D1739), // Set the background color to blue
      appBar: AppBar(
        title: Text('Display and Share Image'),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            onPressed: () => Share.shareFiles([widget.imageFile.path], text: 'Check out this image!'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              widget.imageFile,
              width: MediaQuery.of(context).size.width,
              fit: BoxFit.cover,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Align(
                  alignment: message.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                          margin: EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                          decoration: BoxDecoration(
                            color: message.isOutgoing ? Colors.lightBlueAccent : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ),
                      if (!message.isOutgoing) // Copy icon for incoming messages
                        IconButton(
                          icon: Icon(Icons.copy, color: Colors.white),
                          onPressed: () => _copyToClipboard(message.text),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(bottom: 8, left: 8, right: 8),
            color: Color(0xFF1C2031), // Bottom container color
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.camera_alt, color: Colors.white),
                  onPressed: () {
                    // Placeholder for take picture functionality
                  },
                ),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Color(0xFF262A34), // Input field color
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextField(
                      controller: _textEditingController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type your message here...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_isTyping ? Icons.send : Icons.keyboard_voice, color: Colors.white),
                  onPressed: _isTyping ? () {
                    setState(() {
                      messages.add(Message(text: _textEditingController.text, isOutgoing: true));
                      _textEditingController.clear();
                    });
                  } : () {
                    // Placeholder for voice message functionality
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Message {
  String text;
  bool isOutgoing;
  Message({required this.text, required this.isOutgoing});
}


