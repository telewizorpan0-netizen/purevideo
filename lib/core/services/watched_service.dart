import 'dart:async';
import 'package:collection/collection.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';

class WatchedService {
  late final Box<WatchedMovieModel> box;
  final StreamController<List<WatchedMovieModel>> _watchedController =
      StreamController<List<WatchedMovieModel>>.broadcast();
  
  // Cache for O(1) lookups instead of O(n) box.values scans
  final Map<String, WatchedMovieModel> _urlCache = {};
  
  // Track initialization state
  bool _initialized = false;
  List<WatchedMovieModel> _cachedList = [];

  Stream<List<WatchedMovieModel>> get watchedStream =>
      _getInitializedStream();

  /// Returns a stream that emits initial cached data immediately (if initialized)
  /// then continues with future updates from the broadcast stream
  Stream<List<WatchedMovieModel>> _getInitializedStream() {
    if (_initialized) {
      // Create a stream that emits the cached value first, then listens to updates
      return Stream<List<WatchedMovieModel>>.multi((controller) {
        // Emit cached data immediately
        controller.add(_cachedList);
        
        // Then listen to future updates
        final subscription = _watchedController.stream.listen(
          (data) => controller.add(data),
          onError: (error) => controller.addError(error),
          onDone: () => controller.close(),
        );
        
        // Handle cancellation
        controller.onCancel = subscription.cancel;
      });
    }
    // If not initialized yet, just return the controller stream
    return _watchedController.stream;
  }

  Future<void> init() async {
    try {
      box = await Hive.openBox<WatchedMovieModel>('watched');
    } catch (e) {
      await Hive.deleteBoxFromDisk('watched');
      box = await Hive.openBox<WatchedMovieModel>('watched');
    }
    _rebuildCache();
    _cachedList = getAll();  // Cache the list
    _notifyListeners();
    _initialized = true;  // Mark as initialized so stream emits immediately
  }

  void _rebuildCache() {
    _urlCache.clear();
    for (final watched in box.values) {
      for (final service in watched.movie.services) {
        _urlCache[service.url] = watched;
      }
    }
  }

  void _removeFromCache(MovieDetailsModel movie) {
    // Remove movie from cache incrementally instead of rebuilding entire cache
    for (final service in movie.services) {
      _urlCache.remove(service.url);
    }
  }

  void _addToCache(WatchedMovieModel watched) {
    // Add movie to cache incrementally
    for (final service in watched.movie.services) {
      _urlCache[service.url] = watched;
    }
  }

  void _notifyListeners() {
    _cachedList = getAll();  // Update cache
    _watchedController.add(_cachedList);
  }

  void dispose() {
    _watchedController.close();
  }

  List<WatchedMovieModel> getAll() {
    return box.values.toList();
  }

  WatchedMovieModel? getByMovie(MovieDetailsModel movie) {
    // Try to find in cache first (O(1))
    final movieServiceUrls =
        movie.services.map((service) => service.url).toSet();
    
    for (final url in movieServiceUrls) {
      if (_urlCache.containsKey(url)) {
        return _urlCache[url];
      }
    }
    
    // Fallback to old method if cache miss
    return box.values.firstWhereOrNull((boxElement) {
      final boxServiceUrls =
          boxElement.movie.services.map((service) => service.url).toSet();
      return movieServiceUrls.intersection(boxServiceUrls).isNotEmpty;
    });
  }

  dynamic getKeyByMovie(MovieDetailsModel movie) {
    // Use cache for faster lookup
    final cached = getByMovie(movie);
    if (cached != null) {
      return box.toMap().entries
          .firstWhereOrNull((entry) => entry.value == cached)
          ?.key;
    }
    return null;
  }

  WatchedEpisodeModel? getByEpisode(
      MovieDetailsModel movie, EpisodeModel episode) {
    final watchedMovie = getByMovie(movie);
    return watchedMovie?.getEpisodeByUrl(episode.url);
  }

  void watchMovie(MovieDetailsModel movie, int watchedTime) {
    final existingKey = getKeyByMovie(movie);
    if (existingKey != null) {
      // Remove old entry from cache before deleting
      final oldMovie = box.get(existingKey);
      if (oldMovie != null) {
        _removeFromCache(oldMovie.movie);
      }
      box.delete(existingKey);
    }
    final watchedMovie = WatchedMovieModel(
      movie: movie,
      watchedTime: watchedTime,
      watchedAt: DateTime.now(),
    );
    box.add(watchedMovie);
    // Update cache incrementally
    _addToCache(watchedMovie);
    _notifyListeners();
  }

  void watchEpisode(
    MovieDetailsModel movie,
    SeasonModel season,
    EpisodeModel episode,
    int watchedTime,
  ) {
    var watchedMovie = getByMovie(movie)?.copyWith(
          watchedAt: DateTime.now(),
        ) ??
        WatchedMovieModel(
          movie: movie,
          watchedTime: 0,
          watchedAt: DateTime.now(),
          episodes: [],
        );

    final watchedEpisode = WatchedEpisodeModel(
      episode: episode,
      watchedTime: watchedTime,
      watchedAt: DateTime.now(),
    );

    watchedMovie.episodes!.add(
        WatchedSeasonEpisode(season: season, watchedEpisode: watchedEpisode));

    final existingKey = getKeyByMovie(movie);
    if (existingKey != null) {
      // Remove old entry from cache before deleting
      final oldMovie = box.get(existingKey);
      if (oldMovie != null) {
        _removeFromCache(oldMovie.movie);
      }
      box.delete(existingKey);
    }
    box.add(watchedMovie);
    // Update cache incrementally
    _addToCache(watchedMovie);
    _notifyListeners();
  }
}
