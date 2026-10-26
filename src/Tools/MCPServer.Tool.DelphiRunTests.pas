unit MCPServer.Tool.DelphiRunTests;

interface

uses
  MCPServer.Tool.Base,
  MCPServer.Types,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.TestRunner,
  MCPServer.Tool.DelphiBuild.Params;

type
  TDelphiRunTestsOutput = class
  private
    FPassed: Boolean;
    FBuildSucceeded: Boolean;
    FBuildErrors: TArray<TCompilerMessage>;
    FRan: Boolean;
    FTestsFound: Integer;
    FTestsPassed: Integer;
    FTestsFailed: Integer;
    FTestsErrored: Integer;
    FTestsIgnored: Integer;
    FTestsLeaked: Integer;
    FShutdownLeakReport: Boolean;
    FFailedTests: TArray<TFailedTest>;
    FExitCode: Integer;
    FTimedOut: Boolean;
    FDurationMs: Int64;
    FOutputTail: string;
    class function ErrorsOf(const Messages: TArray<TCompilerMessage>): TArray<TCompilerMessage>; static;
  public
    class function FromReport(const Report: TTestReport): TDelphiRunTestsOutput; static;

    [SchemaDescription('True when the test project built, every test passed and nothing leaked')]
    [SchemaName('passed')]
    property Passed: Boolean read FPassed write FPassed;
    [SchemaDescription('True when the test project compiled')]
    [SchemaName('buildSucceeded')]
    property BuildSucceeded: Boolean read FBuildSucceeded write FBuildSucceeded;
    [SchemaDescription('Compiler errors when the build failed')]
    [SchemaName('buildErrors')]
    property BuildErrors: TArray<TCompilerMessage> read FBuildErrors write FBuildErrors;
    [SchemaDescription('True when the test executable was started')]
    [SchemaName('ran')]
    property Ran: Boolean read FRan write FRan;
    [SchemaDescription('Number of tests DUnitX found')]
    [SchemaName('testsFound')]
    property TestsFound: Integer read FTestsFound write FTestsFound;
    [SchemaDescription('Number of tests that passed')]
    [SchemaName('testsPassed')]
    property TestsPassed: Integer read FTestsPassed write FTestsPassed;
    [SchemaDescription('Number of tests that failed an assertion')]
    [SchemaName('testsFailed')]
    property TestsFailed: Integer read FTestsFailed write FTestsFailed;
    [SchemaDescription('Number of tests that raised an unexpected exception')]
    [SchemaName('testsErrored')]
    property TestsErrored: Integer read FTestsErrored write FTestsErrored;
    [SchemaDescription('Number of ignored tests')]
    [SchemaName('testsIgnored')]
    property TestsIgnored: Integer read FTestsIgnored write FTestsIgnored;
    [SchemaDescription('Number of tests DUnitX reported as leaking memory')]
    [SchemaName('testsLeaked')]
    property TestsLeaked: Integer read FTestsLeaked write FTestsLeaked;
    [SchemaDescription('True when the memory manager reported an unexpected memory leak at shutdown')]
    [SchemaName('shutdownLeakReport')]
    property ShutdownLeakReport: Boolean read FShutdownLeakReport write FShutdownLeakReport;
    [SchemaDescription('Full name and message of every failed or errored test')]
    [SchemaName('failedTests')]
    property FailedTests: TArray<TFailedTest> read FFailedTests write FFailedTests;
    [SchemaDescription('Exit code of the test executable')]
    [SchemaName('exitCode')]
    property ExitCode: Integer read FExitCode write FExitCode;
    [SchemaDescription('True when the test run was stopped because it exceeded the time limit')]
    [SchemaName('timedOut')]
    property TimedOut: Boolean read FTimedOut write FTimedOut;
    [SchemaDescription('Duration of the test run in milliseconds')]
    [SchemaName('durationMs')]
    property DurationMs: Int64 read FDurationMs write FDurationMs;
    [SchemaDescription('Last lines of the build or test output when something failed, empty otherwise')]
    [SchemaName('outputTail')]
    property OutputTail: string read FOutputTail write FOutputTail;
  end;

  TDelphiRunTestsTool = class(TMCPToolBase<TDelphiProjectParams, TDelphiRunTestsOutput>)
  private
    FTestRunner: IDelphiTestRunner;
  protected
    function ExecuteWithParams(const Params: TDelphiProjectParams): TDelphiRunTestsOutput; override;
  public
    constructor Create; override;
    constructor CreateWithTestRunner(const TestRunner: IDelphiTestRunner);
  end;

const
  DelphiRunTestsToolName = 'delphi_run_tests';

implementation

uses
  MCPServer.Errors;

resourcestring
  SDelphiRunTestsTitle = 'Build and run Delphi DUnitX tests';
  SDelphiRunTestsDescription = 'Builds a DUnitX console test project (.dpr) with the RAD Studio command-line compiler, ' +
                               'runs it and returns the number of found, passed, failed, errored, ignored and leaking ' +
                               'tests, the name and message of every failed test, and whether the memory manager ' +
                               'reported a leak at shutdown. Use it to run the regression suite after a Delphi change. ' +
                               'Runs the built test executable as the server''s user.';
  SDelphiRunTestsNotConfigured = 'delphi_run_tests was created without a test runner; register it with TDelphiBuildToolRegistration';

class function TDelphiRunTestsOutput.FromReport(const Report: TTestReport): TDelphiRunTestsOutput;
begin
  Result := TDelphiRunTestsOutput.Create;
  Result.Passed             := Report.Passed;
  Result.BuildSucceeded     := Report.Build.Succeeded;
  Result.BuildErrors        := ErrorsOf(Report.Build.Messages);
  Result.Ran                := Report.Ran;
  Result.TestsFound         := Report.Summary.Found;
  Result.TestsPassed        := Report.Summary.Passed;
  Result.TestsFailed        := Report.Summary.Failed;
  Result.TestsErrored       := Report.Summary.Errored;
  Result.TestsIgnored       := Report.Summary.Ignored;
  Result.TestsLeaked        := Report.Summary.Leaked;
  Result.ShutdownLeakReport := Report.Summary.HasShutdownLeakReport;
  Result.FailedTests        := Report.Summary.FailedTests;
  Result.ExitCode           := Integer(Report.ExitCode);
  Result.TimedOut           := Report.TimedOut or Report.Build.TimedOut;
  Result.DurationMs         := Report.Build.DurationMs + Report.DurationMs;
  Result.OutputTail         := Report.OutputTail;

  const BuildFailed = not Report.Build.Succeeded;
  if BuildFailed then
    Result.OutputTail := Report.Build.OutputTail;
end;

class function TDelphiRunTestsOutput.ErrorsOf(const Messages: TArray<TCompilerMessage>): TArray<TCompilerMessage>;
begin
  Result := [];
  for var Message in Messages do
  begin
    const IsError = (Message.Kind in [TCompilerMessageKind.Error, TCompilerMessageKind.Fatal]);
    if IsError then
      Result := Result + [Message];
  end;
end;

constructor TDelphiRunTestsTool.Create;
begin
  inherited Create;
  FName        := DelphiRunTestsToolName;
  FTitle       := SDelphiRunTestsTitle;
  FDescription := SDelphiRunTestsDescription;
end;

constructor TDelphiRunTestsTool.CreateWithTestRunner(const TestRunner: IDelphiTestRunner);
begin
  Create;
  FTestRunner := TestRunner;
end;

function TDelphiRunTestsTool.ExecuteWithParams(const Params: TDelphiProjectParams): TDelphiRunTestsOutput;
begin
  if not Assigned(FTestRunner) then
    raise EMCPToolError.Create(SDelphiRunTestsNotConfigured);

  try
    const Request = Params.ToRequest;
    const Report = FTestRunner.Run(Request);
    Result := TDelphiRunTestsOutput.FromReport(Report);
  except
    on E: EDelphiBuildError do
      raise EMCPToolError.Create(E.Message);
  end;
end;

end.
