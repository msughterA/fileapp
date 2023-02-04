import 'dart:typed_data';

import 'package:fileapp/api_constants.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:chunked_stream/chunked_stream.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'widgets.dart';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'api.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

class Stack<E> {
  final _list = <E>[];

  void push(E value) => _list.add(value);

  E pop() => _list.removeLast();

  E get peek => _list.last;

  bool get isEmpty => _list.isEmpty;
  bool get isNotEmpty => _list.isNotEmpty;

  @override
  String toString() => _list.toString();
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  if (service is AndroidServiceInstance) {
    // service.on('setAsForeground').listen((event) {
    //   service.setAsForegroundService();
    // });
    String filepath = '';
    bool shouldBreak = false;
    bool isBusy = false;
    final fileQueue = Stack<String>();
    service.on('setAsBackground').listen((event) async {
      service.setAsBackgroundService();
      String fp = event!['filepath'];
      String filename = event['filename'];
      fileQueue.push(fp);
      //fileQueue.
      //int chunkCount = event['chunkCount'];
      // int filesize = event['filesize'];
      print('FILE ADDED TO THE FILE QUEUE');
      if (isBusy == false) {
        isBusy = true;
        while (true) {
          print('INSIDE THE WHILE LOOP');
          if (fileQueue.isEmpty == false) {
            filepath = fileQueue.pop();
            print('PROCESSING THE FILE QUEUE');
            // determine the filesize and chunkCount all here
            final bStream = bufferChunkedStream(File(filepath).openRead(),
                bufferSize: 1024 * 1024);
            int chunkCount = 0;
            int filesize = 0;
            // Create a chunk stream iterator over the buffered stream.
            final itr = ChunkedStreamIterator(bStream);
            while (true) {
              // read the first 1024 bytes
              final lBytes = await itr.read(1024);
              if (lBytes.isEmpty) {
                break;
              }
              filesize = filesize + lBytes.length;
              chunkCount++;
            }
            // call the api with the following parameters
            // userId, filename, filesize, chunkCount all in post data body
            final channel;
            bool isPostError = false;
            var request_body = {
              'type': 'collection',
              'filename': filename,
              'userId': 100,
              'deviceId': 'samsung-a30-123-567'
            };
            var response = await BaseClient()
                .post(
                    ApiConstants.BASE_URL, ApiConstants.ON_CREATE, request_body)
                .catchError((error) {
              // handle the error here
              isPostError = true;
            });
            // it returns socket address, startIndex
            // the startIndex indicates where to start reading the bytes from

            if (isPostError == false) {
              int startIndex = 0;
              int index = 0;
              var socket_url = response['data'];
              channel = WebSocketChannel.connect(
                Uri.parse(socket_url),
              );
              //notficationsListener();
              int percentage = 0;
              int bytesLength = 0;
              // To ensure efficient reading, we buffer the stream upto 4096 bytes, for I/O
              // buffering can improve performance (in some cases).
              final bufferedStream =
                  bufferChunkedStream(File(filepath).openRead());

              // Create a chunk stream iterator over the buffered stream.
              final iterator = ChunkedStreamIterator(bufferedStream);
              String update = '${filepath}_update';
              shouldBreak = false;
              while (true) {
                // Read the first 1024 bytes because the chunkCount was calculated
                //  by bytes/1024, in kilobytes (KB)
                final lengthBytes = await iterator.read(1024);
                // print the bytes
                //print(lengthBytes);
                if (startIndex == index) {
                  if (index >= chunkCount) {
                    // upload the bytes
                    print('UPLOADING LAST BYTES TO SOCKET');
                    try {
                      await channel.sink.add(lengthBytes);
                      //print(lengthBytes);
                      service.invoke(
                        update,
                        {
                          "percentage": percentage,
                          "index": index,
                        },
                      );
                      flutterLocalNotificationsPlugin.show(
                        888,
                        'EnigmaLab',
                        'Upload Complete',
                        const NotificationDetails(
                          android: AndroidNotificationDetails(
                            'my_foreground',
                            'MY FOREGROUND SERVICE',
                            icon: 'ic_bg_service_small',
                            ongoing: true,
                          ),
                        ),
                      );
                    } catch (e) {
                      service.invoke(
                        '${filepath}_update',
                        {
                          "percentage": -1,
                          "index": -1,
                        },
                      );
                      flutterLocalNotificationsPlugin.show(
                        888,
                        'EnigmaLab',
                        'Upload Error',
                        const NotificationDetails(
                          android: AndroidNotificationDetails(
                            'my_foreground',
                            'MY FOREGROUND SERVICE',
                            icon: 'ic_bg_service_small',
                            ongoing: true,
                          ),
                        ),
                      );
                    }
                  } else {
                    // upload the bytes
                    //
                    if (percentage % 1 == 0) {
                      print('UPLOADING BYTES TO SOCKET');
                      //print(lengthBytes);

                      try {
                        await channel.sink.add(lengthBytes);
                        // Delayed function to simulate api call
                        print('CALL HAS BEEN MADE TO THE API');
                        service.invoke(
                          update,
                          {
                            "percentage": percentage,
                            "index": index,
                          },
                        );

                        flutterLocalNotificationsPlugin.show(
                            888,
                            'DemoApp',
                            'Upload in Progress',
                            NotificationDetails(
                              android: AndroidNotificationDetails(
                                'my_foreground',
                                'MY FOREGROUND SERVICE',
                                progress: percentage,
                                icon: 'ic_bg_service_small',
                                enableVibration: false,
                                showProgress: true,
                                onlyAlertOnce: true,
                                maxProgress: 100,
                                channelShowBadge: false,
                              ),
                              iOS: const DarwinNotificationDetails(),
                            ));
                      } catch (e) {
                        service.invoke(
                          '${filepath}_update',
                          {
                            "percentage": -1,
                            "index": -1,
                          },
                        );
                        flutterLocalNotificationsPlugin.show(
                          888,
                          'EnigmaLab',
                          'Upload Error',
                          const NotificationDetails(
                            android: AndroidNotificationDetails(
                              'my_foreground',
                              'MY FOREGROUND SERVICE',
                              icon: 'ic_bg_service_small',
                              ongoing: true,
                            ),
                          ),
                        );
                      }
                    }
                  }

                  if ((lengthBytes.isEmpty) || (shouldBreak == true)) {
                    //isBusy = false;
                    break;
                  }
                  // increment both counters
                  startIndex += 1;
                  index += 1;
                  // method 1 to calculate the progress in percentage
                  bytesLength = bytesLength + lengthBytes.length;
                  double p = ((bytesLength) / filesize) * 100;
                  //percentage = p.toInt();
                  // method 2 to calculate the progress in percentage
                  double pt = ((startIndex / chunkCount) * 100);
                  percentage = pt.toInt();
                  //print('THIS IS THE TEST PERCENTAGE ${testP}');
                  double testP = (startIndex / chunkCount) * 100;
                  // print('THIS IS THE INDEX ${startIndex}');
                  // print('THIS IS THE PERCENTAGE IN DOUBLE ${testP}');
                } else {
                  if (lengthBytes.isEmpty) {
                    break;
                  }
                  // increment the index counter
                  index += 1;
                }
                // We have EOF if there is no more bytes

              }
            } else {
              service.invoke(
                '${filepath}_update',
                {
                  "percentage": -1,
                  "index": -1,
                },
              );
            }
          } else {
            isBusy = false;
            break;
          }
        }
      }
    });

    service.on('cancel').listen((event) {
      String canclePath = event!['filepath'];
      if (filepath != '') {
        if (canclePath == filepath) {
          shouldBreak = true;
          service.invoke(
            '${canclePath}_update',
            {
              "percentage": -1,
              "index": -1,
            },
          );
          flutterLocalNotificationsPlugin.show(
            888,
            'enigmaLab',
            'Upload Cancelled',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'my_foreground',
                'MY FOREGROUND SERVICE',
                icon: 'ic_bg_service_small',
                ongoing: true,
              ),
            ),
          );
        }
      }
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  DartPluginRegistrant.ensureInitialized();
  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);
  return true;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Widget> files = [];
  int chunks = 0;
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<String?> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      return result.files.single.path;
    } else {
      // User canceled the picker
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: files.isEmpty
            ? Container(
                child: const Center(child: Text('Add a file')),
              )
            : SingleChildScrollView(
                child: Container(
                padding: const EdgeInsets.all(5.0),
                child: Column(
                  // horizontal).
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: files,
                ),
              )),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          String? filename = await pickFile();
          if (filename != null) {
            // read the file using a chunked stream
            //int filesize = await getSize(filename);
            List splitedString = filename.split('/');
            String baseName = splitedString[splitedString.length - 1];
            setState(() {
              files.add(FileTile(
                filename: baseName,
                filepath: filename,
                onShowSnackBar: (message) {
                  showInSnackBar(message);
                },
              ));
            });

            print('FILE LOADED');
          } else {
            print('An error occurred while loading the file');
          }
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  // getFileSize(String filepath, int decimals) async {
  //   var file = File(filepath);
  //   int bytes = await file.length();
  //   if (bytes <= 0) return "0 B";
  //   const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  //   var i = (log(bytes) / log(1024)).floor();
  //   // we would like to get the chunk count in integer
  //   var chunkCount = (bytes / 1024).floor().toInt();
  //   setState(() {
  //     chunks = chunkCount;
  //   });
  //   return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) +
  //       ' ' +
  //       suffixes[i];
  // }

  getFileSize(String filepath) async {
    var file = File(filepath);
    int bytes = await file.length();
    //if (bytes <= 0) return 0;
    double result = bytes / 1024;
    int wholeNumber = result.toInt();
    print('THIS IS THE WHOLE NUMBER ${wholeNumber}');
    double decimal = wholeNumber.toDouble() - result;
    print('THIS IS THE DECIMAL PART OF THE NUMBER ${decimal}');
    //getSize(filepath);
    var chunkCount = (bytes / 1000).ceil().toInt();
    print('THE FILESIZE IS ${bytes}');
    print('THE CHUNCK COUNT IS ${chunkCount}');
    setState(() {
      chunks = chunkCount;
    });
    return bytes;
  }

  getSize(String filepath) async {
    final bufferedStream =
        bufferChunkedStream(File(filepath).openRead(), bufferSize: 4096);
    int counter = 0;
    int bytesSize = 0;
    // Create a chunk stream iterator over the buffered stream.
    final iterator = ChunkedStreamIterator(bufferedStream);
    while (true) {
      // read the first 1024 bytes
      final lengthBytes = await iterator.read(1024);
      if (lengthBytes.isEmpty) {
        break;
      }
      bytesSize = bytesSize + lengthBytes.length;
      counter++;
    }
    setState(() {
      chunks = counter;
    });
    print('THE NUMBER OF CHUNKS IS ${counter}');
    return bytesSize;
  }

  void showInSnackBar(String message) {
    // ignore: deprecated_member_use
    //_scaffoldKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
    ScaffoldMessenger.of(_scaffoldKey.currentContext!)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
