unit MCPServer.DelphiBuild.Types;

interface

uses
  System.SysUtils,
  MCPServer.Types;

const
  OutputLineBreaks: array[0..1] of string = (#13#10, #10);

type
  EDelphiBuildError = class(Exception);

  {$SCOPEDENUMS ON}
  TDelphiConfig = (Debug, Release);
  TDelphiPlatform = (Win32, Win64);
  TCompilerMessageKind = (Hint, Warning, Error, Fatal);
  {$SCOPEDENUMS OFF}

  TDelphiConfigHelper = record helper for TDelphiConfig
    class function Parse(const Name: string): TDelphiConfig; static;
    function Name: string;
  end;

  TDelphiPlatformHelper = record helper for TDelphiPlatform
    class function Parse(const Name: string): TDelphiPlatform; static;
    function Name: string;
    function CompilerFileName: string;
  end;

  TCompilerMessage = record
    [SchemaName('kind')]
    Kind: TCompilerMessageKind;
    [SchemaName('code')]
    Code: string;
    [SchemaName('fileName')]
    FileName: string;
    [SchemaName('line')]
    Line: Integer;
    [SchemaName('text')]
    Text: string;
  end;

  TProcessResult = record
    ExitCode: Cardinal;
    Output: string;
    TimedOut: Boolean;
    DurationMs: Int64;
  end;

  TBuildRequest = record
    ProjectFile: string;
    Config: TDelphiConfig;
    Platform: TDelphiPlatform;
    SearchPaths: TArray<string>;
  end;

  TBuildReport = record
    Succeeded: Boolean;
    ExitCode: Cardinal;
    TimedOut: Boolean;
    DurationMs: Int64;
    ExecutablePath: string;
    ErrorCount: Integer;
    WarningCount: Integer;
    HintCount: Integer;
    Messages: TArray<TCompilerMessage>;
    OutputTail: string;
  end;

  TFailedTest = record
    [SchemaName('name')]
    Name: string;
    [SchemaName('message')]
    Message: string;
  end;

  TTestRunSummary = record
    Found: Integer;
    Passed: Integer;
    Failed: Integer;
    Errored: Integer;
    Ignored: Integer;
    Leaked: Integer;
    HasShutdownLeakReport: Boolean;
    FailedTests: TArray<TFailedTest>;
  end;

  TTestReport = record
    Build: TBuildReport;
    Ran: Boolean;
    Passed: Boolean;
    ExitCode: Cardinal;
    TimedOut: Boolean;
    DurationMs: Int64;
    Summary: TTestRunSummary;
    OutputTail: string;
  end;

resourcestring
  SUnknownConfig = 'Unknown configuration "%s", expected Debug or Release';
  SUnknownPlatform = 'Unknown platform "%s", expected Win32 or Win64';

implementation

const
  ConfigNames: array[TDelphiConfig] of string = ('Debug', 'Release');
  PlatformNames: array[TDelphiPlatform] of string = ('Win32', 'Win64');
  CompilerFileNames: array[TDelphiPlatform] of string = ('dcc32.exe', 'dcc64.exe');

class function TDelphiConfigHelper.Parse(const Name: string): TDelphiConfig;
begin
  for var Config := Low(TDelphiConfig) to High(TDelphiConfig) do
  begin
    const IsMatch = SameText(Name.Trim, ConfigNames[Config]);
    if IsMatch then
      Exit(Config);
  end;

  raise EDelphiBuildError.CreateFmt(SUnknownConfig, [Name]);
end;

function TDelphiConfigHelper.Name: string;
begin
  Result := ConfigNames[Self];
end;

class function TDelphiPlatformHelper.Parse(const Name: string): TDelphiPlatform;
begin
  for var Platform := Low(TDelphiPlatform) to High(TDelphiPlatform) do
  begin
    const IsMatch = SameText(Name.Trim, PlatformNames[Platform]);
    if IsMatch then
      Exit(Platform);
  end;

  raise EDelphiBuildError.CreateFmt(SUnknownPlatform, [Name]);
end;

function TDelphiPlatformHelper.Name: string;
begin
  Result := PlatformNames[Self];
end;

function TDelphiPlatformHelper.CompilerFileName: string;
begin
  Result := CompilerFileNames[Self];
end;

end.
