import '../l10n/app_localizations.dart';

/// Returns the localized display label for a subcategory key.
/// Falls back to [fallback] if provided, otherwise the key itself.
String subcatLabel(String key, AppLocalizations l, {String? fallback}) =>
    switch (key) {
      // Vehicles
      'automobile' => l.subcat_automobile,
      'motorcycle' => l.subcat_motorcycle,
      'electric_vehicle' => l.subcat_electric_vehicle,
      'van_minibus' => l.subcat_van_minibus,
      'truck' => l.subcat_truck,
      'tractor' => l.subcat_tractor,
      'boat' => l.subcat_boat,
      'caravan' => l.subcat_caravan,
      'spare_parts' => l.subcat_spare_parts,
      // Electronics
      'mobile_phone' => l.subcat_mobile_phone,
      'laptop' => l.subcat_laptop,
      'tablet' => l.subcat_tablet,
      'tv_monitor' => l.subcat_tv_monitor,
      'camera' => l.subcat_camera,
      'audio_system' => l.subcat_audio_system,
      'smartwatch' => l.subcat_smartwatch,
      'gaming_console' => l.subcat_gaming_console,
      'other_electronics' => l.subcat_other_electronics,
      // Real estate
      'apartment' => l.subcat_apartment,
      'house_villa' => l.subcat_house_villa,
      'land' => l.subcat_land,
      'field_garden' => l.subcat_field_garden,
      'office' => l.subcat_office,
      'warehouse' => l.subcat_warehouse,
      'building' => l.subcat_building,
      // Fashion
      'womens_clothing' => l.subcat_womens_clothing,
      'mens_clothing' => l.subcat_mens_clothing,
      'kids_clothing' => l.subcat_kids_clothing,
      'shoes' => l.subcat_shoes,
      'bag' => l.subcat_bag,
      'jewelry' => l.subcat_jewelry,
      'watch' => l.subcat_watch,
      'accessories' => l.subcat_accessories,
      // Home
      'furniture' => l.subcat_furniture,
      'kitchen_equipment' => l.subcat_kitchen_equipment,
      'cleaning_equipment' => l.subcat_cleaning_equipment,
      'home_textile' => l.subcat_home_textile,
      'lighting' => l.subcat_lighting,
      'garden_outdoor' => l.subcat_garden_outdoor,
      'antique' => l.subcat_antique,
      // Sports
      'bicycle' => l.subcat_bicycle,
      'fitness_equipment' => l.subcat_fitness_equipment,
      'outdoor_camping' => l.subcat_outdoor_camping,
      'team_sports' => l.subcat_team_sports,
      'outdoor_sports' => l.subcat_outdoor_sports,
      'other_sports' => l.subcat_other_sports,
      // Books
      'fiction' => l.subcat_fiction,
      'sci_fi' => l.subcat_sci_fi,
      'self_development' => l.subcat_self_development,
      'kids_books' => l.subcat_kids_books,
      'school_books' => l.subcat_school_books,
      'arts_books' => l.subcat_arts_books,
      'magazine' => l.subcat_magazine,
      // Other
      'pet' => l.subcat_pet,
      'baby_toys' => l.subcat_baby_toys,
      'musical_instrument' => l.subcat_musical_instrument,
      'photo_video' => l.subcat_photo_video,
      'food_agriculture' => l.subcat_food_agriculture,
      'misc' => l.subcat_misc,
      _ => fallback ?? key,
    };

