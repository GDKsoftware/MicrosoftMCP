program MicrosoftMcp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  MCPServer.Logger,
  MCPAuth.Server.Shutdown,
  MicrosoftMcp.Server.Exceptions in 'Server\MicrosoftMcp.Server.Exceptions.pas',
  MicrosoftMcp.Server.Settings in 'Server\MicrosoftMcp.Server.Settings.pas',
  MicrosoftMcp.Server.Composition in 'Server\MicrosoftMcp.Server.Composition.pas';

const
  ExitFailed = 1;

resourcestring
  FailedFormat = 'MicrosoftMCP failed: %s: %s';

begin
  TShutdownSignal.Prepare;
  TLogger.LogToConsole := True;
  try
    const Settings = TServerSettings.FromEnvironment;
    const Composition = TServerComposition.Create(Settings);
    try
      Composition.Start;
      TShutdownSignal.WaitForSignal;
      Composition.Stop;
    finally
      Composition.Free;
    end;
  except
    on E: Exception do
    begin
      TLogger.Error(FailedFormat, [E.ClassName, E.Message]);
      System.ExitCode := ExitFailed;
    end;
  end;
end.
