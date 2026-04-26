import 'package:flutter/material.dart';

enum ListingStatus { moderation, approved, rejected }

@immutable
class MyListing {
  const MyListing({
    required this.id,
    required this.title,
    required this.address,
    required this.areaSqm,
    required this.priceUzs,
    required this.status,
    required this.views,
    required this.at,
    required this.accent,
  });

  final String id;
  final String title;
  final String address;
  final double areaSqm;
  final int priceUzs;
  final ListingStatus status;
  final int views;
  final DateTime at;

  /// Tint color used as the placeholder thumbnail background.
  final Color accent;
}

final List<MyListing> mockListings = [
  MyListing(
    id: 'l1',
    title: 'Yunusobod 2-xonadon',
    address: 'Toshkent, Yunusobod tumani, 14-mavze',
    areaSqm: 64.5,
    priceUzs: 820000000,
    status: ListingStatus.approved,
    views: 248,
    at: DateTime.now().subtract(const Duration(days: 2)),
    accent: const Color(0xFF10B981),
  ),
  MyListing(
    id: 'l2',
    title: 'Sergeli 1-xonadon',
    address: 'Toshkent, Sergeli tumani, Quruvchilar k.',
    areaSqm: 48.0,
    priceUzs: 460000000,
    status: ListingStatus.moderation,
    views: 0,
    at: DateTime.now().subtract(const Duration(days: 1)),
    accent: const Color(0xFFF59E0B),
  ),
  MyListing(
    id: 'l3',
    title: 'Samarqand ofis',
    address: 'Samarqand sh., Registon ko‘chasi',
    areaSqm: 92.0,
    priceUzs: 1100000000,
    status: ListingStatus.approved,
    views: 612,
    at: DateTime.now().subtract(const Duration(days: 14)),
    accent: const Color(0xFF3B82F6),
  ),
  MyListing(
    id: 'l4',
    title: 'Buxoro ombor',
    address: 'Buxoro sh., Bahouddin Naqshband ko‘chasi',
    areaSqm: 540.0,
    priceUzs: 2680000000,
    status: ListingStatus.rejected,
    views: 0,
    at: DateTime.now().subtract(const Duration(days: 21)),
    accent: const Color(0xFFEF4444),
  ),
];
