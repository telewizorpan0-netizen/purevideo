import 'package:purevideo/data/models/filmweb_model.dart';

abstract class SearchState {
  const SearchState();

  List<FilmwebPreviewModel> get results => [];
}

class SearchInitial extends SearchState {
  const SearchInitial();
}

class SearchLoading extends SearchState {
  const SearchLoading();
}

class SearchLoaded extends SearchState {
  final List<FilmwebPreviewModel> _results;

  const SearchLoaded(this._results);

  @override
  List<FilmwebPreviewModel> get results => _results;
}

class SearchError extends SearchState {
  final String message;

  const SearchError(this.message);
}
