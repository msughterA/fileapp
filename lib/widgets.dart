import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:sqflite/sqlite_api.dart';
import 'api.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'database.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:async';

class FileTile extends StatefulWidget {
  final String filename;
  final String filepath;
  final Function onShowSnackBar;
  const FileTile(
      {super.key,
      required this.filename,
      required this.filepath,
      required this.onShowSnackBar});

  @override
  State<FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<FileTile> {
  String filename = '';
  int index = 0;
  int chunk = 0;
  int percentage = 0;
  double bytesUploaded = 0;
  int filesize = 0;
  UploadState uploadState = UploadState.upload;
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Function to handle initiation of upload
  initiateUpload() async {
    // check if the filepath is in the database
    // await checkFile();
    print('UPLOAD INITIATED');
    FlutterBackgroundService().invoke('setAsBackground',
        {'filepath': widget.filepath, 'filename': widget.filename});
    setState(() {
      uploadState = UploadState.uploading;
    });
    // call the api function with the following parametes deviceId, filename ....
    // if api returns file does not exist
    // create database record to track file
    // check database and resume file upload
    // give workmanager the task of the upload loop
  }

  checkFile() async {
    //databaseHelper.instance
    List fileList = await databaseHelper.instance.checkFile(widget.filepath);
    if (fileList.isEmpty) {
      widget.onShowSnackBar('File already exists');
      return false;
    } else {
      return true;
    }
  }

  // cancel file upload
  cancelUpload() {
    print('upload has been canceled');
    FlutterBackgroundService().invoke('cancel', {'filepath': widget.filepath});
  }

  Widget statusIcon() {
    // This returns icons based on the upload state
    switch (uploadState) {
      case UploadState.upload:
        return Upload(
          upload: () {
            initiateUpload();
          },
        );
      case UploadState.uploading:
        return Uploading(
          progress: percentage,
          filepath: widget.filepath,
          onRetry: () {
            initiateUpload();
          },
          onCancel: () {
            cancelUpload();
          },
        );
      case UploadState.uploaded:
        return Uploaded();
      case UploadState.error:
        return Refresh(retry: () {
          initiateUpload();
        });

      default:
        return Container();
    }
  }

  // This widget should handle upload of the file bytes to the socket
  @override
  Widget build(BuildContext context) {
    return Sizer(builder: ((context, orientation, deviceType) {
      return Container(
        width: 100.w,
        height: 90,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.only(right: 26.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // cancel button
                IconButton(
                    onPressed: () {
                      cancelUpload();
                    },
                    icon: const Icon(Icons.cancel_outlined)),
                const SizedBox(
                  width: 2,
                ),
                // filename
                SizedBox(
                  width: 200,
                  child: Text(
                    '${widget.filename}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Put a spacer to push the last widget to the extreme end of the card
                const Spacer(),
                // upload button which can change to show progress , upload error with try again button, upload succes with clear button
                statusIcon()
              ],
            ),
          ),
        ),
      );
    }));
  }
}

class Upload extends StatelessWidget {
  final Function upload;
  const Upload({super.key, required this.upload});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          this.upload();
        },
        child: Container(
          height: 40,
          width: 40,
          child: const Center(
            child: Icon(Icons.upload_file_rounded),
          ),
        ));
  }
}

class Uploading extends StatefulWidget {
  final int progress;
  final Function onCancel;
  final Function onRetry;
  final String filepath;
  const Uploading(
      {super.key,
      required this.progress,
      required this.onCancel,
      required this.onRetry,
      required this.filepath});

  @override
  State<Uploading> createState() => _UploadingState();
}

class _UploadingState extends State<Uploading> {
  bool isCancel = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: (() {
        setState(() {
          isCancel = !isCancel;
        });
      }),
      child: Container(
        height: 68,
        width: 68,
        child: Center(
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: FlutterBackgroundService().on('${widget.filepath}_update'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 34,
                  width: 34,
                  child: CircularProgressIndicator(),
                );
              }

              final data = snapshot.data!;
              int? percentage = data['percentage'];
              int? chunk = data['index'];
              //print(percentage);
              return percentage == -1
                  ? Refresh(retry: () {
                      // This fucntion would be called when the user retries to retry
                      widget.onRetry();
                      setState(() {
                        isCancel = false;
                      });
                    })
                  : CircularPercentIndicator(
                      radius: 34.0,
                      lineWidth: 3.0,
                      percent: 1.0,
                      center: (isCancel == false)
                          ? Text("${percentage}%")
                          : IconButton(
                              onPressed: (() {
                                // call the function to cancel the upload
                                widget.onCancel();
                                // try calling setstate immediately to rebuild the UI
                                setState(() {
                                  percentage = -1;
                                });
                              }),
                              icon: const Icon(
                                Icons.cancel,
                                color: Colors.red,
                              )),
                      progressColor: Colors.green,
                    );
            },
          ),
        ),
      ),
    );
  }
}

class Refresh extends StatelessWidget {
  final Function retry;
  const Refresh({super.key, required this.retry});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration:
          const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
      child: Center(
          child: IconButton(
        icon: const Icon(
          Icons.refresh_outlined,
        ),
        onPressed: (() {
          this.retry();
        }),
      )),
    );
  }
}

class Uploaded extends StatelessWidget {
  const Uploaded({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      width: 20,
      decoration:
          const BoxDecoration(shape: BoxShape.circle, color: Colors.lightGreen),
      child: const Icon(
        Icons.check,
        color: Colors.white,
      ),
    );
  }
}

enum UploadState { upload, uploading, error, uploaded }
