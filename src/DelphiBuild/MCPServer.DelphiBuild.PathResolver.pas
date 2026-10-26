unit MCPServer.DelphiBuild.PathResolver;

interface

type
  TPathResolver = class
  private
    class function TryResolveExisting(const Path: string; out FinalPath: string): Boolean; static;
    class function StripLongPathPrefix(const Path: string): string; static;
  public
    class function FinalPath(const Path: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows;

const
  LongPathPrefix = '\\?\';
  LongUncPrefix = '\\?\UNC\';
  UncPrefix = '\\';
  PathBufferLength = 32768;
  ShareAll = FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE;

class function TPathResolver.FinalPath(const Path: string): string;
begin
  const FullPath = TPath.GetFullPath(Path);
  var Resolved: string;
  const IsResolved = TryResolveExisting(FullPath, Resolved);
  if IsResolved then
    Exit(Resolved);

  const Parent = TPath.GetDirectoryName(FullPath);
  const HasParent = not Parent.IsEmpty and not SameText(Parent, FullPath);
  if not HasParent then
    Exit(FullPath);

  const ResolvedParent = FinalPath(Parent);
  const Name = TPath.GetFileName(FullPath);
  Result := TPath.Combine(ResolvedParent, Name);
end;

class function TPathResolver.TryResolveExisting(const Path: string; out FinalPath: string): Boolean;
begin
  FinalPath := '';
  const Handle = CreateFile(PChar(Path), 0, ShareAll, nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  const IsOpen = (Handle <> INVALID_HANDLE_VALUE);
  if not IsOpen then
    Exit(False);

  try
    var Buffer: string;
    SetLength(Buffer, PathBufferLength);
    {$WARN SYMBOL_PLATFORM OFF}
    const FinalLength = GetFinalPathNameByHandle(Handle, PChar(Buffer), PathBufferLength, FILE_NAME_NORMALIZED);
    {$WARN SYMBOL_PLATFORM ON}
    Result := (FinalLength > 0) and (FinalLength < PathBufferLength);
    if not Result then
      Exit;

    const LongPath = Copy(Buffer, 1, FinalLength);
    FinalPath := StripLongPathPrefix(LongPath);
  finally
    CloseHandle(Handle);
  end;
end;

class function TPathResolver.StripLongPathPrefix(const Path: string): string;
begin
  const IsLongUnc = Path.StartsWith(LongUncPrefix);
  if IsLongUnc then
  begin
    const ShareName = Path.Substring(LongUncPrefix.Length);
    Exit(Format('%s%s', [UncPrefix, ShareName]));
  end;

  const IsLongPath = Path.StartsWith(LongPathPrefix);
  if IsLongPath then
    Exit(Path.Substring(LongPathPrefix.Length));

  Result := Path;
end;

end.
