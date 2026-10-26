unit MCPServer.Tests.DelphiBuild.FakeRunner;

interface

uses
  System.Generics.Collections,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.ProcessRunner;

type
  TRecordedRun = record
    CommandLine: string;
    WorkingDirectory: string;
    TimeoutMs: Cardinal;
  end;

  TFakeProcessRunner = class(TInterfacedObject, IProcessRunner)
  private
    FResults: TQueue<TProcessResult>;
    FRuns: TList<TRecordedRun>;
    function GetRunCount: Integer;
    function GetRun(const Index: Integer): TRecordedRun;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const Output: string; const ExitCode: Cardinal = 0; const TimedOut: Boolean = False);
    function Run(const CommandLine: string; const WorkingDirectory: string; const TimeoutMs: Cardinal): TProcessResult;
    property RunCount: Integer read GetRunCount;
    property Runs[const Index: Integer]: TRecordedRun read GetRun;
  end;

  TFakeProject = record
    Root: string;
    BdsPath: string;
    ProjectFile: string;
    class function Create(const ProjectName: string): TFakeProject; static;
    function Settings: TDelphiBuildSettings;
    function JsonProjectFile: string;
    procedure Delete;
  end;

const
  CleanCompilerOutput = '12 lines, 0.05 seconds, 100 bytes code, 10 bytes data.';
  Dcc32FileName = 'dcc32.exe';
  Dcc64FileName = 'dcc64.exe';
  CompilerFolder = 'bin';
  MillisecondsPerSecond = 1000;

implementation

uses
  System.SysUtils,
  System.IOUtils;

const
  StudioFolder = 'Studio';
  ProjectFolderName = 'Project';
  ProjectExtension = '.dpr';
  ProjectSource = 'program %s; begin end.';
  Backslash = '\';
  JsonBackslash = '\\';

constructor TFakeProcessRunner.Create;
begin
  inherited Create;
  FResults := TQueue<TProcessResult>.Create;
  FRuns := TList<TRecordedRun>.Create;
end;

destructor TFakeProcessRunner.Destroy;
begin
  FRuns.Free;
  FResults.Free;
  inherited Destroy;
end;

procedure TFakeProcessRunner.Enqueue(const Output: string; const ExitCode: Cardinal; const TimedOut: Boolean);
begin
  var Canned := Default(TProcessResult);
  Canned.Output   := Output;
  Canned.ExitCode := ExitCode;
  Canned.TimedOut := TimedOut;
  FResults.Enqueue(Canned);
end;

function TFakeProcessRunner.Run(const CommandLine: string; const WorkingDirectory: string; const TimeoutMs: Cardinal): TProcessResult;
begin
  var Recorded := Default(TRecordedRun);
  Recorded.CommandLine      := CommandLine;
  Recorded.WorkingDirectory := WorkingDirectory;
  Recorded.TimeoutMs        := TimeoutMs;
  FRuns.Add(Recorded);

  Result := FResults.Dequeue;
end;

function TFakeProcessRunner.GetRunCount: Integer;
begin
  Result := Integer(FRuns.Count);
end;

function TFakeProcessRunner.GetRun(const Index: Integer): TRecordedRun;
begin
  Result := FRuns[Index];
end;

class function TFakeProject.Create(const ProjectName: string): TFakeProject;
begin
  const TempFolder = TPath.GetTempPath;
  const UniqueName = TPath.GetGUIDFileName;
  Result.Root    := TPath.Combine(TempFolder, UniqueName);
  Result.BdsPath := TPath.Combine(Result.Root, StudioFolder);

  const BinFolder = TPath.Combine(Result.BdsPath, CompilerFolder);
  const Dcc32Path = TPath.Combine(BinFolder, Dcc32FileName);
  const Dcc64Path = TPath.Combine(BinFolder, Dcc64FileName);
  TDirectory.CreateDirectory(BinFolder);
  TFile.WriteAllText(Dcc32Path, '');
  TFile.WriteAllText(Dcc64Path, '');

  const ProjectFolder = TPath.Combine(Result.Root, ProjectFolderName);
  const ProjectFileName = TPath.ChangeExtension(ProjectName, ProjectExtension);
  const Source = Format(ProjectSource, [ProjectName]);
  TDirectory.CreateDirectory(ProjectFolder);
  Result.ProjectFile := TPath.Combine(ProjectFolder, ProjectFileName);
  TFile.WriteAllText(Result.ProjectFile, Source);
end;

function TFakeProject.Settings: TDelphiBuildSettings;
begin
  Result := TDelphiBuildSettings.Defaults;
  Result.Enabled      := True;
  Result.BdsPath      := BdsPath;
  Result.AllowedRoots := [Root];
end;

function TFakeProject.JsonProjectFile: string;
begin
  Result := ProjectFile.Replace(Backslash, JsonBackslash);
end;

procedure TFakeProject.Delete;
begin
  const RootExists = TDirectory.Exists(Root);
  if RootExists then
    TDirectory.Delete(Root, True);
end;

end.
