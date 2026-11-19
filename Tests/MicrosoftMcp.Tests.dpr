program MicrosoftMcp.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  MicrosoftMcp.Server.Settings.Tests in 'MicrosoftMcp.Server.Settings.Tests.pas',
  MicrosoftMcp.Server.Composition.Tests in 'MicrosoftMcp.Server.Composition.Tests.pas',
  MicrosoftMcp.Mailbox.Slug.Tests in 'MicrosoftMcp.Mailbox.Slug.Tests.pas',
  MicrosoftMcp.Mailbox.Store.Contract.Tests in 'MicrosoftMcp.Mailbox.Store.Contract.Tests.pas',
  MicrosoftMcp.Mailbox.Store.Memory.Tests in 'MicrosoftMcp.Mailbox.Store.Memory.Tests.pas',
  MicrosoftMcp.Tests.Postgres in 'MicrosoftMcp.Tests.Postgres.pas',
  MicrosoftMcp.Mailbox.Store.FireDAC.Tests in 'MicrosoftMcp.Mailbox.Store.FireDAC.Tests.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;

    const Runner = TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));

    const HasXmlOutput = not TDUnitX.Options.XMLOutputFile.IsEmpty;
    if HasXmlOutput then
      Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile));

    const Results = Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
  except
    on E: Exception do
    begin
      Writeln(Format('%s: %s', [E.ClassName, E.Message]));
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
