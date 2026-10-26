unit MCPServer.Tests.DelphiBuild.ProcessRunner;

interface

uses
  DUnitX.TestFramework,
  MCPServer.DelphiBuild.ProcessRunner;

type
  [TestFixture]
  TWindowsProcessRunnerTests = class
  private
    FRunner: IProcessRunner;
    class function CountProcesses(const ExeName: string): Integer; static;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Run_CapturesStandardOutputAndError;
    [Test]
    procedure Run_ReturnsExitCode;
    [Test]
    procedure Run_UsesWorkingDirectory;
    [Test]
    procedure Run_PastTimeout_KillsProcess;
    [Test]
    procedure Run_PastTimeout_KillsGrandchildren;
    [Test]
    procedure Run_StandardInputIsNul_ProcessDoesNotWaitForInput;
    [Test]
    procedure Run_LargeOutput_IsReadCompletely;
    [Test]
    procedure Run_UnknownProgram_RaisesBuildError;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.TlHelp32,
  MCPServer.DelphiBuild.Types;

const
  TimeoutMs = 10000;
  PingExe = 'ping.exe';
  SettleMs = 500;
  GrandchildDeadlineMs = 10000;

class function TWindowsProcessRunnerTests.CountProcesses(const ExeName: string): Integer;
begin
  Result := 0;
  const Snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  try
    var Entry := Default(TProcessEntry32);
    Entry.dwSize := SizeOf(Entry);
    var HasEntry := Process32First(Snapshot, Entry);
    while HasEntry do
    begin
      const EntryName = string(Entry.szExeFile);
      const IsMatch = SameText(EntryName, ExeName);
      if IsMatch then
        Inc(Result);
      HasEntry := Process32Next(Snapshot, Entry);
    end;
  finally
    CloseHandle(Snapshot);
  end;
end;

procedure TWindowsProcessRunnerTests.Run_PastTimeout_KillsGrandchildren;
begin
  const PingsBefore = CountProcesses(PingExe);

  const Result = FRunner.Run('cmd.exe /c ping -n 60 127.0.0.1', TPath.GetTempPath, 500);
  Sleep(SettleMs);

  Assert.IsTrue(Result.TimedOut);
  Assert.IsTrue(Result.DurationMs < GrandchildDeadlineMs, Format('The process tree was stopped only after %d ms', [Result.DurationMs]));
  Assert.AreEqual(PingsBefore, CountProcesses(PingExe), 'ping.exe survived the timeout of its parent cmd.exe');
end;

procedure TWindowsProcessRunnerTests.Setup;
begin
  FRunner := TWindowsProcessRunner.Create;
end;

procedure TWindowsProcessRunnerTests.TearDown;
begin
  FRunner := nil;
end;

procedure TWindowsProcessRunnerTests.Run_CapturesStandardOutputAndError;
begin
  const Result = FRunner.Run('cmd.exe /c "echo to-out& echo to-err 1>&2"', TPath.GetTempPath, TimeoutMs);

  Assert.Contains(Result.Output, 'to-out');
  Assert.Contains(Result.Output, 'to-err');
  Assert.IsFalse(Result.TimedOut);
end;

procedure TWindowsProcessRunnerTests.Run_ReturnsExitCode;
begin
  const Result = FRunner.Run('cmd.exe /c exit 3', TPath.GetTempPath, TimeoutMs);

  Assert.AreEqual<Cardinal>(3, Result.ExitCode);
end;

procedure TWindowsProcessRunnerTests.Run_UsesWorkingDirectory;
begin
  const Folder = TPath.Combine(TPath.GetTempPath, TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Folder);
  try
    const Result = FRunner.Run('cmd.exe /c cd', Folder, TimeoutMs);

    Assert.AreEqual(Folder, Result.Output.Trim);
  finally
    TDirectory.Delete(Folder);
  end;
end;

procedure TWindowsProcessRunnerTests.Run_PastTimeout_KillsProcess;
begin
  const Result = FRunner.Run('cmd.exe /c ping -n 30 127.0.0.1', TPath.GetTempPath, 500);

  Assert.IsTrue(Result.TimedOut);
  Assert.IsTrue(Result.DurationMs < 10000, Format('Took %d ms', [Result.DurationMs]));
end;

procedure TWindowsProcessRunnerTests.Run_StandardInputIsNul_ProcessDoesNotWaitForInput;
begin
  const Result = FRunner.Run('findstr.exe anything', TPath.GetTempPath, 5000);

  Assert.IsFalse(Result.TimedOut, 'The child process read from the parent''s standard input');
end;

procedure TWindowsProcessRunnerTests.Run_LargeOutput_IsReadCompletely;
begin
  const Result = FRunner.Run('cmd.exe /c "for /l %i in (1,1,5000) do @echo line %i of the output"', TPath.GetTempPath, 60000);

  Assert.IsFalse(Result.TimedOut);
  Assert.Contains(Result.Output, 'line 1 of the output');
  Assert.Contains(Result.Output, 'line 5000 of the output');
end;

procedure TWindowsProcessRunnerTests.Run_UnknownProgram_RaisesBuildError;
begin
  Assert.WillRaise(
    procedure
    begin
      FRunner.Run('"C:\does\not\exist.exe"', TPath.GetTempPath, TimeoutMs);
    end,
    EDelphiBuildError);
end;

end.
