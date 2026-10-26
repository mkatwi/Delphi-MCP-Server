unit MCPServer.Tests.DelphiBuild.Parsers;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerOutputParserTests = class
  public
    [Test]
    procedure Parse_ErrorWithFileAndLine_ReadsAllFields;
    [Test]
    procedure Parse_HintWithoutLocation_ReadsCodeAndText;
    [Test]
    procedure Parse_FatalWithoutCode_ReadsText;
    [Test]
    procedure Parse_SummaryAndBannerLines_AreIgnored;
    [Test]
    procedure Parse_PathWithSpacesAndParentheses_ReadsFileAndLine;
    [Test]
    procedure CountOf_CountsPerKind;
    [Test]
    procedure Tail_ReturnsLastLines;
  end;

  [TestFixture]
  TTestOutputParserTests = class
  public
    [Test]
    procedure Parse_PassingRun_ReadsCounters;
    [Test]
    procedure Parse_FailingRun_ReadsFailedTestsWithMessages;
    [Test]
    procedure Parse_ErroredTestWithMultilineMessage_JoinsMessageLines;
    [Test]
    procedure Parse_TestCaseNameWithSpaces_KeepsTheTest;
    [Test]
    procedure Parse_ShutdownLeakReport_IsDetected;
    [Test]
    procedure Parse_EmptyOutput_ReturnsZeroes;
  end;

implementation

uses
  System.SysUtils,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.CompilerOutput,
  MCPServer.DelphiBuild.TestOutput;

const
  CompilerOutput =
    'Embarcadero Delphi for Win64 compiler version 37.0'#13#10 +
    'Copyright (c) 1983,2026 Embarcadero Technologies, Inc.'#13#10 +
    'Hint: H2675 Directory not found: src\Libraries'#13#10 +
    'C:\Work\App\Main.pas(194) Error: E2003 Undeclared identifier: ''Foo'''#13#10 +
    'C:\Work\Lib\TaurusTLS.pas(4828) Warning: W1060 Explicit string cast with potential data loss'#13#10 +
    'Main.pas(12) Warning: W1036 Variable ''X'' might not have been initialized'#13#10 +
    'App.dpr(5) Fatal: F2063 Could not compile used unit ''Main.pas'''#13#10 +
    '842 lines, 0.17 seconds, 3698716 bytes code, 64344 bytes data.'#13#10;

  PassingTestOutput =
    'DUnitX - [App.Tests.exe] - Starting Tests.'#13#10#13#10 +
    '...........'#13#10#13#10 +
    'Tests Found   : 11'#13#10 +
    'Tests Ignored : 1'#13#10 +
    'Tests Passed  : 10'#13#10 +
    'Tests Leaked  : 0'#13#10 +
    'Tests Failed  : 0'#13#10 +
    'Tests Errored : 0'#13#10;

  FailingTestOutput =
    'Tests Found   : 33'#13#10 +
    'Tests Ignored : 0'#13#10 +
    'Tests Passed  : 31'#13#10 +
    'Tests Leaked  : 0'#13#10 +
    'Tests Failed  : 2'#13#10 +
    'Tests Errored : 0'#13#10 +
    #13#10 +
    'Failing Tests'#13#10 +
    #13#10 +
    '  App.Service.Tests.TOrderServiceTests.Load_WhenRepositoryFails_KeepsCurrentOrders.Halfway'#13#10 +
    '  Message: Expected [1] but got [2]'#13#10 +
    #13#10 +
    '  App.Repository.Tests.TRepositoryTests.SaveAll_WithDuplicateId_KeepsPreviousData'#13#10 +
    '  Message: Expected [Acme] but got [Globex] '#13#10 +
    #13#10#13#10;

  ErroredTestOutput =
    'Tests Found   : 1'#13#10 +
    'Tests Errored : 1'#13#10 +
    #13#10 +
    'Tests With Errors'#13#10 +
    #13#10 +
    '  App.Tests.TImportTests.Import_ReadsFile'#13#10 +
    '  Message: Cannot open file "C:\x.csv".'#13#10 +
    'The system cannot find the file specified'#13#10 +
    #13#10;

procedure TCompilerOutputParserTests.Parse_ErrorWithFileAndLine_ReadsAllFields;
begin
  const Messages = TCompilerOutputParser.Parse(CompilerOutput);

  const Error = Messages[1];
  Assert.AreEqual<TCompilerMessageKind>(TCompilerMessageKind.Error, Error.Kind);
  Assert.AreEqual('E2003', Error.Code);
  Assert.AreEqual('C:\Work\App\Main.pas', Error.FileName);
  Assert.AreEqual(194, Error.Line);
  Assert.AreEqual('Undeclared identifier: ''Foo''', Error.Text);
end;

procedure TCompilerOutputParserTests.Parse_HintWithoutLocation_ReadsCodeAndText;
begin
  const Messages = TCompilerOutputParser.Parse(CompilerOutput);

  const Hint = Messages[0];
  Assert.AreEqual<TCompilerMessageKind>(TCompilerMessageKind.Hint, Hint.Kind);
  Assert.AreEqual('H2675', Hint.Code);
  Assert.AreEqual('', Hint.FileName);
  Assert.AreEqual(0, Hint.Line);
  Assert.AreEqual('Directory not found: src\Libraries', Hint.Text);
end;

procedure TCompilerOutputParserTests.Parse_FatalWithoutCode_ReadsText;
begin
  const Messages = TCompilerOutputParser.Parse('Fatal: Could not find the compiler configuration');

  Assert.AreEqual<NativeInt>(1, Length(Messages));
  Assert.AreEqual<TCompilerMessageKind>(TCompilerMessageKind.Fatal, Messages[0].Kind);
  Assert.AreEqual('', Messages[0].Code);
  Assert.AreEqual('Could not find the compiler configuration', Messages[0].Text);
end;

procedure TCompilerOutputParserTests.Parse_SummaryAndBannerLines_AreIgnored;
begin
  const Messages = TCompilerOutputParser.Parse(CompilerOutput);

  Assert.AreEqual<NativeInt>(5, Length(Messages));
end;

procedure TCompilerOutputParserTests.Parse_PathWithSpacesAndParentheses_ReadsFileAndLine;
begin
  const Messages = TCompilerOutputParser.Parse('C:\Program Files (x86)\My App (old)\Main.pas(12) Warning: W1036 Variable ''X'' might not have been initialized');

  Assert.AreEqual<NativeInt>(1, Length(Messages));
  Assert.AreEqual('C:\Program Files (x86)\My App (old)\Main.pas', Messages[0].FileName);
  Assert.AreEqual(12, Messages[0].Line);
  Assert.AreEqual('W1036', Messages[0].Code);
end;

procedure TCompilerOutputParserTests.CountOf_CountsPerKind;
begin
  const Messages = TCompilerOutputParser.Parse(CompilerOutput);

  Assert.AreEqual(1, TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Hint));
  Assert.AreEqual(2, TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Warning));
  Assert.AreEqual(1, TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Error));
  Assert.AreEqual(1, TCompilerOutputParser.CountOf(Messages, TCompilerMessageKind.Fatal));
end;

procedure TCompilerOutputParserTests.Tail_ReturnsLastLines;
begin
  const Tail = TCompilerOutputParser.Tail(CompilerOutput, 2);

  const Expected = Format('%s%s%s', ['App.dpr(5) Fatal: F2063 Could not compile used unit ''Main.pas''',
                                     sLineBreak,
                                     '842 lines, 0.17 seconds, 3698716 bytes code, 64344 bytes data.']);
  Assert.AreEqual(Expected, Tail);
end;

procedure TTestOutputParserTests.Parse_PassingRun_ReadsCounters;
begin
  const Summary = TTestOutputParser.Parse(PassingTestOutput);

  Assert.AreEqual(11, Summary.Found);
  Assert.AreEqual(1, Summary.Ignored);
  Assert.AreEqual(10, Summary.Passed);
  Assert.AreEqual(0, Summary.Leaked);
  Assert.AreEqual(0, Summary.Failed);
  Assert.AreEqual(0, Summary.Errored);
  Assert.AreEqual<NativeInt>(0, Length(Summary.FailedTests));
  Assert.IsFalse(Summary.HasShutdownLeakReport);
end;

procedure TTestOutputParserTests.Parse_FailingRun_ReadsFailedTestsWithMessages;
begin
  const Summary = TTestOutputParser.Parse(FailingTestOutput);

  Assert.AreEqual(2, Summary.Failed);
  Assert.AreEqual<NativeInt>(2, Length(Summary.FailedTests));
  Assert.AreEqual('App.Service.Tests.TOrderServiceTests.Load_WhenRepositoryFails_KeepsCurrentOrders.Halfway', Summary.FailedTests[0].Name);
  Assert.AreEqual('Expected [1] but got [2]', Summary.FailedTests[0].Message);
  Assert.AreEqual('Expected [Acme] but got [Globex]', Summary.FailedTests[1].Message);
end;

procedure TTestOutputParserTests.Parse_ErroredTestWithMultilineMessage_JoinsMessageLines;
begin
  const Summary = TTestOutputParser.Parse(ErroredTestOutput);

  Assert.AreEqual(1, Summary.Errored);
  Assert.AreEqual<NativeInt>(1, Length(Summary.FailedTests));
  const Expected = Format('%s%s%s', ['Cannot open file "C:\x.csv".', sLineBreak, 'The system cannot find the file specified']);
  Assert.AreEqual(Expected, Summary.FailedTests[0].Message);
end;

procedure TTestOutputParserTests.Parse_TestCaseNameWithSpaces_KeepsTheTest;
begin
  const Output = 'Tests Found   : 2'#13#10'Tests Failed  : 1'#13#10#13#10'Failing Tests'#13#10#13#10 +
                 '  App.Tests.TTrimTests.Trim_RemovesBlanks.Empty string'#13#10 +
                 '  Message: Expected [] but got [ ]'#13#10#13#10;

  const Summary = TTestOutputParser.Parse(Output);

  Assert.AreEqual<NativeInt>(1, Length(Summary.FailedTests));
  Assert.AreEqual('App.Tests.TTrimTests.Trim_RemovesBlanks.Empty string', Summary.FailedTests[0].Name);
  Assert.AreEqual('Expected [] but got [ ]', Summary.FailedTests[0].Message);
end;

procedure TTestOutputParserTests.Parse_ShutdownLeakReport_IsDetected;
begin
  const Output = Format('%s%sUnexpected Memory Leak%sAn unexpected memory leak has occurred.', [PassingTestOutput, sLineBreak, sLineBreak]);

  const Summary = TTestOutputParser.Parse(Output);

  Assert.IsTrue(Summary.HasShutdownLeakReport);
end;

procedure TTestOutputParserTests.Parse_EmptyOutput_ReturnsZeroes;
begin
  const Summary = TTestOutputParser.Parse('');

  Assert.AreEqual(0, Summary.Found);
  Assert.AreEqual<NativeInt>(0, Length(Summary.FailedTests));
end;

end.
