import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// windows flag that kills child processes when the job closes
const _jobObjectLimitKillOnJobClose = 0x00002000;

/// mirrors the windows io counter struct used by job limits
base class _IoCounters extends Struct {
  @Uint64()
  external int readOperationCount;

  @Uint64()
  external int writeOperationCount;

  @Uint64()
  external int otherOperationCount;

  @Uint64()
  external int readTransferCount;

  @Uint64()
  external int writeTransferCount;

  @Uint64()
  external int otherTransferCount;
}

/// mirrors the windows basic job limit struct
base class _JobObjectBasicLimitInformation extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;

  @Int64()
  external int perJobUserTimeLimit;

  @Uint32()
  external int limitFlags;

  @UintPtr()
  external int minimumWorkingSetSize;

  @UintPtr()
  external int maximumWorkingSetSize;

  @Uint32()
  external int activeProcessLimit;

  @UintPtr()
  external int affinity;

  @Uint32()
  external int priorityClass;

  @Uint32()
  external int schedulingClass;
}

/// mirrors the windows extended job limit struct
base class _JobObjectExtendedLimitInformation extends Struct {
  external _JobObjectBasicLimitInformation basicLimitInformation;
  external _IoCounters ioInfo;

  @UintPtr()
  external int processMemoryLimit;

  @UintPtr()
  external int jobMemoryLimit;

  @UintPtr()
  external int peakProcessMemoryUsed;

  @UintPtr()
  external int peakJobMemoryUsed;
}

/// groups child processes so they close with the manager
class WindowsJobObject {
  WindowsJobObject();

  int? _handle;

  bool get enabled => _handle != null;

  /// creates a job that closes child processes when the manager exits
  void create() {
    if (!Platform.isWindows) return;
    final handle = CreateJobObject(nullptr, nullptr);
    if (handle == 0) return;

    final info = calloc<_JobObjectExtendedLimitInformation>();
    try {
      info.ref.basicLimitInformation.limitFlags = _jobObjectLimitKillOnJobClose;
      final ok = SetInformationJobObject(
        handle,
        JobObjectExtendedLimitInformation,
        info.cast(),
        sizeOf<_JobObjectExtendedLimitInformation>(),
      );
      if (ok == 0) {
        CloseHandle(handle);
        return;
      }
      _handle = handle;
    } finally {
      calloc.free(info);
    }
  }

  /// assigns a started process to the manager job
  void assignPid(int pid) {
    final handle = _handle;
    if (handle == null || !Platform.isWindows) return;
    final processHandle = OpenProcess(
      PROCESS_SET_QUOTA | PROCESS_TERMINATE,
      FALSE,
      pid,
    );
    if (processHandle == 0) return;
    try {
      AssignProcessToJobObject(handle, processHandle);
    } finally {
      CloseHandle(processHandle);
    }
  }

  /// closes the job handle and lets windows clean up child processes
  void close() {
    final handle = _handle;
    if (handle == null) return;
    CloseHandle(handle);
    _handle = null;
  }
}
