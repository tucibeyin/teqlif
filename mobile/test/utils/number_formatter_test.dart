import 'package:flutter_test/flutter_test.dart';
import 'package:teqlif/utils/number_formatter.dart';

void main() {
  group('TeqNumberFormatter - Format Tests', () {
    test('Formats integers with thousands separators (TR locale)', () {
      expect(TeqNumberFormatter.format(1500000, locale: 'tr_TR'), '1.500.000');
      expect(TeqNumberFormatter.format(150000, locale: 'tr_TR', unit: 'km'), '150.000 km');
      expect(TeqNumberFormatter.format(25000, locale: 'tr_TR', unit: 'm²'), '25.000 m²');
    });

    test('Formats integers with thousands separators (EN locale)', () {
      expect(TeqNumberFormatter.format(1500000, locale: 'en_US'), '1,500,000');
      expect(TeqNumberFormatter.format(150000, locale: 'en_US', unit: 'km'), '150,000 km');
    });

    test('Formats decimals correctly for boat length (Group D)', () {
      expect(TeqNumberFormatter.format(12.5, locale: 'tr_TR', unit: 'm'), '12,5 m');
      expect(TeqNumberFormatter.format(12.5, locale: 'en_US', unit: 'm'), '12.5 m');
    });

    test('Does NOT format blacklisted keys (Year, Floor, Age, ID)', () {
      expect(TeqNumberFormatter.format(2023, fieldKey: 'year', locale: 'tr_TR'), '2023');
      expect(TeqNumberFormatter.format(5, fieldKey: 'floor', locale: 'tr_TR'), '5');
      expect(TeqNumberFormatter.format(15, fieldKey: 'building_age', locale: 'tr_TR'), '15');
      expect(TeqNumberFormatter.format(12345, fieldKey: 'id', locale: 'tr_TR'), '12345');
      expect(TeqNumberFormatter.format(998877, fieldKey: 'listing_id', locale: 'tr_TR'), '998877');
    });

    test('Handles non-numeric string values without errors', () {
      expect(TeqNumberFormatter.format('Benzin', fieldKey: 'fuel_type'), 'Benzin');
      expect(TeqNumberFormatter.format('Otomatik', fieldKey: 'transmission'), 'Otomatik');
      expect(TeqNumberFormatter.format('3+1', fieldKey: 'room_count'), '3+1');
    });
  });

  group('TeqNumberFormatter - Parse Tests', () {
    test('Parses formatted strings to clean numbers', () {
      expect(TeqNumberFormatter.parse('1.500.000'), 1500000);
      expect(TeqNumberFormatter.parse('1,500,000'), 1500000);
      expect(TeqNumberFormatter.parse('150.000'), 150000);
      expect(TeqNumberFormatter.parse('12,5'), 12.5);
      expect(TeqNumberFormatter.parse('12.5'), 12.5);
      expect(TeqNumberFormatter.parse(500000), 500000);
    });
  });

  group('TeqNumberFormatter - Blacklist check', () {
    test('Identifies unformatted keys correctly', () {
      expect(TeqNumberFormatter.isUnformattedKey('year'), isTrue);
      expect(TeqNumberFormatter.isUnformattedKey('model_year'), isTrue);
      expect(TeqNumberFormatter.isUnformattedKey('floor'), isTrue);
      expect(TeqNumberFormatter.isUnformattedKey('floor_count'), isTrue);
      expect(TeqNumberFormatter.isUnformattedKey('building_age'), isTrue);
      expect(TeqNumberFormatter.isUnformattedKey('user_id'), isTrue);

      expect(TeqNumberFormatter.isUnformattedKey('mileage'), isFalse);
      expect(TeqNumberFormatter.isUnformattedKey('price'), isFalse);
      expect(TeqNumberFormatter.isUnformattedKey('gross_sqm'), isFalse);
      expect(TeqNumberFormatter.isUnformattedKey('engine_cc'), isFalse);
      expect(TeqNumberFormatter.isUnformattedKey('working_hours'), isFalse);
    });
  });
}
