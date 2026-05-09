import 'package:flutter/rendering.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:hive/hive.dart';
import 'package:purevideo/core/services/resolve_url_service.dart';
import 'package:purevideo/data/models/movie_model.dart';

@HiveType(typeId: 3)
class VideoSource {
  @HiveField(0)
  final String url;
  @HiveField(1)
  final String lang;
  @HiveField(2)
  final String quality;
  @HiveField(3)
  final String host;
  @HiveField(4)
  final Map<String, String>? headers;

  const VideoSource({
    required this.url,
    required this.lang,
    required this.quality,
    required this.host,
    this.headers,
  });

  @override
  String toString() {
    return 'VideoSource(url: $url, lang: $lang, quality: $quality, host: $host, headers: $headers)';
  }
}

class VideoSourceRepository {
  late final ResolveUrlService _resolveService;

  VideoSourceRepository() {
    _initialize();
  }

  void _initialize() {
    _resolveService = getIt<ResolveUrlService>();
  }

  Future<MovieDetailsModel> scrapeVideoUrls(MovieDetailsModel movie) async {
    if (movie.videoUrls == null) return movie;

    final results = await _resolveService.resolve(movie.videoUrls ?? []);

    debugPrint('Resolved video sources: $results');

    return movie.copyWith(directUrls: results);
  }
}
