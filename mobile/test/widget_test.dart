import 'package:flutter_test/flutter_test.dart';
import 'package:teqlif/models/listing_filter_state.dart';

void main() {
  group('ListingFilterState Tests', () {
    test('initial state should be empty with zero activeCount', () {
      const filter = ListingFilterState();
      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, equals(0));
      expect(filter.searchQuery, isNull);
      expect(filter.dateFrom, isNull);
      expect(filter.dateTo, isNull);
    });

    test('copyWith should update fields properly and calculate activeCount', () {
      final now = DateTime(2026, 7, 27);
      final filter = const ListingFilterState().copyWith(
        searchQuery: 'iPhone 15',
        category: 'elektronik',
        dateFrom: now,
        dateTo: now.add(const Duration(days: 7)),
      );

      expect(filter.isEmpty, isFalse);
      expect(filter.activeCount, equals(3)); // searchQuery, category, dateRange
      expect(filter.searchQuery, equals('iPhone 15'));
      expect(filter.category, equals('elektronik'));
      expect(filter.dateFrom, equals(now));
      expect(filter.dateTo, equals(now.add(const Duration(days: 7))));
    });

    test('clearAll should reset all filters', () {
      final filter = const ListingFilterState(
        searchQuery: 'test',
        category: 'cat',
        minPrice: 100,
      ).clearAll();

      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, equals(0));
      expect(filter.searchQuery, isNull);
      expect(filter.category, isNull);
      expect(filter.minPrice, isNull);
    });

    test('clearCategory should only clear category and subcategory', () {
      final filter = const ListingFilterState(
        searchQuery: 'test query',
        category: 'vasita',
        subcategory: 'otomobil',
        minPrice: 50000,
      ).clearCategory();

      expect(filter.category, isNull);
      expect(filter.subcategory, isNull);
      expect(filter.searchQuery, equals('test query'));
      expect(filter.minPrice, equals(50000));
    });

    test('equality and hashCode should work for identical states', () {
      final dateFrom = DateTime.utc(2026, 1, 1);
      final dateTo = DateTime.utc(2026, 1, 31);
      final filter1 = ListingFilterState(
        searchQuery: 'araba',
        category: 'vasita',
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      final filter2 = ListingFilterState(
        searchQuery: 'araba',
        category: 'vasita',
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      expect(filter1, equals(filter2));
      expect(filter1.hashCode, equals(filter2.hashCode));
    });
  });
}
