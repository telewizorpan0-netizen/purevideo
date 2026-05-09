import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filmweb/filmweb_info_repository.dart';
import 'package:purevideo/presentation/search/bloc/search_event.dart';
import 'package:purevideo/presentation/search/bloc/search_state.dart';
import 'package:purevideo/di/injection_container.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final Map<SupportedService, AuthRepository> _authRepositories = getIt();
  final FilmwebInfoRepository _filmwebInfoRepository = getIt();

  SearchBloc() : super(const SearchInitial()) {
    on<SearchRequested>(_onSearchRequested);
    on<SearchCleared>(_onSearchCleared);
  }

  Future<void> _onSearchRequested(
    SearchRequested event,
    Emitter<SearchState> emit,
  ) async {
    emit(const SearchLoading());

    try {
      bool hasLoggedInUser = false;
      for (final entry in _authRepositories.entries) {
        final account = entry.value.getAccount();
        if (account != null) {
          hasLoggedInUser = true;
          break;
        }
      }

      if (!hasLoggedInUser) {
        emit(const SearchError('Zaloguj się aby zobaczyć filmy'));
        return;
      }

      final results = await _filmwebInfoRepository.searchMovie(event.query);

      // final merge = getIt<MergeService>();

      // final results = <MovieModel>[];

      // Fetch search results from all logged-in services in parallel instead of sequentially
      // final loggedServiceEntries = _searchRepositories.entries
      //     .where((entry) => _authRepositories[entry.key]?.getAccount() != null)
      //     .toList();

      // if (loggedServiceEntries.isNotEmpty) {
      //   final searchFutures = loggedServiceEntries
      //       .map((entry) => entry.value.searchMovies(event.query))
      //       .toList();

      // Wait for all search calls to complete in parallel, but continue even if one fails
      // final searchResults = await Future.wait(
      //   searchFutures,
      //   eagerError: false,
      // ).then((results) => results
      //     .whereType<List<ServiceMovieModel>>()
      //     .fold<List<ServiceMovieModel>>([], (acc, list) => [...acc, ...list]));

      // Add all fetched results to merge service
      // await merge.addFromServiceTemp(searchResults, results);
      // }

      emit(SearchLoaded(results));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> _onSearchCleared(
    SearchCleared event,
    Emitter<SearchState> emit,
  ) async {
    emit(const SearchInitial());
  }
}
