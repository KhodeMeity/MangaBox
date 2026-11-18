import 'dart:convert';
import 'package:crypto/crypto.dart';

class ComicEntry {
  ComicEntry({
    required this.id, required this.uri, required this.title,
    this.pageCount = 0, this.lastPage = 0, this.lastRead = 0,
    this.addedAt = 0, this.coverPath,
  });
  final String id, uri, title;
  final int pageCount, lastPage, lastRead, addedAt;
  final String? coverPath;

  double get progress => pageCount <= 1 ? 0 : (lastPage + 1) / pageCount;

  static String idFor(String uri) => sha1.convert(utf8.encode(uri)).toString();

  ComicEntry copyWith({int? pageCount, int? lastPage, int? lastRead, String? coverPath}) => ComicEntry(
        id: id, uri: uri, title: title, addedAt: addedAt,
        pageCount: pageCount ?? this.pageCount,
        lastPage: lastPage ?? this.lastPage,
        lastRead: lastRead ?? this.lastRead,
        coverPath: coverPath ?? this.coverPath,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'uri': uri, 'title': title, 'pageCount': pageCount,
        'lastPage': lastPage, 'lastRead': lastRead, 'addedAt': addedAt, 'coverPath': coverPath,
      };

  factory ComicEntry.fromMap(Map m) => ComicEntry(
        id: m['id'], uri: m['uri'], title: m['title'],
        pageCount: m['pageCount'] ?? 0, lastPage: m['lastPage'] ?? 0,
        lastRead: m['lastRead'] ?? 0, addedAt: m['addedAt'] ?? 0, coverPath: m['coverPath'],
      );
}
