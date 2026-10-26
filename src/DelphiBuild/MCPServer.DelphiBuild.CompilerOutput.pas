unit MCPServer.DelphiBuild.CompilerOutput;

interface

uses
  System.RegularExpressions,
  MCPServer.DelphiBuild.Types;

type
  TCompilerOutputParser = class
  private
    class function TryParseLine(const Line: string; out Message: TCompilerMessage): Boolean; static;
    class function ParseKind(const KindName: string): TCompilerMessageKind; static;
    class function GroupValue(const Match: TMatch; const GroupName: string): string; static;
  public
    class function Parse(const Output: string): TArray<TCompilerMessage>; static;
    class function CountOf(const Messages: TArray<TCompilerMessage>; const Kind: TCompilerMessageKind): Integer; static;
    class function Tail(const Output: string; const LineCount: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  MessagePattern = '^(?:(?<file>.+?)\((?<line>\d+)\)\s+)?(?<kind>Hint|Warning|Error|Fatal):\s+(?:(?<code>[HWEF]\d{4})\s+)?(?<text>.*)$';
  GroupFile = 'file';
  GroupLine = 'line';
  GroupKind = 'kind';
  GroupCode = 'code';
  GroupText = 'text';
  KindLabels: array[TCompilerMessageKind] of string = ('Hint', 'Warning', 'Error', 'Fatal');

resourcestring
  SUnknownMessageKind = 'Unknown compiler message kind "%s"';

class function TCompilerOutputParser.Parse(const Output: string): TArray<TCompilerMessage>;
begin
  Result := [];
  const Lines = Output.Split(OutputLineBreaks);
  for var Line in Lines do
  begin
    var Message: TCompilerMessage;
    const IsMessage = TryParseLine(Line, Message);
    if IsMessage then
      Result := Result + [Message];
  end;
end;

class function TCompilerOutputParser.CountOf(const Messages: TArray<TCompilerMessage>; const Kind: TCompilerMessageKind): Integer;
begin
  Result := 0;
  for var Message in Messages do
  begin
    const IsKind = (Message.Kind = Kind);
    if IsKind then
      Inc(Result);
  end;
end;

class function TCompilerOutputParser.Tail(const Output: string; const LineCount: Integer): string;
begin
  const Lines = Output.TrimRight.Split(OutputLineBreaks);
  const TotalLines = Integer(Length(Lines));
  const StartIndex = Max(0, TotalLines - LineCount);
  Result := string.Join(sLineBreak, Lines, StartIndex, TotalLines - StartIndex);
end;

class function TCompilerOutputParser.TryParseLine(const Line: string; out Message: TCompilerMessage): Boolean;
begin
  const TrimmedLine = Line.Trim;
  const Match = TRegEx.Match(TrimmedLine, MessagePattern);
  Result := Match.Success;
  if not Result then
    Exit;

  const LineText = GroupValue(Match, GroupLine);
  const KindText = GroupValue(Match, GroupKind);
  const MessageText = GroupValue(Match, GroupText);
  const HasLine = not LineText.IsEmpty;

  Message.Kind     := ParseKind(KindText);
  Message.Code     := GroupValue(Match, GroupCode);
  Message.FileName := GroupValue(Match, GroupFile);
  Message.Text     := MessageText.Trim;
  Message.Line     := 0;
  if HasLine then
    Message.Line := StrToInt(LineText);
end;

class function TCompilerOutputParser.ParseKind(const KindName: string): TCompilerMessageKind;
begin
  for var Kind := Low(TCompilerMessageKind) to High(TCompilerMessageKind) do
  begin
    const IsMatch = SameText(KindName, KindLabels[Kind]);
    if IsMatch then
      Exit(Kind);
  end;

  raise EDelphiBuildError.CreateFmt(SUnknownMessageKind, [KindName]);
end;

class function TCompilerOutputParser.GroupValue(const Match: TMatch; const GroupName: string): string;
begin
  var Group: TGroup;
  const HasGroup = Match.Groups.TryGetNamedGroup(GroupName, Group);
  if HasGroup and Group.Success then
    Exit(Group.Value);

  Result := '';
end;

end.
