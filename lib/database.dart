import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
//import 'package:path_provider/path_provider.dart';
import 'dart:async';

const String id = 'id';
const String fileName = 'fileName';
const String filePath = 'filePath';
const String socketAddress = 'socketAddress';
const String date = 'date';
const String status = 'status';

const String _uploadsTable = 'Uploads';

class UploadTabledata {
  late String fileName;
  late String socketAddress;
  late String filePath;
  late String date;
  late int status;
  int? id;
  UploadTabledata(
      {this.id,
      required this.fileName,
      required this.socketAddress,
      required this.filePath,
      required this.status,
      required this.date});
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'socketAddress': socketAddress,
      'filePath': filePath,
      'status': status,
      'date': date
    };
    return map;
  }

  UploadTabledata.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    fileName = map['fileName'];
    socketAddress = map['socketAddress'];
    status = map['status'];
    filePath = map['filePath'];
    date = map['date'];
  }
}

class databaseHelper {
  static Database? _db;
  static const _dbName = 'database.db';
  static const _dbVersion = 1;
  static const _uploadsTable = 'Uploads';

  //making it a singleton class
  databaseHelper._privateConstructor();

  static final databaseHelper instance = databaseHelper._privateConstructor();

  Future<Database?> get database async {
    if (_db != null) return _db;
    _db = await _initiateDatabase();
    return _db;
  }

  Future _onCreate(Database db, int version) async {
    await db.execute("""
            CREATE TABLE $_uploadsTable (
              $id INTEGER PRIMARY KEY,
              $fileName TEXT NOT NULL,
              $filePath TEXT NOT NULL,
              $socketAddress INTEGER NOT NULL,
              $status INTEGER NOT NULL,
              $date TEXT NOT NULL,
            )""");
  }

  Future _initiateDatabase() async {
    Directory path = await Directory('');
    String dbpath = join(path.path, _dbName);
    return await openDatabase(dbpath, version: _dbVersion, onCreate: _onCreate);
  }

  Future<int> insertUpload(Map<String, dynamic> row) async {
    Database? db = await instance.database;
    return await db!.insert(_uploadsTable, row);
  }

  Future<List<Map<String, dynamic>>> queryAllUploads() async {
    Database? db = await instance.database;
    return await db!.query(_uploadsTable);
  }

  Future<List<Map<String, dynamic>>> queryUpload(int uploadId) async {
    Database? db = await instance.database;
    return await db!.query(_uploadsTable,
        columns: ['$fileName', '$socketAddress', '$id'],
        where: "$id=?",
        whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> checkFile(String filepath) async {
    Database? db = await instance.database;
    return await db!.query(_uploadsTable,
        columns: ['$fileName', '$socketAddress', '$id'],
        where: "$filePath=?",
        whereArgs: [filepath]);
  }

  Future deleteUpload(int uploadId) async {
    Database? db = await instance.database;
    return await db!
        .delete(_uploadsTable, where: 'id=?', whereArgs: [uploadId]);
  }
}
