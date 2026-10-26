unit MCPServer.Tests.DelphiBuild.Compiler;

interface

uses
  DUnitX.TestFramework,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.Compiler,
  MCPServer.Tests.DelphiBuild.FakeRunner;

type
  [TestFixture]
  TDelphiBuildSettingsTests = class
  private
    FFolder: string;
    function SettingsFile: string;
    function WriteSettings(const Lines: TArray<string>): TDelphiBuildSettings;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadFromFile_MissingFile_IsDisabledWithoutRoots;
    [Test]
    procedure LoadFromFile_EnabledWithRoots_IsConfigured;
    [Test]
    procedure LoadFromFile_EnabledWithoutRoots_IsNotConfigured;
    [Test]
    [TestCase('BelowMinimum', '1,10')]
    [TestCase('Negative', '-5,10')]
    [TestCase('AboveMaximum', '999999,3600')]
    [TestCase('InRange', '120,120')]
    procedure ClampTimeout_KeepsLimits(const Seconds: Integer; const Expected: Integer);
    [Test]
    procedure IsAllowed_InsideRootRootItselfAndTrailingSeparator;
    [Test]
    procedure IsAllowed_PrefixSiblingAndParentEscape_AreRefused;
    [Test]
    procedure IsAllowed_JunctionPointingOutside_IsRefused;
    [Test]
    procedure IsAllowed_NoRoots_RefusesEverything;
  end;

  [TestFixture]
  TDelphiCompilerTests = class
  private
    FProject: TFakeProject;
    FFakeRunner: TFakeProcessRunner;
    FCompiler: IDelphiCompiler;
    function CreateRequest: TBuildRequest;
    function CommandLineOf(const Request: TBuildRequest): string;
    procedure AssertRefused(const Request: TBuildRequest);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Build_Win64Release_UsesDcc64AndReleaseSwitches;
    [Test]
    procedure Build_Debug_UsesDebugSwitchesAndOutputFolder;
    [Test]
    procedure Build_SearchPathWithTrailingSeparator_IsQuotedWithoutIt;
    [Test]
    procedure Build_RunsInProjectFolderWithTimeout;
    [Test]
    procedure Build_CleanOutput_ReportsSuccessAndExecutable;
    [Test]
    procedure Build_ErrorsInOutput_ReportsFailureWithMessages;
    [Test]
    procedure Build_TimedOut_ReportsFailure;
    [Test]
    procedure Build_ProjectOutsideRoots_IsRefused;
    [Test]
    procedure Build_NonDprProject_IsRefused;
    [Test]
    procedure Build_MissingProject_IsRefused;
    [Test]
    procedure Build_SearchPathOutsideRoots_IsRefused;
    [Test]
    procedure Build_MissingCompiler_IsRefused;
    [Test]
    procedure Create_WithoutRunner_RaisesBuildError;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  MCPServer.DelphiBuild.ProcessRunner;

const
  ProjectName = 'Sample';
  TimeoutSeconds = 17;
  SettingsFileName = 'settings.ini';
  WorkRoot = 'C:\Work';
  ErrorOutput = 'C:\Work\Main.pas(3) Error: E2003 Undeclared identifier: ''Foo'''#13#10 +
                'Main.pas(4) Warning: W1036 Variable ''X'' might not have been initialized'#13#10 +
                'Sample.dpr(2) Fatal: F2063 Could not compile used unit ''Main.pas''';
  JunctionCommandFormat = 'cmd.exe /c mklink /J "%s" "%s"';
  JunctionTimeoutMs = 10000;

procedure TDelphiBuildSettingsTests.Setup;
begin
  const TempFolder = TPath.GetTempPath;
  const UniqueName = TPath.GetGUIDFileName;
  FFolder := TPath.Combine(TempFolder, UniqueName);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TDelphiBuildSettingsTests.TearDown;
begin
  const FolderExists = TDirectory.Exists(FFolder);
  if FolderExists then
    TDirectory.Delete(FFolder, True);
end;

function TDelphiBuildSettingsTests.SettingsFile: string;
begin
  Result := TPath.Combine(FFolder, SettingsFileName);
end;

function TDelphiBuildSettingsTests.WriteSettings(const Lines: TArray<string>): TDelphiBuildSettings;
begin
  const Content = string.Join(sLineBreak, Lines);
  TFile.WriteAllText(SettingsFile, Content);
  Result := TDelphiBuildSettings.LoadFromFile(SettingsFile);
end;

procedure TDelphiBuildSettingsTests.LoadFromFile_MissingFile_IsDisabledWithoutRoots;
begin
  const Settings = TDelphiBuildSettings.LoadFromFile(SettingsFile);

  Assert.IsFalse(Settings.Enabled);
  Assert.AreEqual<NativeInt>(0, Length(Settings.AllowedRoots));
  Assert.IsFalse(Settings.IsConfigured);
  Assert.AreEqual(DefaultBdsPath, Settings.BdsPath);
  Assert.AreEqual(DefaultTimeoutSeconds, Settings.TimeoutSeconds);
end;

procedure TDelphiBuildSettingsTests.LoadFromFile_EnabledWithRoots_IsConfigured;
begin
  const Settings = WriteSettings(['[DelphiBuild]', 'Enabled=1', 'BdsPath=D:\Studio\23.0',
                                  'AllowedRoots=C:\Work; D:\Projects', 'TimeoutSeconds=42']);

  Assert.IsTrue(Settings.IsConfigured);
  Assert.AreEqual('D:\Studio\23.0', Settings.BdsPath);
  Assert.AreEqual(42, Settings.TimeoutSeconds);
  Assert.AreEqual<NativeInt>(2, Length(Settings.AllowedRoots));
  Assert.AreEqual(WorkRoot, Settings.AllowedRoots[0]);
  Assert.AreEqual('D:\Projects', Settings.AllowedRoots[1]);
end;

procedure TDelphiBuildSettingsTests.LoadFromFile_EnabledWithoutRoots_IsNotConfigured;
begin
  const Settings = WriteSettings(['[DelphiBuild]', 'Enabled=1']);

  Assert.IsTrue(Settings.Enabled);
  Assert.IsFalse(Settings.IsConfigured);
end;

procedure TDelphiBuildSettingsTests.ClampTimeout_KeepsLimits(const Seconds: Integer; const Expected: Integer);
begin
  Assert.AreEqual(Expected, TDelphiBuildSettings.ClampTimeout(Seconds));
end;

procedure TDelphiBuildSettingsTests.IsAllowed_InsideRootRootItselfAndTrailingSeparator;
begin
  var Settings := TDelphiBuildSettings.Defaults;
  Settings.AllowedRoots := [IncludeTrailingPathDelimiter(FFolder)];

  Assert.IsTrue(Settings.IsAllowed(TPath.Combine(FFolder, 'App\App.dpr')));
  Assert.IsTrue(Settings.IsAllowed(FFolder));
end;

procedure TDelphiBuildSettingsTests.IsAllowed_PrefixSiblingAndParentEscape_AreRefused;
begin
  var Settings := TDelphiBuildSettings.Defaults;
  Settings.AllowedRoots := [WorkRoot];

  Assert.IsTrue(Settings.IsAllowed('C:\Work\App\App.dpr'));
  Assert.IsFalse(Settings.IsAllowed('C:\Workshop\App.dpr'));
  Assert.IsFalse(Settings.IsAllowed('C:\Work\..\Windows\App.dpr'));
end;

procedure TDelphiBuildSettingsTests.IsAllowed_JunctionPointingOutside_IsRefused;
begin
  const Root = TPath.Combine(FFolder, 'Root');
  const Outside = TPath.Combine(FFolder, 'Outside');
  const Junction = TPath.Combine(Root, 'Link');
  TDirectory.CreateDirectory(Root);
  TDirectory.CreateDirectory(Outside);
  const Runner: IProcessRunner = TWindowsProcessRunner.Create;
  const JunctionCommand = Format(JunctionCommandFormat, [Junction, Outside]);
  const Created = Runner.Run(JunctionCommand, FFolder, JunctionTimeoutMs);
  try
    Assert.AreEqual<Cardinal>(0, Created.ExitCode, Created.Output);

    var Settings := TDelphiBuildSettings.Defaults;
    Settings.AllowedRoots := [Root];

    Assert.IsTrue(Settings.IsAllowed(TPath.Combine(Root, 'App.dpr')));
    Assert.IsFalse(Settings.IsAllowed(TPath.Combine(Junction, 'App.dpr')));
  finally
    RemoveDir(Junction);
  end;
end;

procedure TDelphiBuildSettingsTests.IsAllowed_NoRoots_RefusesEverything;
begin
  const Settings = TDelphiBuildSettings.Defaults;

  Assert.IsFalse(Settings.IsAllowed(FFolder));
end;

procedure TDelphiCompilerTests.Setup;
begin
  FProject := TFakeProject.Create(ProjectName);
  FFakeRunner := TFakeProcessRunner.Create;

  var Settings := FProject.Settings;
  Settings.TimeoutSeconds := TimeoutSeconds;
  FCompiler := TDelphiCompiler.Create(Settings, FFakeRunner);
end;

procedure TDelphiCompilerTests.TearDown;
begin
  FCompiler := nil;
  FFakeRunner := nil;
  FProject.Delete;
end;

function TDelphiCompilerTests.CreateRequest: TBuildRequest;
begin
  Result := Default(TBuildRequest);
  Result.ProjectFile := FProject.ProjectFile;
  Result.Config      := TDelphiConfig.Debug;
  Result.Platform    := TDelphiPlatform.Win32;
end;

function TDelphiCompilerTests.CommandLineOf(const Request: TBuildRequest): string;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FCompiler.Build(Request);
  Result := FFakeRunner.Runs[0].CommandLine;
end;

procedure TDelphiCompilerTests.AssertRefused(const Request: TBuildRequest);
begin
  Assert.WillRaise(
    procedure
    begin
      FCompiler.Build(Request);
    end,
    EDelphiBuildError);
  Assert.AreEqual(0, FFakeRunner.RunCount);
end;

procedure TDelphiCompilerTests.Build_Win64Release_UsesDcc64AndReleaseSwitches;
begin
  var Request := CreateRequest;
  Request.Config   := TDelphiConfig.Release;
  Request.Platform := TDelphiPlatform.Win64;

  const CommandLine = CommandLineOf(Request);

  const BinFolder = TPath.Combine(FProject.BdsPath, CompilerFolder);
  Assert.Contains(CommandLine, TPath.Combine(BinFolder, Dcc64FileName), False);
  Assert.Contains(CommandLine, '-$O+', False);
  Assert.Contains(CommandLine, '-DRELEASE', False);
  Assert.Contains(CommandLine, 'lib\Win64\release', False);
end;

procedure TDelphiCompilerTests.Build_Debug_UsesDebugSwitchesAndOutputFolder;
begin
  const Request = CreateRequest;

  const CommandLine = CommandLineOf(Request);

  const OutputFolder = TDelphiCompiler.OutputFolder(Request);
  const ExpectedOutput = Format('-E"%s"', [OutputFolder]);
  const ExpectedProject = Format('"%s"', [FProject.ProjectFile]);
  const DcuFolder = TPath.Combine(OutputFolder, 'DCU');
  Assert.Contains(CommandLine, Dcc32FileName, False);
  Assert.Contains(CommandLine, '-$O- -$W+ -$R+ -$Q+', False);
  Assert.Contains(CommandLine, '-DDEBUG', False);
  Assert.Contains(CommandLine, '--no-config -B -Q', False);
  Assert.Contains(CommandLine, ExpectedOutput, False);
  Assert.EndsWith(ExpectedProject, CommandLine, False);
  Assert.IsTrue(TDirectory.Exists(DcuFolder));
end;

procedure TDelphiCompilerTests.Build_SearchPathWithTrailingSeparator_IsQuotedWithoutIt;
begin
  const SearchFolder = TPath.GetDirectoryName(FProject.ProjectFile);
  var Request := CreateRequest;
  Request.SearchPaths := [IncludeTrailingPathDelimiter(SearchFolder)];

  const CommandLine = CommandLineOf(Request);

  const Expected = Format('"%s"', [SearchFolder]);
  const Broken = Format('"%s\"', [SearchFolder]);
  Assert.Contains(CommandLine, Expected, False);
  Assert.DoesNotContain(CommandLine, Broken, False);
end;

procedure TDelphiCompilerTests.Build_RunsInProjectFolderWithTimeout;
begin
  CommandLineOf(CreateRequest);

  const ProjectFolder = TPath.GetDirectoryName(FProject.ProjectFile);
  const ExpectedTimeoutMs = Cardinal(TimeoutSeconds * MillisecondsPerSecond);
  Assert.AreEqual(ProjectFolder, FFakeRunner.Runs[0].WorkingDirectory);
  Assert.AreEqual<Cardinal>(ExpectedTimeoutMs, FFakeRunner.Runs[0].TimeoutMs);
end;

procedure TDelphiCompilerTests.Build_CleanOutput_ReportsSuccessAndExecutable;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  const Request = CreateRequest;

  const Report = FCompiler.Build(Request);

  Assert.IsTrue(Report.Succeeded);
  Assert.AreEqual(0, Report.ErrorCount);
  Assert.AreEqual(TDelphiCompiler.ExecutablePath(Request), Report.ExecutablePath);
  Assert.EndsWith('build\Win32\Debug\Sample.exe', Report.ExecutablePath, False);
  Assert.AreEqual('', Report.OutputTail);
end;

procedure TDelphiCompilerTests.Build_ErrorsInOutput_ReportsFailureWithMessages;
begin
  FFakeRunner.Enqueue(ErrorOutput, 1);

  const Report = FCompiler.Build(CreateRequest);

  Assert.IsFalse(Report.Succeeded);
  Assert.AreEqual(2, Report.ErrorCount);
  Assert.AreEqual(1, Report.WarningCount);
  Assert.AreEqual<NativeInt>(3, Length(Report.Messages));
  Assert.AreEqual('', Report.ExecutablePath);
  Assert.Contains(Report.OutputTail, 'F2063', False);
end;

procedure TDelphiCompilerTests.Build_TimedOut_ReportsFailure;
begin
  FFakeRunner.Enqueue('', 1, True);

  const Report = FCompiler.Build(CreateRequest);

  Assert.IsFalse(Report.Succeeded);
  Assert.IsTrue(Report.TimedOut);
end;

procedure TDelphiCompilerTests.Build_ProjectOutsideRoots_IsRefused;
begin
  var Request := CreateRequest;
  Request.ProjectFile := TPath.Combine(TPath.GetTempPath, 'Elsewhere.dpr');

  AssertRefused(Request);
end;

procedure TDelphiCompilerTests.Build_NonDprProject_IsRefused;
begin
  const ScriptFile = TPath.ChangeExtension(FProject.ProjectFile, '.bat');
  TFile.WriteAllText(ScriptFile, 'del *.*');
  var Request := CreateRequest;
  Request.ProjectFile := ScriptFile;

  AssertRefused(Request);
end;

procedure TDelphiCompilerTests.Build_MissingProject_IsRefused;
begin
  var Request := CreateRequest;
  Request.ProjectFile := TPath.ChangeExtension(FProject.ProjectFile, '.missing.dpr');

  AssertRefused(Request);
end;

procedure TDelphiCompilerTests.Build_SearchPathOutsideRoots_IsRefused;
begin
  var Request := CreateRequest;
  Request.SearchPaths := [TPath.GetTempPath];

  AssertRefused(Request);
end;

procedure TDelphiCompilerTests.Build_MissingCompiler_IsRefused;
begin
  const BinFolder = TPath.Combine(FProject.BdsPath, CompilerFolder);
  TFile.Delete(TPath.Combine(BinFolder, Dcc32FileName));

  AssertRefused(CreateRequest);
end;

procedure TDelphiCompilerTests.Create_WithoutRunner_RaisesBuildError;
begin
  const Settings = FProject.Settings;

  Assert.WillRaise(
    procedure
    begin
      TDelphiCompiler.Create(Settings, nil).Free;
    end,
    EDelphiBuildError);
end;

end.
