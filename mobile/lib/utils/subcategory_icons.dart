import 'package:flutter/material.dart';

IconData getSubcategoryIcon(String subcatKey) {
  switch (subcatKey) {
    // Vehicles
    case 'automobile':
    case 'electric_vehicle':
      return Icons.directions_car;
    case 'motorcycle':
      return Icons.two_wheeler;
    case 'van_minibus':
    case 'truck':
      return Icons.local_shipping;
    case 'tractor':
      return Icons.agriculture;
    case 'boat':
      return Icons.directions_boat;
    case 'caravan':
      return Icons.rv_hookup;
    case 'spare_parts':
      return Icons.build;
      
    // Electronics
    case 'mobile_phone':
      return Icons.smartphone;
    case 'laptop':
      return Icons.computer;
    case 'tablet':
      return Icons.tablet_mac;
    case 'tv_monitor':
      return Icons.tv;
    case 'camera':
    case 'photo_video':
      return Icons.camera_alt;
    case 'audio_system':
      return Icons.speaker;
    case 'smartwatch':
      return Icons.watch;
    case 'gaming_console':
      return Icons.videogame_asset;
    case 'other_electronics':
      return Icons.devices_other;

    // Real Estate
    case 'apartment':
    case 'house_villa':
    case 'building':
      return Icons.home;
    case 'land':
    case 'field_garden':
      return Icons.landscape;
    case 'office':
      return Icons.storefront;
    case 'warehouse':
      return Icons.warehouse;

    // Fashion
    case 'womens_clothing':
    case 'mens_clothing':
    case 'kids_clothing':
      return Icons.checkroom;
    case 'shoes':
      return Icons.do_not_step;
    case 'bag':
      return Icons.shopping_bag;
    case 'jewelry':
      return Icons.diamond;
    case 'watch':
      return Icons.watch;
    case 'accessories':
      return Icons.style;

    // Home
    case 'furniture':
      return Icons.chair;
    case 'kitchen_equipment':
      return Icons.kitchen;
    case 'cleaning_equipment':
      return Icons.cleaning_services;
    case 'home_textile':
      return Icons.bed;
    case 'lighting':
      return Icons.lightbulb;
    case 'garden_outdoor':
      return Icons.deck;

    // Sports & Hobbies
    case 'antique':
      return Icons.history_edu;
    case 'bicycle':
      return Icons.pedal_bike;
    case 'fitness_equipment':
      return Icons.fitness_center;
    case 'outdoor_camping':
      return Icons.terrain;
    case 'team_sports':
      return Icons.sports_soccer;
    case 'outdoor_sports':
      return Icons.directions_run;
    case 'other_sports':
      return Icons.sports;

    // Books & Others
    case 'fiction':
    case 'sci_fi':
    case 'self_development':
    case 'kids_books':
    case 'school_books':
    case 'arts_books':
      return Icons.menu_book;
    case 'magazine':
      return Icons.auto_stories;

    // Miscellaneous
    case 'pet':
      return Icons.pets;
    case 'baby_toys':
      return Icons.smart_toy;
    case 'musical_instrument':
      return Icons.music_note;
    case 'food_agriculture':
      return Icons.restaurant;
    case 'misc':
      return Icons.category;
      
    default:
      return Icons.category_outlined;
  }
}
