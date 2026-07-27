class ListingFilterState {
  const ListingFilterState({
    this.category,
    this.subcategory,
    this.city,
    this.condition,
    this.sortBy,
    this.minPrice,
    this.maxPrice,
    this.searchQuery,
    this.dateFrom,
    this.dateTo,
    this.extraFields = const {},
  });

  final String? category;
  final String? subcategory;
  final String? city;
  final String? condition;
  final String? sortBy;
  final double? minPrice;
  final double? maxPrice;
  final String? searchQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Map<String, dynamic> extraFields;

  bool get isEmpty =>
      category == null &&
      subcategory == null &&
      city == null &&
      condition == null &&
      sortBy == null &&
      minPrice == null &&
      maxPrice == null &&
      (searchQuery == null || searchQuery!.isEmpty) &&
      dateFrom == null &&
      dateTo == null &&
      extraFields.isEmpty;

  int get activeCount {
    var n = 0;
    if (category != null) n++;
    if (subcategory != null) n++;
    if (city != null) n++;
    if (condition != null) n++;
    if (sortBy != null) n++;
    if (minPrice != null) n++;
    if (maxPrice != null) n++;
    if (searchQuery != null && searchQuery!.isNotEmpty) n++;
    if (dateFrom != null || dateTo != null) n++;
    n += extraFields.length;
    return n;
  }

  ListingFilterState copyWith({
    Object? category = _sentinel,
    Object? subcategory = _sentinel,
    Object? city = _sentinel,
    Object? condition = _sentinel,
    Object? sortBy = _sentinel,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    Object? searchQuery = _sentinel,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
    Map<String, dynamic>? extraFields,
  }) =>
      ListingFilterState(
        category:    category    == _sentinel ? this.category    : category    as String?,
        subcategory: subcategory == _sentinel ? this.subcategory : subcategory as String?,
        city:        city        == _sentinel ? this.city        : city        as String?,
        condition:   condition   == _sentinel ? this.condition   : condition   as String?,
        sortBy:      sortBy      == _sentinel ? this.sortBy      : sortBy      as String?,
        minPrice:    minPrice    == _sentinel ? this.minPrice    : minPrice    as double?,
        maxPrice:    maxPrice    == _sentinel ? this.maxPrice    : maxPrice    as double?,
        searchQuery: searchQuery == _sentinel ? this.searchQuery : searchQuery as String?,
        dateFrom:    dateFrom    == _sentinel ? this.dateFrom    : dateFrom    as DateTime?,
        dateTo:      dateTo      == _sentinel ? this.dateTo      : dateTo      as DateTime?,
        extraFields: extraFields ?? this.extraFields,
      );

  ListingFilterState clearAll() => const ListingFilterState();

  ListingFilterState clearCategory() => copyWith(
        category: null,
        subcategory: null,
        extraFields: {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingFilterState &&
          other.category == category &&
          other.subcategory == subcategory &&
          other.city == city &&
          other.condition == condition &&
          other.sortBy == sortBy &&
          other.minPrice == minPrice &&
          other.maxPrice == maxPrice &&
          other.searchQuery == searchQuery &&
          other.dateFrom == dateFrom &&
          other.dateTo == dateTo &&
          _mapsEqual(other.extraFields, extraFields);

  @override
  int get hashCode => Object.hash(
        category, subcategory, city, condition, sortBy, minPrice, maxPrice,
        searchQuery, dateFrom, dateTo,
        Object.hashAll(extraFields.entries.map((e) => Object.hash(e.key, e.value))),
      );
}

const _sentinel = Object();

bool _mapsEqual(Map a, Map b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (!b.containsKey(k) || b[k] != a[k]) return false;
  }
  return true;
}
