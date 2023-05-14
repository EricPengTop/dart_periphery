// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_periphery/src/cpu_architecture.dart';

import 'native/lib_base64.dart';

const pkgName = 'dart_periphery';

const String version = '1.0.0';

final String sharedLib = 'libperiphery.so';

String library = "";

String test = "///";

late DynamicLibrary _peripheryLib;
bool isPeripheryLibLoaded = false;
String _peripheryLibPath = '';

class PlatformException implements Exception {
  final String error;
  PlatformException(this.error);
  @override
  String toString() => error;
}

// Fix typo
// https://github.com/pezi/dart_periphery/pull/20
@Deprecated("Fix typo in method name")
void useSharedLibray() {
  _peripheryLibPath = sharedLib;
}

/// dart_periphery loads the shared library.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void useSharedLibrary() {
  _peripheryLibPath = sharedLib;
}

/// dart_periphery loads a custom library.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void setCustomLibrary(String absolutePath) {
  _peripheryLibPath = absolutePath;
}

/// Bypasses the autodetection of the CPU architecture.
void setCPUarchitecture(CpuArchitecture arch) {
  if (arch == CpuArchitecture.notSupported ||
      arch == CpuArchitecture.undefined) {
    throw LibraryException(
        LibraryErrorCode.invalidParameter, "Invalid parameter");
  }
  var cpu = arch.toString();
  cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
  library = 'libperiphery_$cpu.so';
}

String _autoDetectCPUarch() {
  CpuArch arch = CpuArch();
  if (arch.cpuArch == CpuArchitecture.notSupported) {
    throw LibraryException(LibraryErrorCode.cpuArchDetectionFailed,
        "Unable to detect CPU architecture, found '${arch.machine}' . Use 'setCustomLibrary(String absolutePath)' - see documentation https://github.com/pezi/dart_periphery, or create an issue https://github.com/pezi/dart_periphery/issues");
  }
  var cpu = arch.cpuArch.toString();
  cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
  return 'libperiphery_$cpu.so';
}

/// dart_periphery loads the library from the actual directory.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void useLocalLibrary([CpuArchitecture arch = CpuArchitecture.undefined]) {
  if (arch == CpuArchitecture.undefined) {
    _peripheryLibPath = './${_autoDetectCPUarch()}';
  } else {
    if (arch == CpuArchitecture.notSupported) {
      throw LibraryException(
          LibraryErrorCode.invalidParameter, "Invalid parameter");
    }
    var cpu = arch.toString();
    cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
    _peripheryLibPath = './libperiphery_$cpu.so';
  }
}

enum LibraryErrorCode {
  libraryNotFound,
  cpuArchDetectionFailed,
  invalidParameter
}

/// Library exception
class LibraryException implements Exception {
  final String errorMsg;
  final LibraryErrorCode errorCode;
  LibraryException(this.errorCode, this.errorMsg);
  @override
  String toString() => errorMsg;
}

// ignore: camel_case_types
typedef _getpId = Int32 Function();
typedef _GetpId = int Function();

bool _isFlutterPi = Platform.resolvedExecutable.endsWith('flutter-pi');

/// Returns true for a flutter-pi environment.
bool isFlutterPiEnv() {
  return _isFlutterPi;
}

var _flutterPiArgs = <String>[];

/// Returns the PID of the running flutter-pi program, -1 for all other platforms.
int getPID() {
  if (!isFlutterPiEnv()) {
    return -1;
  }
  final dylib = DynamicLibrary.open('libc.so.6');
  var getpid =
      dylib.lookup<NativeFunction<_getpId>>('getpid').asFunction<_GetpId>();
  return getpid();
}

/// Returns the argument list of the running flutter-pi program by
/// reading the /proc/PID/cmdline data. For a non flutter-pi environment
/// an empty list will be returned.
List<String> getFlutterPiArgs() {
  if (!isFlutterPiEnv()) {
    return const <String>[];
  }
  if (_flutterPiArgs.isEmpty) {
    var cmd = File('/proc/${getPID()}/cmdline').readAsBytesSync();
    var index = 0;
    for (var i = 0; i < cmd.length; ++i) {
      if (cmd[i] == 0) {
        _flutterPiArgs
            .add(String.fromCharCodes(Uint8List.sublistView(cmd, index, i)));
        index = i + 1;
      }
    }
  }
  return List.unmodifiable(_flutterPiArgs);
}

DynamicLibrary getPeripheryLib() {
  if (isPeripheryLibLoaded) {
    return _peripheryLib;
  }
  if (!Platform.isLinux) {
    throw PlatformException('dart_periphery is only supported for Linux!');
  }

  String path = '';
  if (isFlutterPiEnv() && _peripheryLibPath.isEmpty) {
    var args = getFlutterPiArgs();
    var index = 1;
    for (var i = 1; i < args.length; ++i) {
      // skip --release
      if (args[i].startsWith('--release')) {
        ++index;
        // skip options like -r, --rotation <degrees>
      } else if (args[i].startsWith('-')) {
        index += 2;
      } else {
        break;
      }
    }
    var assetDir = args[index];
    var separator = '';
    if (!assetDir.startsWith('/')) {
      separator = '/';
    }
    var dir = Directory.current.path + separator + assetDir;
    if (!dir.endsWith('/')) {
      dir += '/';
    }
    if (library.isEmpty) {
      library = _autoDetectCPUarch();
    }
    path = dir + library;
  } else {
    String libName = _autoDetectCPUarch();

    String base64EncodedLib = '';
    CpuArch arch = CpuArch();
    switch (arch.cpuArch) {
      case CpuArchitecture.arm:
        base64EncodedLib = arm;
        break;
      case CpuArchitecture.arm64:
        base64EncodedLib = arm64;
        break;
      case CpuArchitecture.x86:
        base64EncodedLib = x86;
        break;
      case CpuArchitecture.x86_64:
        base64EncodedLib = x86_64;
        break;
      default:
        throw LibraryException(LibraryErrorCode.invalidParameter,
            "Not supported Cpu architecture");
    }

    var systemTempDir = Directory.systemTemp;
    path = systemTempDir.path + Platform.pathSeparator + libName;
    final file = File(path);

    file.createSync(recursive: true);
    final decodedBytes = base64Decode(base64EncodedLib);
    file.writeAsBytesSync(decodedBytes);
  }
  _peripheryLib = DynamicLibrary.open(path);

  isPeripheryLibLoaded = true;
  return _peripheryLib;
}
