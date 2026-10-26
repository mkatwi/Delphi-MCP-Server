unit MCPServer.DelphiBuild.TestRunner;

interface

uses
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.ProcessRunner,
  MCPServer.DelphiBuild.Compiler;

type
  IDelphiTestRunner = interface
    ['{9F3A6C2D-1E4B-4D8A-B7C5-3A2E8F1D6B90}']
    function Run(const Request: TBuildRequest): TTestReport;
  end;

  TDelphiTestRunner = class(TInterfacedObject, IDelphiTestRunner)
  private
    FSettings: TDelphiBuildSettings;
    FRunner: IProcessRunner;
    FCompiler: IDelphiCompiler;
    function RunExecutable(const Build: TBuildReport; const Request: TBuildRequest): TTestReport;
  public
    constructor Create(const Settings: TDelphiBuildSettings; const Runner: IProcessRunner; const Compiler: IDelphiCompiler);
    function Run(const Request: TBuildRequest): TTestReport;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  MCPServer.DelphiBuild.CompilerOutput,
  MCPServer.DelphiBuild.TestOutput;

const
  TestArguments = '--hidebanner --exitbehavior:Continue';
  TestCommandLineFormat = '"%s" %s';
  OutputTailLines = 60;
  MillisecondsPerSecond = 1000;

resourcestring
  SDependencyMissing = 'TDelphiTestRunner needs a process runner and a compiler';

constructor TDelphiTestRunner.Create(const Settings: TDelphiBuildSettings; const Runner: IProcessRunner; const Compiler: IDelphiCompiler);
begin
  inherited Create;
  const HasDependencies = Assigned(Runner) and Assigned(Compiler);
  if not HasDependencies then
    raise EDelphiBuildError.Create(SDependencyMissing);

  FSettings := Settings;
  FRunner   := Runner;
  FCompiler := Compiler;
end;

function TDelphiTestRunner.Run(const Request: TBuildRequest): TTestReport;
begin
  const Build = FCompiler.Build(Request);
  if not Build.Succeeded then
  begin
    Result := Default(TTestReport);
    Result.Build := Build;
    Exit;
  end;

  Result := RunExecutable(Build, Request);
end;

function TDelphiTestRunner.RunExecutable(const Build: TBuildReport; const Request: TBuildRequest): TTestReport;
begin
  const ProjectPath = TPath.GetFullPath(Request.ProjectFile);
  const ProjectFolder = TPath.GetDirectoryName(ProjectPath);
  const CommandLine = Format(TestCommandLineFormat, [Build.ExecutablePath, TestArguments]);
  const TimeoutMs = Cardinal(FSettings.TimeoutSeconds) * MillisecondsPerSecond;
  const ProcessResult = FRunner.Run(CommandLine, ProjectFolder, TimeoutMs);
  const Summary = TTestOutputParser.Parse(ProcessResult.Output);

  Result := Default(TTestReport);
  Result.Build      := Build;
  Result.Ran        := True;
  Result.ExitCode   := ProcessResult.ExitCode;
  Result.TimedOut   := ProcessResult.TimedOut;
  Result.DurationMs := ProcessResult.DurationMs;
  Result.Summary    := Summary;

  const AllCountersClean = (Summary.Failed = 0) and (Summary.Errored = 0) and (Summary.Leaked = 0);
  const RanToEnd = (ProcessResult.ExitCode = 0) and not ProcessResult.TimedOut;
  const FoundTests = (Summary.Found > 0);
  Result.Passed := RanToEnd and FoundTests and AllCountersClean and not Summary.HasShutdownLeakReport;

  if not Result.Passed then
    Result.OutputTail := TCompilerOutputParser.Tail(ProcessResult.Output, OutputTailLines);
end;

end.
