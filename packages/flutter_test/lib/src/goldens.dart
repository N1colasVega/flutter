// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:test/test.dart' show TestFailure;

/// Compares rasterized image bytes against a golden image file.
///
/// Instances of this comparator will be used as the backend for
/// [matchesGoldenFile].
///
/// Instances of this comparator will be invoked by the test framework in the
/// [TestWidgetsFlutterBinding.runAsync] zone and are thus not subject to the
/// fake async constraints that are normally imposed on widget tests (i.e. the
/// need or the ability to call [WidgetTester.pump] to advance the microtask
/// queue).
abstract class GoldenFileComparator {
  /// Compares [imageBytes] against the golden file identified by [golden].
  ///
  /// The returned future completes with a boolean value that indicates whether
  /// [imageBytes] matches the golden file's bytes within the tolerance defined
  /// by the comparator.
  ///
  /// In the case of comparison mismatch, the comparator may choose to throw a
  /// [TestFailure] if it wants to control the failure message.
  ///
  /// The method by which [golden] is located and by which its bytes are loaded
  /// is left up to the implementation class. For instance, some implementations
  /// may load files from the local file system, whereas others may load files
  /// over the network or from a remote repository.
  Future<bool> compare(Uint8List imageBytes, Uri golden);

  /// Updates the golden file identified by [golden] with [imageBytes].
  ///
  /// This will be invoked in lieu of [compare] when [autoUpdateGoldenFiles]
  /// is `true` (which gets set automatically by the test framework when the
  /// user runs `flutter test --update-goldens`).
  ///
  /// The method by which [golden] is located and by which its bytes are written
  /// is left up to the implementation class.
  Future<void> update(Uri golden, Uint8List imageBytes);
}

/// Compares rasterized image bytes against a golden image file.
///
/// This comparator is used as the backend for [matchesGoldenFile].
///
/// The default comparator, [LocalFileComparator], will treat the golden key as
/// a relative path from the test file's directory. It will then load the
/// golden file's bytes from disk and perform a byte-for-byte comparison of the
/// encoded PNGs, returning true only if there's an exact match.
///
/// Callers may choose to override the default comparator by setting this to a
/// custom comparator during test set-up. For example, some projects may wish to
/// install a more intelligent comparator that knows how to decode the PNG
/// images to raw pixels and compare pixel vales, reporting specific differences
/// between the images.
GoldenFileComparator goldenFileComparator = const _UninitializedComparator();

/// Whether golden files should be automatically updated during tests rather
/// than compared to the image bytes recorded by the tests.
///
/// When this is `true`, [matchesGoldenFile] will always report a successful
/// match, because the bytes being tested implicitly become the new golden.
///
/// The Flutter tool will automatically set this to `true` when the user runs
/// `flutter test --update-goldens`, so callers should generally never have to
/// explicitly modify this value.
///
/// See also:
///
///   * [goldenFileComparator]
bool autoUpdateGoldenFiles = false;

/// Placeholder to signal an unexpected error in the testing framework itself.
///
/// The test harness file that gets generated by the Flutter tool when the
/// user runs `flutter test` is expected to set [goldenFileComparator] to
/// a valid comparator. From there, the caller may choose to override it by
/// setting the comparator during test initialization (e.g. in `setUpAll()`).
/// But under no circumstances do we expect it to remain uninitialized.
class _UninitializedComparator implements GoldenFileComparator {
  const _UninitializedComparator();

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) {
    throw new StateError('goldenFileComparator has not been initialized');
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) {
    throw new StateError('goldenFileComparator has not been initialized');
  }
}

/// The default [GoldenFileComparator] implementation.
///
/// This comparator loads golden files from the local file system, treating the
/// golden key as a relative path from the test file's directory.
///
/// This comparator performs a very simplistic comparison, doing a byte-for-byte
/// comparison of the encoded PNGs, returning true only if there's an exact
/// match. This means it will fail the test if two PNGs represent the same
/// pixels but are encoded differently.
class LocalFileComparator implements GoldenFileComparator {
  /// Creates a new [LocalFileComparator] for the specified [testFile].
  ///
  /// Golden file keys will be interpreted as file paths relative to the
  /// directory in which [testFile] resides.
  ///
  /// The [testFile] URI must represent a file.
  LocalFileComparator(Uri testFile)
      : assert(testFile.scheme == 'file'),
        basedir = new Uri.directory(_path.dirname(_path.fromUri(testFile)));

  // Due to https://github.com/flutter/flutter/issues/17118, we need to
  // explicitly set the path style.
  static final path.Context _path = new path.Context(style: Platform.isWindows
      ? path.Style.windows
      : path.Style.posix);

  /// The directory in which the test was loaded.
  ///
  /// Golden file keys will be interpreted as file paths relative to this
  /// directory.
  final Uri basedir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final File goldenFile = _getFile(golden);
    if (!goldenFile.existsSync()) {
      throw new TestFailure('Could not be compared against non-existent file: "$golden"');
    }
    final List<int> goldenBytes = await goldenFile.readAsBytes();
    return _areListsEqual(imageBytes, goldenBytes);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final File goldenFile = _getFile(golden);
    await goldenFile.writeAsBytes(imageBytes, flush: true);
  }

  File _getFile(Uri golden) {
    return new File(_path.join(_path.fromUri(basedir), golden.path));
  }

  static bool _areListsEqual<T>(List<T> list1, List<T> list2) {
    if (identical(list1, list2)) {
      return true;
    }
    if (list1 == null || list2 == null) {
      return false;
    }
    final int length = list1.length;
    if (length != list2.length) {
      return false;
    }
    for (int i = 0; i < length; i++) {
      if (list1[i] != list2[i]) {
        return false;
      }
    }
    return true;
  }
}
