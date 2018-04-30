// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:test/test.dart' as test_package;
import 'package:test/test.dart' hide test;

import 'package:flutter_test/flutter_test.dart' show goldenFileComparator, LocalFileComparator;

const List<int> _kExpectedBytes = const <int>[1, 2, 3];

void main() {
  MemoryFileSystem fs;

  setUp(() {
    final FileSystemStyle style = io.Platform.isWindows
        ? FileSystemStyle.windows
        : FileSystemStyle.posix;
    fs = new MemoryFileSystem(style: style);
  });

  void test(String description, FutureOr<void> body()) {
    test_package.test(description, () {
      return io.IOOverrides.runZoned(
        body,
        createDirectory: (String path) => fs.directory(path),
        createFile: (String path) => fs.file(path),
        createLink: (String path) => fs.link(path),
        getCurrentDirectory: () => fs.currentDirectory,
        setCurrentDirectory: (String path) => fs.currentDirectory = path,
        getSystemTempDirectory: () => fs.systemTempDirectory,
        stat: (String path) => fs.stat(path),
        statSync: (String path) => fs.statSync(path),
        fseIdentical: (String p1, String p2) => fs.identical(p1, p2),
        fseIdenticalSync: (String p1, String p2) => fs.identicalSync(p1, p2),
        fseGetType: (String path, bool followLinks) => fs.type(path, followLinks: followLinks),
        fseGetTypeSync: (String path, bool followLinks) => fs.typeSync(path, followLinks: followLinks),
        fsWatch: (String a, int b, bool c) => throw new UnsupportedError('unsupported'),
        fsWatchIsSupported: () => fs.isWatchSupported,
      );
    });
  }

  group('goldenFileComparator', () {
    test('is initialized by test framework', () {
      expect(goldenFileComparator, isNotNull);
      expect(goldenFileComparator, const isInstanceOf<LocalFileComparator>());
      final LocalFileComparator comparator = goldenFileComparator;
      expect(comparator.basedir.path, contains('flutter_test'));
    });
  });

  group('LocalFileComparator', () {
    LocalFileComparator comparator;

    setUp(() {
      comparator = new LocalFileComparator(new Uri.file('/golden_test.dart'));
    });

    test('calculates basedir correctly', () {
      expect(comparator.basedir, new Uri.file('/'));
      comparator = new LocalFileComparator(new Uri.file('/foo/bar/golden_test.dart'));
      expect(comparator.basedir, new Uri.file('/foo/bar/'));
    });

    group('compare', () {
      Future<bool> doComparison([String golden = 'golden.png']) {
        final Uri uri = new Uri.file(golden);
        return comparator.compare(
          new Uint8List.fromList(_kExpectedBytes),
          uri,
        );
      }

      group('succeeds', () {
        test('when golden file is in same folder as test', () async {
          fs.file('/golden.png').writeAsBytesSync(_kExpectedBytes);
          final bool success = await doComparison();
          expect(success, isTrue);
        });

        test('when golden file is in subfolder of test', () async {
          fs.file('/sub/foo.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(_kExpectedBytes);
          final bool success = await doComparison('sub/foo.png');
          expect(success, isTrue);
        });
      });

      group('fails', () {
        test('when golden file does not exist', () async {
          final Future<bool> comparison = doComparison();
          expect(comparison, throwsA(const isInstanceOf<TestFailure>()));
        });

        test('when golden bytes are leading subset of image bytes', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[1, 2]);
          expect(await doComparison(), isFalse);
        });

        test('when golden bytes are leading superset of image bytes', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[1, 2, 3, 4]);
          expect(await doComparison(), isFalse);
        });

        test('when golden bytes are trailing subset of image bytes', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[2, 3]);
          expect(await doComparison(), isFalse);
        });

        test('when golden bytes are trailing superset of image bytes', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[0, 1, 2, 3]);
          expect(await doComparison(), isFalse);
        });

        test('when golden bytes are disjoint from image bytes', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[4, 5, 6]);
          expect(await doComparison(), isFalse);
        });

        test('when golden bytes are empty', () async {
          fs.file('/golden.png').writeAsBytesSync(<int>[]);
          expect(await doComparison(), isFalse);
        });
      });
    });

    group('update', () {
      test('updates existing file', () async {
        fs.file('/golden.png').writeAsBytesSync(_kExpectedBytes);
        const List<int> newBytes = const <int>[11, 12, 13];
        await comparator.update(new Uri.file('golden.png'), new Uint8List.fromList(newBytes));
        expect(fs.file('/golden.png').readAsBytesSync(), newBytes);
      });

      test('creates non-existent file', () async {
        expect(fs.file('/foo.png').existsSync(), isFalse);
        const List<int> newBytes = const <int>[11, 12, 13];
        await comparator.update(new Uri.file('foo.png'), new Uint8List.fromList(newBytes));
        expect(fs.file('/foo.png').existsSync(), isTrue);
        expect(fs.file('/foo.png').readAsBytesSync(), newBytes);
      });
    });
  });
}
