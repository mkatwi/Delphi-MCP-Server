unit MCPServer.DelphiBuild.ProcessRunner;

interface

uses
  System.Classes,
  Winapi.Windows,
  MCPServer.DelphiBuild.Types;

type
  IProcessRunner = interface
    ['{6D0C3B1E-8A4F-4E2B-9B7D-2F5A1C9E3D84}']
    function Run(const CommandLine: string; const WorkingDirectory: string; const TimeoutMs: Cardinal): TProcessResult;
  end;

  TWindowsProcessRunner = class(TInterfacedObject, IProcessRunner)
  private type
    TProcessHandles = record
      OutputRead: THandle;
      OutputWrite: THandle;
      InputNull: THandle;
      Job: THandle;
    end;
  private
    function CreateHandles: TProcessHandles;
    function CreateKillOnCloseJob: THandle;
    function StartProcess(const CommandLine: string; const WorkingDirectory: string; const Handles: TProcessHandles): TProcessInformation;
    function CreateInheritList(const InheritedHandles: TArray<THandle>): PProcThreadAttributeList;
    function WaitForExit(const Process: TProcessInformation; const Handles: TProcessHandles; const TimeoutMs: Cardinal; const Output: TBytesStream): Boolean;
    procedure DrainPipe(const ReadHandle: THandle; const Output: TBytesStream);
    procedure KeepTail(const Output: TBytesStream);
    function DecodeOutput(const Output: TBytesStream): string;
    procedure CloseHandles(const Handles: TProcessHandles);
  public
    function Run(const CommandLine: string; const WorkingDirectory: string; const TimeoutMs: Cardinal): TProcessResult;
  end;

const
  MaxOutputBytes = 8 * 1024 * 1024;

implementation

uses
  System.SysUtils,
  System.Diagnostics;

type
  TStartupInfoEx = record
    StartupInfo: TStartupInfo;
    AttributeList: PProcThreadAttributeList;
  end;

const
  PollIntervalMs = 50;
  ReadBufferSize = 65536;
  NullDevice = 'NUL';
  TerminatedExitCode = 1;
  InheritAttributeCount = 1;
  ProcThreadAttributeHandleList = $00020002;
  CreationFlags = CREATE_NO_WINDOW or CREATE_SUSPENDED or EXTENDED_STARTUPINFO_PRESENT;
  TruncatedMarker = '[earlier output truncated]';

procedure DeleteProcThreadAttributeList(lpAttributeList: PProcThreadAttributeList); stdcall;
  external kernel32 name 'DeleteProcThreadAttributeList';

function UpdateHandleListAttribute(lpAttributeList: PProcThreadAttributeList; dwFlags: DWORD; Attribute: NativeUInt;
                                   lpValue: Pointer; cbSize: NativeUInt; lpPreviousValue: Pointer;
                                   lpReturnSize: PNativeUInt): BOOL; stdcall;
  external kernel32 name 'UpdateProcThreadAttribute';

resourcestring
  SPipeCreationFailed = 'Could not create the output pipe: %s';
  SNullDeviceFailed = 'Could not open the NUL device for standard input: %s';
  SJobCreationFailed = 'Could not create the job object for the child process: %s';
  SAttributeListFailed = 'Could not prepare the handle list for the child process: %s';
  SProcessStartFailed = 'Could not start "%s": %s';

function TWindowsProcessRunner.Run(const CommandLine: string; const WorkingDirectory: string; const TimeoutMs: Cardinal): TProcessResult;
begin
  Result := Default(TProcessResult);
  const Stopwatch = TStopwatch.StartNew;
  const Handles = CreateHandles;
  try
    const Process = StartProcess(CommandLine, WorkingDirectory, Handles);
    try
      const Output = TBytesStream.Create;
      try
        Result.TimedOut := not WaitForExit(Process, Handles, TimeoutMs, Output);
        Result.Output   := DecodeOutput(Output);
      finally
        Output.Free;
      end;

      var ExitCode: Cardinal := TerminatedExitCode;
      GetExitCodeProcess(Process.hProcess, ExitCode);
      Result.ExitCode := ExitCode;
    finally
      CloseHandle(Process.hThread);
      CloseHandle(Process.hProcess);
    end;
  finally
    CloseHandles(Handles);
  end;
  Result.DurationMs := Stopwatch.ElapsedMilliseconds;
end;

function TWindowsProcessRunner.CreateHandles: TProcessHandles;
begin
  Result := Default(TProcessHandles);
  var Security := Default(TSecurityAttributes);
  Security.nLength        := SizeOf(Security);
  Security.bInheritHandle := True;

  const PipeCreated = CreatePipe(Result.OutputRead, Result.OutputWrite, @Security, 0);
  if not PipeCreated then
    raise EDelphiBuildError.CreateFmt(SPipeCreationFailed, [SysErrorMessage(GetLastError)]);
  SetHandleInformation(Result.OutputRead, HANDLE_FLAG_INHERIT, 0);

  Result.InputNull := CreateFile(NullDevice, GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security, OPEN_EXISTING, 0, 0);
  const NullOpened = (Result.InputNull <> INVALID_HANDLE_VALUE);
  if not NullOpened then
  begin
    const ErrorText = SysErrorMessage(GetLastError);
    Result.InputNull := 0;
    CloseHandles(Result);
    raise EDelphiBuildError.CreateFmt(SNullDeviceFailed, [ErrorText]);
  end;

  try
    Result.Job := CreateKillOnCloseJob;
  except
    CloseHandles(Result);
    raise;
  end;
end;

function TWindowsProcessRunner.CreateKillOnCloseJob: THandle;
begin
  Result := CreateJobObject(nil, nil);
  const JobCreated = (Result <> 0);
  if not JobCreated then
    raise EDelphiBuildError.CreateFmt(SJobCreationFailed, [SysErrorMessage(GetLastError)]);

  var Limits := Default(TJobObjectExtendedLimitInformation);
  Limits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  const LimitsSet = SetInformationJobObject(Result, JobObjectExtendedLimitInformation, @Limits, SizeOf(Limits));
  if not LimitsSet then
  begin
    const ErrorText = SysErrorMessage(GetLastError);
    CloseHandle(Result);
    raise EDelphiBuildError.CreateFmt(SJobCreationFailed, [ErrorText]);
  end;
end;

function TWindowsProcessRunner.StartProcess(const CommandLine: string; const WorkingDirectory: string; const Handles: TProcessHandles): TProcessInformation;
begin
  var InheritedHandles: TArray<THandle> := [Handles.OutputWrite, Handles.InputNull];
  var StartupInfo := Default(TStartupInfoEx);
  StartupInfo.StartupInfo.cb          := SizeOf(StartupInfo);
  StartupInfo.StartupInfo.dwFlags     := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  StartupInfo.StartupInfo.wShowWindow := SW_HIDE;
  StartupInfo.StartupInfo.hStdInput   := Handles.InputNull;
  StartupInfo.StartupInfo.hStdOutput  := Handles.OutputWrite;
  StartupInfo.StartupInfo.hStdError   := Handles.OutputWrite;
  StartupInfo.AttributeList           := CreateInheritList(InheritedHandles);
  try
    var MutableCommandLine := CommandLine;
    UniqueString(MutableCommandLine);
    Result := Default(TProcessInformation);

    const Started = CreateProcess(nil, PChar(MutableCommandLine), nil, nil, True, CreationFlags, nil,
                                  PChar(WorkingDirectory), StartupInfo.StartupInfo, Result);
    if not Started then
      raise EDelphiBuildError.CreateFmt(SProcessStartFailed, [CommandLine, SysErrorMessage(GetLastError)]);
  finally
    DeleteProcThreadAttributeList(StartupInfo.AttributeList);
    FreeMem(StartupInfo.AttributeList);
  end;

  AssignProcessToJobObject(Handles.Job, Result.hProcess);
  ResumeThread(Result.hThread);
end;

function TWindowsProcessRunner.CreateInheritList(const InheritedHandles: TArray<THandle>): PProcThreadAttributeList;
begin
  var Size: NativeUInt := 0;
  InitializeProcThreadAttributeList(nil, InheritAttributeCount, 0, Size);
  Result := AllocMem(NativeInt(Size));

  const Initialized = InitializeProcThreadAttributeList(Result, InheritAttributeCount, 0, Size);
  const HandleBytes = NativeUInt(Length(InheritedHandles)) * SizeOf(THandle);
  const Updated = Initialized and
                  UpdateHandleListAttribute(Result, 0, ProcThreadAttributeHandleList, @InheritedHandles[0],
                                            HandleBytes, nil, nil);
  if not Updated then
  begin
    const ErrorText = SysErrorMessage(GetLastError);
    if Initialized then
      DeleteProcThreadAttributeList(Result);
    FreeMem(Result);
    raise EDelphiBuildError.CreateFmt(SAttributeListFailed, [ErrorText]);
  end;
end;

function TWindowsProcessRunner.WaitForExit(const Process: TProcessInformation; const Handles: TProcessHandles; const TimeoutMs: Cardinal; const Output: TBytesStream): Boolean;
begin
  const Stopwatch = TStopwatch.StartNew;
  Result := False;
  try
    while not Result do
    begin
      DrainPipe(Handles.OutputRead, Output);
      const WaitResult = WaitForSingleObject(Process.hProcess, PollIntervalMs);
      Result := (WaitResult = WAIT_OBJECT_0);

      const IsOverdue = (Stopwatch.ElapsedMilliseconds > TimeoutMs);
      const MustStop = (not Result) and IsOverdue;
      if MustStop then
      begin
        TerminateJobObject(Handles.Job, TerminatedExitCode);
        WaitForSingleObject(Process.hProcess, INFINITE);
        Break;
      end;
    end;
    DrainPipe(Handles.OutputRead, Output);
  except
    TerminateJobObject(Handles.Job, TerminatedExitCode);
    raise;
  end;
end;

procedure TWindowsProcessRunner.DrainPipe(const ReadHandle: THandle; const Output: TBytesStream);
begin
  var Buffer: TBytes;
  SetLength(Buffer, ReadBufferSize);
  var Available: DWORD := 0;
  while PeekNamedPipe(ReadHandle, nil, 0, nil, @Available, nil) and (Available > 0) do
  begin
    var BytesRead: DWORD := 0;
    const ReadOk = ReadFile(ReadHandle, Buffer[0], ReadBufferSize, BytesRead, nil);
    const HasData = ReadOk and (BytesRead > 0);
    if not HasData then
      Break;
    Output.WriteBuffer(Buffer[0], Integer(BytesRead));
    KeepTail(Output);
  end;
end;

procedure TWindowsProcessRunner.KeepTail(const Output: TBytesStream);
begin
  const IsTooLarge = (Output.Size > MaxOutputBytes);
  if not IsTooLarge then
    Exit;

  const KeepBytes = MaxOutputBytes div 2;
  const Tail = Copy(Output.Bytes, Integer(Output.Size) - KeepBytes, KeepBytes);
  const Marker = TEncoding.ANSI.GetBytes(TruncatedMarker + sLineBreak);
  Output.Clear;
  Output.WriteBuffer(Marker[0], Length(Marker));
  Output.WriteBuffer(Tail[0], Length(Tail));
end;

function TWindowsProcessRunner.DecodeOutput(const Output: TBytesStream): string;
begin
  const ByteCount = Integer(Output.Size);
  Result := TEncoding.ANSI.GetString(Output.Bytes, 0, ByteCount);
end;

procedure TWindowsProcessRunner.CloseHandles(const Handles: TProcessHandles);
begin
  const HandleList: TArray<THandle> = [Handles.Job, Handles.OutputRead, Handles.OutputWrite, Handles.InputNull];
  for var Handle in HandleList do
  begin
    const IsOpen = (Handle <> 0) and (Handle <> INVALID_HANDLE_VALUE);
    if IsOpen then
      CloseHandle(Handle);
  end;
end;

end.
