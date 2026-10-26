unit MCPServer.Tests.DelphiBuild.Integration;

interface

uses
  DUnitX.TestFramework,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Settings;

type
  [TestFixture]
  [Category('Integration')]
  TDelphiBuildIntegrationTests = class
  private
    FRoot: string;
    FSettings: TDelphiBuildSettings;
    FCompilerAvailable: Boolean;
    function WriteProject(const FileName: string; const Lines: TArray<string>): string;
    function CreateRequest(const ProjectFile: string; const Platform: TDelphiPlatform): TBuildRequest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    [TestCase('Win32', 'Win32')]
    [TestCase('Win64', 'Win64')]
    procedure Build_ValidProject_ProducesExecutable(const PlatformName: string);
    [Test]
    procedure Build_BrokenProject_ReportsErrorWithLocation;
    [Test]
    procedure RunTests_DUnitXProject_ReportsPassedAndFailed;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  MCPServer.DelphiBuild.ProcessRunner,
  MCPServer.DelphiBuild.Compiler,
  MCPServer.DelphiBuild.TestRunner;

const
  SkipMessage = 'RAD Studio compiler not found, integration test skipped';

procedure TDelphiBuildIntegrationTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(FRoot);

  FSettings := TDelphiBuildSettings.Defaults;
  FSettings.AllowedRoots := [FRoot];
  FSettings.TimeoutSeconds := 120;

  const Dcc32 = FSettings.CompilerPath('dcc32.exe');
  FCompilerAvailable := TFile.Exists(Dcc32);
end;

procedure TDelphiBuildIntegrationTests.TearDown;
begin
  const RootExists = TDirectory.Exists(FRoot);
  if RootExists then
    TDirectory.Delete(FRoot, True);
end;

function TDelphiBuildIntegrationTests.WriteProject(const FileName: string; const Lines: TArray<string>): string;
begin
  Result := TPath.Combine(FRoot, FileName);
  TFile.WriteAllText(Result, string.Join(sLineBreak, Lines), TEncoding.ANSI);
end;

function TDelphiBuildIntegrationTests.CreateRequest(const ProjectFile: string; const Platform: TDelphiPlatform): TBuildRequest;
begin
  Result := Default(TBuildRequest);
  Result.ProjectFile := ProjectFile;
  Result.Config      := TDelphiConfig.Debug;
  Result.Platform    := Platform;
end;

procedure TDelphiBuildIntegrationTests.Build_ValidProject_ProducesExecutable(const PlatformName: string);
begin
  if not FCompilerAvailable then
  begin
    Assert.Pass(SkipMessage);
    Exit;
  end;

  const ProjectFile = WriteProject('Hello.dpr', ['program Hello;', '{$APPTYPE CONSOLE}', 'begin', '  Writeln(''ok'');', 'end.']);
  const Compiler: IDelphiCompiler = TDelphiCompiler.Create(FSettings, TWindowsProcessRunner.Create);

  const Report = Compiler.Build(CreateRequest(ProjectFile, TDelphiPlatform.Parse(PlatformName)));

  Assert.IsTrue(Report.Succeeded, Report.OutputTail);
  Assert.AreEqual(0, Report.ErrorCount);
  Assert.IsTrue(TFile.Exists(Report.ExecutablePath), Report.ExecutablePath);
end;

procedure TDelphiBuildIntegrationTests.Build_BrokenProject_ReportsErrorWithLocation;
begin
  if not FCompilerAvailable then
  begin
    Assert.Pass(SkipMessage);
    Exit;
  end;

  const ProjectFile = WriteProject('Broken.dpr', ['program Broken;', 'begin', '  UndeclaredRoutine;', 'end.']);
  const Compiler: IDelphiCompiler = TDelphiCompiler.Create(FSettings, TWindowsProcessRunner.Create);

  const Report = Compiler.Build(CreateRequest(ProjectFile, TDelphiPlatform.Win32));

  Assert.IsFalse(Report.Succeeded);
  Assert.IsTrue(Report.ErrorCount >= 1);
  const FirstError = Report.Messages[0];
  Assert.AreEqual<TCompilerMessageKind>(TCompilerMessageKind.Error, FirstError.Kind);
  Assert.AreEqual('E2003', FirstError.Code);
  Assert.AreEqual(3, FirstError.Line);
  Assert.Contains(FirstError.FileName, 'Broken.dpr');
end;

procedure TDelphiBuildIntegrationTests.RunTests_DUnitXProject_ReportsPassedAndFailed;
begin
  if not FCompilerAvailable then
  begin
    Assert.Pass(SkipMessage);
    Exit;
  end;

  WriteProject('Sample.Fixture.pas', [
    'unit Sample.Fixture;', 'interface', 'uses DUnitX.TestFramework;', 'type',
    '  [TestFixture]', '  TSampleTests = class', '  public',
    '    [Test] procedure Add_ReturnsSum;', '    [Test] procedure Subtract_ReturnsDifference;', '  end;',
    'implementation',
    'procedure TSampleTests.Add_ReturnsSum; begin Assert.AreEqual(4, 2 + 2); end;',
    'procedure TSampleTests.Subtract_ReturnsDifference; begin Assert.AreEqual(1, 3 - 1); end;',
    'end.']);
  const ProjectFile = WriteProject('SampleTests.dpr', [
    'program SampleTests;', '{$APPTYPE CONSOLE}', '{$STRONGLINKTYPES ON}',
    'uses System.SysUtils, DUnitX.TestFramework, DUnitX.Loggers.Console, Sample.Fixture in ''Sample.Fixture.pas'';',
    'begin',
    '  const Runner = TDUnitX.CreateRunner;',
    '  Runner.UseRTTI := True;',
    '  Runner.AddLogger(TDUnitXConsoleLogger.Create(True));',
    '  const Results = Runner.Execute;',
    '  System.ExitCode := Ord(not Results.AllPassed);',
    'end.']);

  const Runner: IProcessRunner = TWindowsProcessRunner.Create;
  const Compiler: IDelphiCompiler = TDelphiCompiler.Create(FSettings, Runner);
  const TestRunner: IDelphiTestRunner = TDelphiTestRunner.Create(FSettings, Runner, Compiler);

  const Report = TestRunner.Run(CreateRequest(ProjectFile, TDelphiPlatform.Win32));

  Assert.IsTrue(Report.Build.Succeeded, Report.Build.OutputTail);
  Assert.IsTrue(Report.Ran);
  Assert.IsFalse(Report.Passed);
  Assert.AreEqual(2, Report.Summary.Found);
  Assert.AreEqual(1, Report.Summary.Passed);
  Assert.AreEqual(1, Report.Summary.Failed);
  Assert.AreEqual('Sample.Fixture.TSampleTests.Subtract_ReturnsDifference', Report.Summary.FailedTests[0].Name);
  Assert.Contains(Report.Summary.FailedTests[0].Message, 'Expected [1] but got [2]');
end;

end.
