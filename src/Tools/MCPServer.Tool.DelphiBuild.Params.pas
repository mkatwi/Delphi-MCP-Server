unit MCPServer.Tool.DelphiBuild.Params;

interface

uses
  MCPServer.Types,
  MCPServer.DelphiBuild.Types;

type
  TDelphiProjectParams = class
  private
    FProject: string;
    FConfig: string;
    FPlatform: string;
    FSearchPaths: string;
  public
    function ToRequest: TBuildRequest;

    [SchemaDescription('Path of the Delphi .dpr project file to build, absolute or relative to the server''s working directory. Must lie inside one of the allowed roots')]
    [SchemaName('project')]
    property Project: string read FProject write FProject;

    [Optional]
    [SchemaDescription('Build configuration: Debug (range and overflow checks on) or Release (optimized). Default Debug')]
    [SchemaEnum('Debug', 'Release')]
    [SchemaName('config')]
    property Config: string read FConfig write FConfig;

    [Optional]
    [SchemaDescription('Target platform: Win32 or Win64. Default Win32')]
    [SchemaEnum('Win32', 'Win64')]
    [SchemaName('platform')]
    property Platform: string read FPlatform write FPlatform;

    [Optional]
    [SchemaDescription('Extra unit search folders, separated by semicolons, for units the .dpr does not list with an "in" clause. Each must lie inside the allowed roots')]
    [SchemaName('searchPaths')]
    property SearchPaths: string read FSearchPaths write FSearchPaths;
  end;

implementation

uses
  System.SysUtils;

const
  DefaultConfig = TDelphiConfig.Debug;
  DefaultPlatform = TDelphiPlatform.Win32;
  SearchPathSeparator = ';';

function TDelphiProjectParams.ToRequest: TBuildRequest;
begin
  Result := Default(TBuildRequest);
  Result.ProjectFile := FProject.Trim;
  Result.Config      := DefaultConfig;
  Result.Platform    := DefaultPlatform;

  const HasConfig = not FConfig.Trim.IsEmpty;
  if HasConfig then
    Result.Config := TDelphiConfig.Parse(FConfig);

  const HasPlatform = not FPlatform.Trim.IsEmpty;
  if HasPlatform then
    Result.Platform := TDelphiPlatform.Parse(FPlatform);

  const Paths = FSearchPaths.Split([SearchPathSeparator], TStringSplitOptions.ExcludeEmpty);
  for var Path in Paths do
  begin
    Result.SearchPaths := Result.SearchPaths + [Path.Trim];
  end;
end;

end.
