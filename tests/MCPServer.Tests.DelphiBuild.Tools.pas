unit MCPServer.Tests.DelphiBuild.Tools;

interface

uses
  DUnitX.TestFramework,
  MCPServer.Tool.Base,
  MCPServer.Tests.DelphiBuild.FakeRunner;

type
  [TestFixture]
  TDelphiBuildToolTests = class
  private
    FProject: TFakeProject;
    FFakeRunner: TFakeProcessRunner;
    FBuildTool: IMCPTool;
    FTestTool: IMCPTool;
    function Call(const Tool: IMCPTool; const ArgumentsJson: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BuildTool_NameAndSchema_DescribeTheProject;
    [Test]
    procedure BuildTool_OutputSchema_ListsMessages;
    [Test]
    procedure BuildTool_Call_ReturnsStructuredReport;
    [Test]
    procedure BuildTool_DefaultsToDebugWin32;
    [Test]
    procedure BuildTool_UnknownPlatform_RaisesToolError;
    [Test]
    procedure BuildTool_ProjectOutsideRoots_RaisesToolError;
    [Test]
    procedure TestTool_Call_ReturnsCountersAndFailedTests;
    [Test]
    procedure Tools_CreatedWithoutDependencies_RaiseToolError;
    [Test]
    procedure Registration_NotConfigured_RegistersNothing;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Rtti,
  MCPServer.Errors,
  MCPServer.DelphiBuild.Settings,
  MCPServer.DelphiBuild.Compiler,
  MCPServer.DelphiBuild.TestRunner,
  MCPServer.Tool.DelphiBuild,
  MCPServer.Tool.DelphiRunTests,
  MCPServer.Registration,
  MCPServer.DelphiBuild.Registration;

const
  ProjectName = 'Sample';
  ErrorBuild = 'C:\Work\Main.pas(3) Error: E2003 Undeclared identifier: ''Foo''';
  FailingRun = 'Tests Found   : 2'#13#10'Tests Passed  : 1'#13#10'Tests Failed  : 1'#13#10'Tests Errored : 0'#13#10'Tests Leaked  : 0'#13#10#13#10 +
               'Failing Tests'#13#10#13#10'  Sample.Tests.TSampleTests.Add_ReturnsSum'#13#10'  Message: Expected [3] but got [4]'#13#10#13#10;

procedure TDelphiBuildToolTests.Setup;
begin
  FProject := TFakeProject.Create(ProjectName);
  FFakeRunner := TFakeProcessRunner.Create;

  const Settings = FProject.Settings;

  const Compiler: IDelphiCompiler = TDelphiCompiler.Create(Settings, FFakeRunner);
  const TestRunner: IDelphiTestRunner = TDelphiTestRunner.Create(Settings, FFakeRunner, Compiler);
  FBuildTool := TDelphiBuildTool.CreateWithCompiler(Compiler);
  FTestTool := TDelphiRunTestsTool.CreateWithTestRunner(TestRunner);
end;

procedure TDelphiBuildToolTests.TearDown;
begin
  FBuildTool := nil;
  FTestTool := nil;
  FFakeRunner := nil;
  FProject.Delete;
end;

function TDelphiBuildToolTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): string;
begin
  const Arguments = TJSONObject.ParseJSONValue(ArgumentsJson) as TJSONObject;
  try
    const Value = Tool.Execute(Arguments);
    const Json = Value.AsType<TJSONObject>;
    try
      Result := Json.ToJSON;
    finally
      Json.Free;
    end;
  finally
    Arguments.Free;
  end;
end;

procedure TDelphiBuildToolTests.BuildTool_NameAndSchema_DescribeTheProject;
begin
  Assert.AreEqual(DelphiBuildToolName, FBuildTool.Name);
  Assert.AreEqual(DelphiRunTestsToolName, FTestTool.Name);

  const Schema = FBuildTool.InputSchema;
  try
    const SchemaJson = Schema.ToJSON;
    Assert.Contains(SchemaJson, '"project"', False);
    Assert.Contains(SchemaJson, '"Release"', False);
    Assert.Contains(SchemaJson, '"Win64"', False);
    Assert.Contains(SchemaJson, '"required":["project"]', False);
  finally
    Schema.Free;
  end;
end;

procedure TDelphiBuildToolTests.BuildTool_OutputSchema_ListsMessages;
begin
  const Schema = FBuildTool.OutputSchema;
  try
    const SchemaJson = Schema.ToJSON;
    Assert.Contains(SchemaJson, '"messages"', False);
    Assert.Contains(SchemaJson, '"executablePath"', False);
  finally
    Schema.Free;
  end;
end;

procedure TDelphiBuildToolTests.BuildTool_Call_ReturnsStructuredReport;
begin
  FFakeRunner.Enqueue(ErrorBuild, 1);
  const Arguments = Format('{"project":"%s","config":"Release","platform":"Win64"}', [FProject.JsonProjectFile]);

  const Json = Call(FBuildTool, Arguments);

  Assert.Contains(Json, '"succeeded":false', False);
  Assert.Contains(Json, '"errorCount":1', False);
  Assert.Contains(Json, '"code":"E2003"', False);
  Assert.Contains(Json, '"kind":"Error"', False);
  Assert.Contains(Json, '"line":3', False);
  Assert.Contains(FFakeRunner.Runs[0].CommandLine, 'dcc64.exe');
end;

procedure TDelphiBuildToolTests.BuildTool_DefaultsToDebugWin32;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  const Arguments = Format('{"project":"%s"}', [FProject.JsonProjectFile]);

  const Json = Call(FBuildTool, Arguments);

  Assert.Contains(Json, '"succeeded":true', False);
  Assert.Contains(FFakeRunner.Runs[0].CommandLine, 'dcc32.exe');
  Assert.Contains(FFakeRunner.Runs[0].CommandLine, '-DDEBUG');
end;

procedure TDelphiBuildToolTests.BuildTool_UnknownPlatform_RaisesToolError;
begin
  const Arguments = Format('{"project":"%s","platform":"Linux64"}', [FProject.JsonProjectFile]);

  Assert.WillRaise(
    procedure
    begin
      Call(FBuildTool, Arguments);
    end,
    EMCPToolError);
end;

procedure TDelphiBuildToolTests.BuildTool_ProjectOutsideRoots_RaisesToolError;
begin
  Assert.WillRaise(
    procedure
    begin
      Call(FBuildTool, '{"project":"C:\\Windows\\System32\\Evil.dpr"}');
    end,
    EMCPToolError);
  Assert.AreEqual(0, FFakeRunner.RunCount);
end;

procedure TDelphiBuildToolTests.TestTool_Call_ReturnsCountersAndFailedTests;
begin
  FFakeRunner.Enqueue(CleanCompilerOutput);
  FFakeRunner.Enqueue(FailingRun, 1);
  const Arguments = Format('{"project":"%s"}', [FProject.JsonProjectFile]);

  const Json = Call(FTestTool, Arguments);

  Assert.Contains(Json, '"passed":false', False);
  Assert.Contains(Json, '"buildSucceeded":true', False);
  Assert.Contains(Json, '"testsFound":2', False);
  Assert.Contains(Json, '"testsFailed":1', False);
  Assert.Contains(Json, '"name":"Sample.Tests.TSampleTests.Add_ReturnsSum"', False);
  Assert.Contains(Json, 'Expected [3] but got [4]', False);
end;

procedure TDelphiBuildToolTests.Tools_CreatedWithoutDependencies_RaiseToolError;
begin
  const BareBuildTool: IMCPTool = TDelphiBuildTool.Create;
  const BareTestTool: IMCPTool = TDelphiRunTestsTool.Create;
  const Arguments = Format('{"project":"%s"}', [FProject.JsonProjectFile]);

  Assert.WillRaise(
    procedure
    begin
      Call(BareBuildTool, Arguments);
    end,
    EMCPToolError);
  Assert.WillRaise(
    procedure
    begin
      Call(BareTestTool, Arguments);
    end,
    EMCPToolError);
end;

procedure TDelphiBuildToolTests.Registration_NotConfigured_RegistersNothing;
begin
  var Settings := FProject.Settings;
  Settings.Enabled := False;

  const Registered = TDelphiBuildToolRegistration.RegisterTools(Settings);

  Assert.IsFalse(Registered);
  Assert.IsFalse(TMCPRegistry.HasTool(DelphiBuildToolName));
  Assert.IsFalse(TMCPRegistry.HasTool(DelphiRunTestsToolName));
end;

end.
