unit MicrosoftMcp.Server.Maintenance.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Confirm.Interfaces,
  MicrosoftMcp.Fakes.Clock;

type
  [TestFixture]
  TServerMaintenanceTests = class
  private
    FClock: TFakeClock;
    FClockInterface: IInterface;
    FConfirmations: IConfirmations;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure MaintenanceDeletesExpiredConfirmations;

    [Test]
    procedure MaintenanceRunsOnItsInterval;

    [Test]
    procedure MaintenanceStopsPromptly;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Diagnostics,
  MCPAuth.Secret.Token,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Server.Maintenance;

const
  Kees = 'user-1';
  DeleteTool = 'mail_delete';
  ArgumentsHash = 'hash-1';
  Summary = 'Delete a message';
  ShortIntervalMs = 20;
  WaitStepMs = 10;
  MaxWaitMs = 2000;
  PromptStopMs = 2000;

{ TServerMaintenanceTests }

procedure TServerMaintenanceTests.Setup;
begin
  FClock := TFakeClock.Create(EncodeDateTime(2026, 11, 20, 9, 0, 0, 0));
  FClockInterface := FClock;
  FConfirmations := TConfirmationsMemory.Create(TTokenGenerator.Create, FClock);
end;

procedure TServerMaintenanceTests.TearDown;
begin
  FConfirmations := nil;
  FClock := nil;
  FClockInterface := nil;
end;

procedure TServerMaintenanceTests.MaintenanceDeletesExpiredConfirmations;
begin
  FConfirmations.Issue(Kees, DeleteTool, ArgumentsHash, Summary);
  FClock.AdvanceMinutes(TConfirmationsMemory.LifetimeMinutes + 1);
  const Maintenance = TServerMaintenance.Create(FConfirmations);
  try
    Maintenance.RunOnce;

    Assert.AreEqual(0, FConfirmations.DeleteExpired, 'already deleted by the maintenance');
    Assert.AreEqual(1, Maintenance.RunCount);
  finally
    Maintenance.Free;
  end;
end;

procedure TServerMaintenanceTests.MaintenanceRunsOnItsInterval;
begin
  const Maintenance = TServerMaintenance.Create(FConfirmations, ShortIntervalMs);
  try
    Maintenance.Start;

    const Watch = TStopwatch.StartNew;
    while (Maintenance.RunCount = 0) and (Watch.ElapsedMilliseconds < MaxWaitMs) do
    begin
      Sleep(WaitStepMs);
    end;
    Maintenance.Stop;

    Assert.IsTrue(Maintenance.RunCount > 0, 'the thread ran at least once');
  finally
    Maintenance.Free;
  end;
end;

procedure TServerMaintenanceTests.MaintenanceStopsPromptly;
begin
  const Maintenance = TServerMaintenance.Create(FConfirmations);
  try
    Maintenance.Start;
    Sleep(WaitStepMs);

    const Watch = TStopwatch.StartNew;
    Maintenance.Stop;
    const ElapsedMs = Watch.ElapsedMilliseconds;

    Assert.IsTrue(ElapsedMs < PromptStopMs, Format('Stop took %d ms', [ElapsedMs]));
  finally
    Maintenance.Free;
  end;
end;

end.
