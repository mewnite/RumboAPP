import '../domain/search_models.dart';

enum SearchStatus { initial, loading, success, empty, error, offline }

class SearchState {
  const SearchState({
    this.query = '',
    this.status = SearchStatus.initial,
    this.results = const [],
    this.isLocalOnly = false,
    this.errorMessage,
  });

  final String query;
  final SearchStatus status;
  final List<SearchResult> results;
  final bool isLocalOnly;
  final String? errorMessage;

  SearchState copyWith({
    String? query,
    SearchStatus? status,
    List<SearchResult>? results,
    bool? isLocalOnly,
    String? errorMessage,
  }) {
    return SearchState(
      query: query ?? this.query,
      status: status ?? this.status,
      results: results ?? this.results,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
