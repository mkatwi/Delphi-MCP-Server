unit MCPServer.DelphiBuild.Settings;

interface

type
  TDelphiBuildSettings = record
    Enabled: Boolean;
    BdsPath: string;
    AllowedRoots: TArray<string>;
    TimeoutSeconds: Integer;
    class function Defaults: TDelphiBuildSettings; static;
    class function LoadFromFile(const FileName: string): TDelphiBuildSettings; static;
    class function ClampTimeout(const Seconds: Integer): Integer; static;
    function IsConfigured: Boolean;
    function IsAllowed(const Path: string): Boolean;
    function CompilerPath(const CompilerFileName: string): string;
  end;

const
  DefaultBdsPath = 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  DefaultTimeoutSeconds = 300;
  MinTimeoutSeconds = 10;
  MaxTimeoutSeconds = 3600;

implementation

uses
  System.SysUtils,
  System.Math,
  System.IOUtils,
  System.IniFiles,
  MCPServer.PathBoundary,
  MCPServer.DelphiBuild.PathResolver;

const
  SectionName = 'DelphiBuild';
  KeyEnabled = 'Enabled';
  KeyBdsPath = 'BdsPath';
  KeyAllowedRoots = 'AllowedRoots';
  KeyTimeoutSeconds = 'TimeoutSeconds';
  RootSeparator = ';';
  CompilerFolder = 'bin';

class function TDelphiBuildSettings.Defaults: TDelphiBuildSettings;
begin
  Result.Enabled        := False;
  Result.BdsPath        := DefaultBdsPath;
  Result.AllowedRoots   := [];
  Result.TimeoutSeconds := DefaultTimeoutSeconds;
end;

class function TDelphiBuildSettings.LoadFromFile(const FileName: string): TDelphiBuildSettings;
begin
  Result := Defaults;
  const FileFound = TFile.Exists(FileName);
  if not FileFound then
    Exit;

  const Ini = TMemIniFile.Create(FileName);
  try
    const ConfiguredTimeout = Ini.ReadInteger(SectionName, KeyTimeoutSeconds, Result.TimeoutSeconds);
    const RootList = Ini.ReadString(SectionName, KeyAllowedRoots, '');

    Result.Enabled        := Ini.ReadBool(SectionName, KeyEnabled, Result.Enabled);
    Result.BdsPath        := Ini.ReadString(SectionName, KeyBdsPath, Result.BdsPath);
    Result.TimeoutSeconds := ClampTimeout(ConfiguredTimeout);

    const Roots = RootList.Split([RootSeparator], TStringSplitOptions.ExcludeEmpty);
    for var Root in Roots do
    begin
      const TrimmedRoot = Root.Trim;
      const FullRoot = TPath.GetFullPath(TrimmedRoot);
      Result.AllowedRoots := Result.AllowedRoots + [FullRoot];
    end;
  finally
    Ini.Free;
  end;
end;

class function TDelphiBuildSettings.ClampTimeout(const Seconds: Integer): Integer;
begin
  Result := EnsureRange(Seconds, MinTimeoutSeconds, MaxTimeoutSeconds);
end;

function TDelphiBuildSettings.IsConfigured: Boolean;
begin
  const HasRoots = (Length(AllowedRoots) > 0);
  Result := Enabled and HasRoots;
end;

function TDelphiBuildSettings.IsAllowed(const Path: string): Boolean;
begin
  const ResolvedPath = TPathResolver.FinalPath(Path);
  for var Root in AllowedRoots do
  begin
    const ResolvedRoot = TPathResolver.FinalPath(Root);
    const IsInsideRoot = TPathBoundary.IsWithin(ResolvedPath, ResolvedRoot);
    if IsInsideRoot then
      Exit(True);
  end;

  Result := False;
end;

function TDelphiBuildSettings.CompilerPath(const CompilerFileName: string): string;
begin
  const BinFolder = TPath.Combine(BdsPath, CompilerFolder);
  Result := TPath.Combine(BinFolder, CompilerFileName);
end;

end.
