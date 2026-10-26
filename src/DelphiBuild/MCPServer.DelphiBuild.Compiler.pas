unit MCPServer.DelphiBuild.Compiler;

interface

uses
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.ProcessRunner;

type
  IDelphiCompiler = interface
    ['{2B8E4F1A-7C3D-4A9E-8F21-5D6B0C4E7A13}']
    function Build(const Request: TBuildRequest): TBuildReport;
  end;

  TDelphiCompiler = class(TInterfacedObject, IDelphiCompiler)
  private
    FSettings: TDelphiBuildSettings;
    FRunner: IProcessRunner;
    procedure ValidateRequest(const Request: TBuildRequest);
    procedure ValidateProjectFile(const ProjectFile: string);
    procedure ValidateSearchPath(const SearchPath: string);
    function CreateReport(const Request: TBuildRequest; const ProcessResult: TProcessResult): TBuildReport;
    class function QuotePath(const Path: string): string; static;
  public
    class function OutputFolder(const Request: TBuildRequest): string; static;
    class function ExecutablePath(const Request: TBuildRequest): string; static;
    constructor Create(const Settings: TDelphiBuildSettings; const Runner: IProcessRunner);
    function CommandLine(const Request: TBuildRequest): string;
    function Build(const Request: TBuildRequest): TBuildReport;
  end;

resourcestring
  SProjectNotFound = 'Project file not found: %s';
  SProjectNotDpr = 'Only .dpr project files can be built, got: %s';
  SPathNotAllowed = 'Path is outside the allowed roots: %s';
  SSearchPathNotFound = 'Search path not found: %s';
  SCompilerNotFound = 'Delphi compiler not found: %s (set BdsPath in the [DelphiBuild] section of settings.ini)';
  SRunnerMissing = 'TDelphiCompiler needs a process runner';

implementation

uses
  System.SysUtils,
  System.IOUtils,
  MCPServer.DelphiBuild.CompilerOutput;

const
  ProjectExtension = '.dpr';
  ExecutableExtension = '.exe';
  BuildFolder = 'build';
  DcuFolder = 'DCU';
  LibFolder = 'lib';
  ReleaseLibFolder = 'release';
  IncludeFolder = 'include';
  PathSeparator = ';';
  OutputTailLines = 40;
  MillisecondsPerSecond = 1000;
  Namespaces = 'System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl;System.Win';
  DebugSwitches = '-$O- -$W+ -$R+ -$Q+';
  ReleaseSwitches = '-$O+ -$W- -$R- -$Q- -$C- -$D- -$L- -$Y-';
  CommandLineFormat = '"%s" %s --no-config -B -Q -TX.exe -D%s -NS%s -E"%s" -NU"%s" -NO"%s" -U%s -I%s -R%s -O%s "%s"';
  QuotedPathFormat = '"%s"';

class function TDelphiCompiler.OutputFolder(const Request: TBuildRequest): string;
begin
  const ProjectPath = TPath.GetFullPath(Request.ProjectFile);
  const ProjectFolder = TPath.GetDirectoryName(ProjectPath);
  const BuildRoot = TPath.Combine(ProjectFolder, BuildFolder);
  const PlatformFolder = TPath.Combine(BuildRoot, Request.Platform.Name);
  Result := TPath.Combine(PlatformFolder, Request.Config.Name);
end;

class function TDelphiCompiler.ExecutablePath(const Request: TBuildRequest): string;
begin
  const ProjectFileName = TPath.GetFileName(Request.ProjectFile);
  const ExecutableName = TPath.ChangeExtension(ProjectFileName, ExecutableExtension);
  const OutputPath = OutputFolder(Request);
  Result := TPath.Combine(OutputPath, ExecutableName);
end;

constructor TDelphiCompiler.Create(const Settings: TDelphiBuildSettings; const Runner: IProcessRunner);
begin
  inherited Create;
  if not Assigned(Runner) then
    raise EDelphiBuildError.Create(SRunnerMissing);

  FSettings := Settings;
  FRunner   := Runner;
end;

function TDelphiCompiler.CommandLine(const Request: TBuildRequest): string;
begin
  const CompilerFileName = Request.Platform.CompilerFileName;
  const Compiler = FSettings.CompilerPath(CompilerFileName);
  const LibRoot = TPath.Combine(FSettings.BdsPath, LibFolder);
  const PlatformLib = TPath.Combine(LibRoot, Request.Platform.Name);
  const LibPath = TPath.Combine(PlatformLib, ReleaseLibFolder);
  const IncludePath = TPath.Combine(FSettings.BdsPath, IncludeFolder);
  const OutputPath = OutputFolder(Request);
  const DcuPath = TPath.Combine(OutputPath, DcuFolder);
  const ProjectPath = TPath.GetFullPath(Request.ProjectFile);
  const Define = Request.Config.Name.ToUpper;

  const QuotedLibPath = QuotePath(LibPath);
  const QuotedIncludePath = QuotePath(IncludePath);
  var SearchPaths: TArray<string> := [QuotedLibPath, QuotedIncludePath];
  for var SearchPath in Request.SearchPaths do
  begin
    const QuotedSearchPath = QuotePath(SearchPath);
    SearchPaths := SearchPaths + [QuotedSearchPath];
  end;
  const SearchPathList = string.Join(PathSeparator, SearchPaths);

  const IsRelease = (Request.Config = TDelphiConfig.Release);
  var Switches := DebugSwitches;
  if IsRelease then
    Switches := ReleaseSwitches;

  Result := Format(CommandLineFormat, [Compiler, Switches, Define, Namespaces,
                                       OutputPath, DcuPath, DcuPath,
                                       SearchPathList, SearchPathList, SearchPathList, SearchPathList,
                                       ProjectPath]);
end;

function TDelphiCompiler.Build(const Request: TBuildRequest): TBuildReport;
begin
  ValidateRequest(Request);

  const OutputPath = OutputFolder(Request);
  const DcuPath = TPath.Combine(OutputPath, DcuFolder);
  TDirectory.CreateDirectory(DcuPath);

  const ProjectPath = TPath.GetFullPath(Request.ProjectFile);
  const ProjectFolder = TPath.GetDirectoryName(ProjectPath);
  const TimeoutMs = Cardinal(FSettings.TimeoutSeconds) * MillisecondsPerSecond;
  const BuildCommand = CommandLine(Request);
  const ProcessResult = FRunner.Run(BuildCommand, ProjectFolder, TimeoutMs);

  Result := CreateReport(Request, ProcessResult);
end;

procedure TDelphiCompiler.ValidateRequest(const Request: TBuildRequest);
begin
  ValidateProjectFile(Request.ProjectFile);
  for var SearchPath in Request.SearchPaths do
  begin
    ValidateSearchPath(SearchPath);
  end;

  const CompilerFileName = Request.Platform.CompilerFileName;
  const Compiler = FSettings.CompilerPath(CompilerFileName);
  const CompilerFound = TFile.Exists(Compiler);
  if not CompilerFound then
    raise EDelphiBuildError.CreateFmt(SCompilerNotFound, [Compiler]);
end;

procedure TDelphiCompiler.ValidateProjectFile(const ProjectFile: string);
begin
  const FullPath = TPath.GetFullPath(ProjectFile);
  const IsAllowed = FSettings.IsAllowed(FullPath);
  if not IsAllowed then
    raise EDelphiBuildError.CreateFmt(SPathNotAllowed, [FullPath]);

  const IsDpr = SameText(TPath.GetExtension(FullPath), ProjectExtension);
  if not IsDpr then
    raise EDelphiBuildError.CreateFmt(SProjectNotDpr, [FullPath]);

  const ProjectFound = TFile.Exists(FullPath);
  if not ProjectFound then
    raise EDelphiBuildError.CreateFmt(SProjectNotFound, [FullPath]);
end;

procedure TDelphiCompiler.ValidateSearchPath(const SearchPath: string);
begin
  const FullPath = TPath.GetFullPath(SearchPath);
  const IsAllowed = FSettings.IsAllowed(FullPath);
  if not IsAllowed then
    raise EDelphiBuildError.CreateFmt(SPathNotAllowed, [FullPath]);

  const FolderFound = TDirectory.Exists(FullPath);
  if not FolderFound then
    raise EDelphiBuildError.CreateFmt(SSearchPathNotFound, [FullPath]);
end;

function TDelphiCompiler.CreateReport(const Request: TBuildRequest; const ProcessResult: TProcessResult): TBuildReport;
begin
  const Messages = TCompilerOutputParser.Parse(ProcessResult.Output);

  Result := Default(TBuildReport);
  Result.ExitCode     := ProcessResult.ExitCode;
  Result.TimedOut     := ProcessResult.TimedOut;
  Result.DurationMs   := ProcessResult.DurationMs;
  Result.Messages     := Messages;
  Result.ErrorCount   := TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Error) +
                         TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Fatal);
  Result.WarningCount := TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Warning);
  Result.HintCount    := TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Hint);

  const NoErrors = (Result.ErrorCount = 0);
  const ExitedCleanly = (ProcessResult.ExitCode = 0) and not ProcessResult.TimedOut;
  Result.Succeeded := ExitedCleanly and NoErrors;

  if Result.Succeeded then
    Result.ExecutablePath := ExecutablePath(Request)
  else
    Result.OutputTail := TCompilerOutputParser.Tail(ProcessResult.Output, OutputTailLines);
end;

class function TDelphiCompiler.QuotePath(const Path: string): string;
begin
  const FullPath = TPath.GetFullPath(Path);
  const PathWithoutDelimiter = ExcludeTrailingPathDelimiter(FullPath);
  Result := Format(QuotedPathFormat, [PathWithoutDelimiter]);
end;

end.
