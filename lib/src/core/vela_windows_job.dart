import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _JobBasicLimits extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;
  @Int64()
  external int perJobUserTimeLimit;
  @Uint32()
  external int limitFlags;
  @IntPtr()
  external int minimumWorkingSetSize;
  @IntPtr()
  external int maximumWorkingSetSize;
  @Uint32()
  external int activeProcessLimit;
  @IntPtr()
  external int affinity;
  @Uint32()
  external int priorityClass;
  @Uint32()
  external int schedulingClass;
}

final class _JobIoCounters extends Struct {
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

final class _JobExtendedLimits extends Struct {
  external _JobBasicLimits basicLimitInformation;
  external _JobIoCounters ioInfo;
  @IntPtr()
  external int processMemoryLimit;
  @IntPtr()
  external int jobMemoryLimit;
  @IntPtr()
  external int peakProcessMemoryUsed;
  @IntPtr()
  external int peakJobMemoryUsed;
}

/// Windows owns this job handle. It closes it automatically (and terminates
/// the child) when Vela-SHUO itself is force-killed, even without Dart events.
/// No process-name scanning or interference with other Mihomo applications.
class VelaWindowsJob {
  VelaWindowsJob._(this._job);
  final int _job;
  bool _closed = false;
  static final Set<VelaWindowsJob> _live = <VelaWindowsJob>{};

  static const int _killOnJobClose = 0x2000;
  static const int _extendedLimitInformation = 9;
  static const int _processSetQuota = 0x0100;
  static const int _processTerminate = 0x0001;
  static final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

  static final _createJobObject = _kernel.lookupFunction<
      IntPtr Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('CreateJobObjectW');
  static final _setInformation = _kernel.lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
      int Function(int, int, Pointer<Void>, int)>('SetInformationJobObject');
  static final _openProcess = _kernel.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)>('OpenProcess');
  static final _assignProcess = _kernel.lookupFunction<
      Int32 Function(IntPtr, IntPtr),
      int Function(int, int)>('AssignProcessToJobObject');
  static final _closeHandle = _kernel.lookupFunction<
      Int32 Function(IntPtr),
      int Function(int)>('CloseHandle');

  static VelaWindowsJob attach(int pid) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows process containment requires Windows');
    }
    final job = _createJobObject(nullptr, nullptr);
    if (job == 0) {
      throw StateError('无法创建 Mihomo 安全进程容器');
    }
    var processHandle = 0;
    final limits = calloc<_JobExtendedLimits>();
    var assigned = false;
    try {
      limits.ref.basicLimitInformation.limitFlags = _killOnJobClose;
      if (_setInformation(job, _extendedLimitInformation,
          limits.cast<Void>(), sizeOf<_JobExtendedLimits>()) == 0) {
        throw StateError('无法启用 Mihomo 随主程序退出保护');
      }
      processHandle = _openProcess(_processSetQuota | _processTerminate, 0, pid);
      if (processHandle == 0 || _assignProcess(job, processHandle) == 0) {
        throw StateError('无法将 Mihomo 绑定到 Vela-SHUO 进程');
      }
      assigned = true;
      final guard = VelaWindowsJob._(job);
      _live.add(guard);
      return guard;
    } finally {
      calloc.free(limits);
      if (processHandle != 0) _closeHandle(processHandle);
      if (!assigned) _closeHandle(job);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _live.remove(this);
    _closeHandle(_job);
  }
}
