import 'dart:async';

import 'package:catalog_impl/catalog_impl.dart';
import 'package:feature_catalog/feature_catalog.dart';
import 'package:flutter/material.dart';

import 'local_adapters.dart';

void main() => runApp(const FieldGuideApp());

class FieldGuideApp extends StatefulWidget {
  const FieldGuideApp({super.key});
  @override
  State<FieldGuideApp> createState() => _FieldGuideAppState();
}

class _FieldGuideAppState extends State<FieldGuideApp> {
  late final CatalogRepositoryImpl _repository;
  late final CatalogController _controller;
  @override
  void initState() {
    super.initState();
    final clock = ProcessMonotonicClock();
    _repository = CatalogRepositoryImpl(
      source: BundledCatalogSource(
        fixture: const String.fromEnvironment(
          'FIELD_GUIDE_CATALOG',
          defaultValue: 'catalog-valid',
        ),
        failFirst: const bool.fromEnvironment('FIELD_GUIDE_FAIL_FIRST'),
      ),
      storage: LocalBookmarkStorage(),
      clock: clock,
    );
    _controller = CatalogController(
      repository: _repository,
      queryWalks: QueryWalksImpl(),
      bookmarks: ChangeBookmarkImpl(_repository),
      clock: clock,
    );
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Field Guide',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff285244)),
      scaffoldBackgroundColor: const Color(0xfffff9ee),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff285244),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: CatalogFeature(controller: _controller),
  );
}
