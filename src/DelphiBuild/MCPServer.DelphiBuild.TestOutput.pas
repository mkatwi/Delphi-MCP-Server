unit MCPServer.DelphiBuild.TestOutput;

interface

uses
  MCPServer.DelphiBuild.Types;

type
  TTestOutputParser = class
  private
    class function ReadCounters(const Lines: TArray<string>): TTestRunSummary; static;
    class function TryReadCounter(const Line: string; const Prefix: string; out Value: Integer): Boolean; static;
    class function ReadFailedTests(const Lines: TArray<string>): TArray<TFailedTest>; static;
    class function IsSectionHeader(const Line: string): Boolean; static;
  public
    class function Parse(const Output: string): TTestRunSummary; static;
  end;

implementation

uses
  System.SysUtils;

const
  FoundPrefix = 'Tests Found';
  PassedPrefix = 'Tests Passed';
  FailedPrefix = 'Tests Failed';
  ErroredPrefix = 'Tests Errored';
  IgnoredPrefix = 'Tests Ignored';
  LeakedPrefix = 'Tests Leaked';
  CounterSeparator = ':';
  FailingSection = 'Failing Tests';
  ErrorSection = 'Tests With Errors';
  LeakSection = 'Tests With Memory Leak';
  MessagePrefix = 'Message:';
  TestNameIndent = '  ';
  ShutdownLeakMarker = 'Unexpected Memory Leak';

class function TTestOutputParser.Parse(const Output: string): TTestRunSummary;
begin
  const Lines = Output.Split(OutputLineBreaks);

  Result := ReadCounters(Lines);
  Result.FailedTests           := ReadFailedTests(Lines);
  Result.HasShutdownLeakReport := Output.Contains(ShutdownLeakMarker);
end;

class function TTestOutputParser.ReadCounters(const Lines: TArray<string>): TTestRunSummary;
begin
  Result := Default(TTestRunSummary);
  for var Line in Lines do
  begin
    const Trimmed = Line.Trim;
    var Value: Integer;
    if TryReadCounter(Trimmed, FoundPrefix, Value) then
      Result.Found := Value
    else if TryReadCounter(Trimmed, PassedPrefix, Value) then
      Result.Passed := Value
    else if TryReadCounter(Trimmed, FailedPrefix, Value) then
      Result.Failed := Value
    else if TryReadCounter(Trimmed, ErroredPrefix, Value) then
      Result.Errored := Value
    else if TryReadCounter(Trimmed, IgnoredPrefix, Value) then
      Result.Ignored := Value
    else if TryReadCounter(Trimmed, LeakedPrefix, Value) then
      Result.Leaked := Value;
  end;
end;

class function TTestOutputParser.TryReadCounter(const Line: string; const Prefix: string; out Value: Integer): Boolean;
begin
  Value := 0;
  Result := Line.StartsWith(Prefix) and Line.Contains(CounterSeparator);
  if not Result then
    Exit;

  const SeparatorIndex = Line.IndexOf(CounterSeparator);
  const ValueText = Line.Substring(SeparatorIndex + 1);
  const TrimmedValue = ValueText.Trim;
  Result := TryStrToInt(TrimmedValue, Value);
end;

class function TTestOutputParser.ReadFailedTests(const Lines: TArray<string>): TArray<TFailedTest>;
begin
  Result := [];
  var InSection := False;
  var Current := Default(TFailedTest);
  var HasCurrent := False;
  var InMessage := False;

  for var Line in Lines do
  begin
    const Trimmed = Line.Trim;

    if IsSectionHeader(Trimmed) then
    begin
      InSection := not SameText(Trimmed, LeakSection);
      Continue;
    end;

    if not InSection then
      Continue;

    if Trimmed.IsEmpty then
    begin
      if HasCurrent then
        Result := Result + [Current];
      HasCurrent := False;
      InMessage := False;
      Continue;
    end;

    if InMessage then
    begin
      Current.Message := Format('%s%s%s', [Current.Message, sLineBreak, Trimmed]);
      Continue;
    end;

    const IsMessageLine = HasCurrent and Trimmed.StartsWith(MessagePrefix);
    if IsMessageLine then
    begin
      const MessageText = Trimmed.Substring(MessagePrefix.Length);
      Current.Message := MessageText.Trim;
      InMessage := True;
      Continue;
    end;

    const IsNameLine = (not HasCurrent) and Line.StartsWith(TestNameIndent);
    if IsNameLine then
    begin
      Current := Default(TFailedTest);
      Current.Name := Trimmed;
      HasCurrent := True;
    end;
  end;

  if HasCurrent then
    Result := Result + [Current];
end;

class function TTestOutputParser.IsSectionHeader(const Line: string): Boolean;
begin
  Result := SameText(Line, FailingSection) or SameText(Line, ErrorSection) or SameText(Line, LeakSection);
end;

end.
