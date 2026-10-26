unit MCPServer.DelphiBuild.Registration;

interface

uses
  MCPServer.DelphiBuild.Settings;

type
  TDelphiBuildToolRegistration = class
  public
    class function RegisterTools(const Settings: TDelphiBuildSettings): Boolean; static;
    class function RegisterToolsFromSettingsFile(const SettingsFile: string): Boolean; static;
    class function RegisterToolsFromServerSettings: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  MCPServer.Registration,
  MCPServer.Settings,
  MCPServer.Logger,
  MCPServer.Tool.Base,
  MCPServer.DelphiBuild.ProcessRunner,
  MCPServer.DelphiBuild.Compiler,
  MCPServer.DelphiBuild.TestRunner,
  MCPServer.Tool.DelphiBuild,
  MCPServer.Tool.DelphiRunTests;

resourcestring
  SToolsDisabled = 'Delphi build tools are disabled: set Enabled=1 and AllowedRoots in the [DelphiBuild] section of settings.ini to enable them';
  SToolsEnabled = 'Delphi build tools enabled for %d allowed root(s)';

class function TDelphiBuildToolRegistration.RegisterTools(const Settings: TDelphiBuildSettings): Boolean;
begin
  Result := Settings.IsConfigured;
  if not Result then
  begin
    TLogger.Info(SToolsDisabled);
    Exit;
  end;

  const ToolSettings = Settings;

  TMCPRegistry.RegisterTool(DelphiBuildToolName,
    function: IMCPTool
    begin
      const Runner: IProcessRunner = TWindowsProcessRunner.Create;
      const Compiler: IDelphiCompiler = TDelphiCompiler.Create(ToolSettings, Runner);
      Result := TDelphiBuildTool.CreateWithCompiler(Compiler);
    end);

  TMCPRegistry.RegisterTool(DelphiRunTestsToolName,
    function: IMCPTool
    begin
      const Runner: IProcessRunner = TWindowsProcessRunner.Create;
      const Compiler: IDelphiCompiler = TDelphiCompiler.Create(ToolSettings, Runner);
      const TestRunner: IDelphiTestRunner = TDelphiTestRunner.Create(ToolSettings, Runner, Compiler);
      Result := TDelphiRunTestsTool.CreateWithTestRunner(TestRunner);
    end);

  TLogger.Info(Format(SToolsEnabled, [Length(Settings.AllowedRoots)]));
end;

class function TDelphiBuildToolRegistration.RegisterToolsFromSettingsFile(const SettingsFile: string): Boolean;
begin
  const Settings = TDelphiBuildSettings.LoadFromFile(SettingsFile);
  Result := RegisterTools(Settings);
end;

class function TDelphiBuildToolRegistration.RegisterToolsFromServerSettings: Boolean;
begin
  const ServerSettings = TMCPSettings.Create('', False);
  try
    Result := RegisterToolsFromSettingsFile(ServerSettings.SettingsFile);
  finally
    ServerSettings.Free;
  end;
end;

end.
