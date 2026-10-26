unit MCPServer.Tests.DelphiBuild.TestRunner;

interface

uses
  DUnitX.TestFramework,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.TestRunner,
  MCPServer.Tests.DelphiBuild.FakeRunner;

type
  [TestFixture]
  TDelphiTestRunnerTests = class
  private
    FProject: TFakeProject;
    FFakeRunner: TFakeProcessRunner;
    FTestRunner: IDelphiTestRunner;
    function CreateRequest: TBuildRequest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Run_BuildFails_DoesNotStartTests;
    [Test]
    procedure Run_AllPass_ReportsPassed;
    [Test]
    procedure Run_FailingTests_ReportsFailures;
    [Test]
    procedure Run_ShutdownLeak_ReportsNotPassed;
    [Test]
    procedure Run_NoTestsFound_ReportsNotPassed;
  end;

implementation

uses
  System.SysUtils,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.Compiler;

const
  ProjectName = 'SampleTests';
  FailedBuild = 'SampleTests.dpr(3) Fatal: F2613 Unit ''Missing'' not found.';
  PassingRun = 'Tests Found   : 3'#13#10'Tests Passed  : 3'#13#10'Tests Failed  : 0'#13#10'Tests Errored : 0'#13#10'Tests Leaked  : 0';
  FailingRun = 'Tests Found   : 3'#13#10'Tests Passed  : 2'#13#10'Tests Failed  : 1'#13#10'Tests Errored : 0'#13#10'Tests Leaked  : 0'#13#10#13#10 +
               'Failing Tests'#13#10#13#10'  Sample.Tests.TSampleTests.Add_ReturnsSum'#13#10'  Message: Expected [3] but got [4]'#13#10#13#10;
  LeakingRun = PassingRun + #13#10'Unexpected Memory Leak'#13#10'An unexpected memory leak has occurred.';
  EmptyRun = 'Tests Found   : 0'#13#10'Tests Passed  : 0';

procedure TDelphiTestRunnerTests.Setup;
begin
  FProject := TFakeProject.Create(ProjectName);
  FFakeRunner := TFakeProcessRunner.Create;

  const Settings = FProject.Settings;

  const Compiler: IDelphiCompiler = TDelphiCompiler.Create(Settings, FFakeRunner);
  FTestRunner := TDelphiTestRunner.Create(Settings, FFakeRunner, Compiler);
end;

procedure TDelphiTestRunnerTests.TearDown;
begin
  FTestRunner := nil;
  FFakeRunner := nil;
  FProject.Delete;
end;

function TDelphiTestRunnerTests.CreateRequest: TBuildRequest;
begin
  Result := Default(TBuildRequest);
  Result.ProjectFile := FProject.ProjectFile;
  Result.Config      := TDelphiConfig.Debug;
  Result.Platform    := TDelphiPlatform.Win32;
end;

procedure TDelphiTestRunnerTests.Run_BuildFails_DoesNotStartTests;
begin
  FFakeRunner.Enqueue(FailedBuild, 1);

  const Report = FTestRunner.Run(CreateRequest);

  Assert.IsFalse(Report.Build.Succeeded);
  Assert.IsFalse(Report.Ran);
  Assert.IsFalse(Report.Passed);
  Assert.AreEqual(1, FFakeRunner.RunCount);
end;

procedure TDelphiTestRunnerTests.Run_AllPass_ReportsPassed;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FFakeRunner.Enqueue(PassingRun);

  const Report = FTestRunner.Run(CreateRequest);

  Assert.IsTrue(Report.Ran);
  Assert.IsTrue(Report.Passed);
  Assert.AreEqual(3, Report.Summary.Passed);
  Assert.AreEqual(2, FFakeRunner.RunCount);
  Assert.Contains(FFakeRunner.Runs[1].CommandLine, Format('"%s"', [Report.Build.ExecutablePath]));
  Assert.Contains(FFakeRunner.Runs[1].CommandLine, '--exitbehavior:Continue');
end;

procedure TDelphiTestRunnerTests.Run_FailingTests_ReportsFailures;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FFakeRunner.Enqueue(FailingRun, 1);

  const Report = FTestRunner.Run(CreateRequest);

  Assert.IsTrue(Report.Ran);
  Assert.IsFalse(Report.Passed);
  Assert.AreEqual(1, Report.Summary.Failed);
  Assert.AreEqual('Sample.Tests.TSampleTests.Add_ReturnsSum', Report.Summary.FailedTests[0].Name);
  Assert.Contains(Report.OutputTail, 'Expected [3] but got [4]');
end;

procedure TDelphiTestRunnerTests.Run_ShutdownLeak_ReportsNotPassed;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FFakeRunner.Enqueue(LeakingRun);

  const Report = FTestRunner.Run(CreateRequest);

  Assert.IsTrue(Report.Summary.HasShutdownLeakReport);
  Assert.IsFalse(Report.Passed);
end;

procedure TDelphiTestRunnerTests.Run_NoTestsFound_ReportsNotPassed;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FFakeRunner.Enqueue(EmptyRun);

  const Report = FTestRunner.Run(CreateRequest);

  Assert.IsTrue(Report.Ran);
  Assert.IsFalse(Report.Passed);
end;

end.
