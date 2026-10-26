unit MCPServer.Tool.DelphiBuild;

interface

uses
  MCPServer.Tool.Base,
  MCPServer.Types,
  MCPServer.DelphiBuild.Types,
  MCPServer.DelphiBuild.Compiler,
  MCPServer.Tool.DelphiBuild.Params;

type
  TDelphiBuildOutput = class
  private
    FSucceeded: Boolean;
    FExitCode: Integer;
    FTimedOut: Boolean;
    FDurationMs: Int64;
    FExecutablePath: string;
    FErrorCount: Integer;
    FWarningCount: Integer;
    FHintCount: Integer;
    FMessages: TArray<TCompilerMessage>;
    FOutputTail: string;
  public
    class function FromReport(const Report: TBuildReport): TDelphiBuildOutput; static;

    [SchemaDescription('True when the compiler finished without errors and produced the executable')]
    [SchemaName('succeeded')]
    property Succeeded: Boolean read FSucceeded write FSucceeded;
    [SchemaDescription('Exit code of the compiler process')]
    [SchemaName('exitCode')]
    property ExitCode: Integer read FExitCode write FExitCode;
    [SchemaDescription('True when the build was stopped because it exceeded the time limit')]
    [SchemaName('timedOut')]
    property TimedOut: Boolean read FTimedOut write FTimedOut;
    [SchemaDescription('Duration of the build in milliseconds')]
    [SchemaName('durationMs')]
    property DurationMs: Int64 read FDurationMs write FDurationMs;
    [SchemaDescription('Full path of the built executable, empty when the build failed')]
    [SchemaName('executablePath')]
    property ExecutablePath: string read FExecutablePath write FExecutablePath;
    [SchemaDescription('Number of errors, fatal errors included')]
    [SchemaName('errorCount')]
    property ErrorCount: Integer read FErrorCount write FErrorCount;
    [SchemaDescription('Number of warnings')]
    [SchemaName('warningCount')]
    property WarningCount: Integer read FWarningCount write FWarningCount;
    [SchemaDescription('Number of hints')]
    [SchemaName('hintCount')]
    property HintCount: Integer read FHintCount write FHintCount;
    [SchemaDescription('Every hint, warning and error with code, file and line')]
    [SchemaName('messages')]
    property Messages: TArray<TCompilerMessage> read FMessages write FMessages;
    [SchemaDescription('Last lines of the compiler output when the build failed, empty otherwise')]
    [SchemaName('outputTail')]
    property OutputTail: string read FOutputTail write FOutputTail;
  end;

  TDelphiBuildTool = class(TMCPToolBase<TDelphiProjectParams, TDelphiBuildOutput>)
  private
    FCompiler: IDelphiCompiler;
  protected
    function ExecuteWithParams(const Params: TDelphiProjectParams): TDelphiBuildOutput; override;
  public
    constructor Create; override;
    constructor CreateWithCompiler(const Compiler: IDelphiCompiler);
  end;

const
  DelphiBuildToolName = 'delphi_build';

implementation

uses
  MCPServer.Errors;

resourcestring
  SDelphiBuildNotConfigured = 'delphi_build was created without a compiler; register it with TDelphiBuildToolRegistration';
  SDelphiBuildTitle = 'Build a Delphi project';
  SDelphiBuildDescription = 'Compiles a Delphi .dpr project with the RAD Studio command-line compiler (dcc32/dcc64) ' +
                            'and returns every error, warning and hint with code, file and line, plus the path of the ' +
                            'executable. Use it to check that Delphi code compiles cleanly after a change. ' +
                            'Writes build output to <project folder>\build\<platform>\<config>.';

class function TDelphiBuildOutput.FromReport(const Report: TBuildReport): TDelphiBuildOutput;
begin
  Result := TDelphiBuildOutput.Create;
  Result.Succeeded      := Report.Succeeded;
  Result.ExitCode       := Integer(Report.ExitCode);
  Result.TimedOut       := Report.TimedOut;
  Result.DurationMs     := Report.DurationMs;
  Result.ExecutablePath := Report.ExecutablePath;
  Result.ErrorCount     := Report.ErrorCount;
  Result.WarningCount   := Report.WarningCount;
  Result.HintCount      := Report.HintCount;
  Result.Messages       := Report.Messages;
  Result.OutputTail     := Report.OutputTail;
end;

constructor TDelphiBuildTool.Create;
begin
  inherited Create;
  FName        := DelphiBuildToolName;
  FTitle       := SDelphiBuildTitle;
  FDescription := SDelphiBuildDescription;
end;

constructor TDelphiBuildTool.CreateWithCompiler(const Compiler: IDelphiCompiler);
begin
  Create;
  FCompiler := Compiler;
end;

function TDelphiBuildTool.ExecuteWithParams(const Params: TDelphiProjectParams): TDelphiBuildOutput;
begin
  if not Assigned(FCompiler) then
    raise EMCPToolError.Create(SDelphiBuildNotConfigured);

  try
    const Request = Params.ToRequest;
    const Report = FCompiler.Build(Request);
    Result := TDelphiBuildOutput.FromReport(Report);
  except
    on E: EDelphiBuildError do
      raise EMCPToolError.Create(E.Message);
  end;
end;

end.
