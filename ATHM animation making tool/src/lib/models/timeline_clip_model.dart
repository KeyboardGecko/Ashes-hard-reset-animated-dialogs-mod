import 'dart:io';
import 'package:flutter/material.dart';

class TimelineClipModel {
  final File imageFile;
  double startMs;
  double durationMs;
  final String id;

  TimelineClipModel({
    required this.imageFile,
    required this.startMs,
    required this.durationMs,
    String? id,
  }) : id = id ?? UniqueKey().toString();

  Map<String, dynamic> toJson() => {
    'image': imageFile.path,
    'startMs': startMs,
    'durationMs': durationMs,
  };

  factory TimelineClipModel.fromJson(Map<String, dynamic> json) =>
      TimelineClipModel(
        imageFile: File(json['image']),
        startMs: json['startMs'],
        durationMs: json['durationMs'],
      );
}
