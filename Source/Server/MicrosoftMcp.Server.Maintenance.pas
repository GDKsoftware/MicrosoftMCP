unit MicrosoftMcp.Server.Maintenance;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  MicrosoftMcp.Confirm.Interfaces;

type
  // Deletes expired confirmation tokens on a background thread, once per interval.
  // Stop wakes the thread, so it ends within the time of one running cleanup.
  TServerMaintenance = class
  private
    FConfirmations: IConfirmations;
    FIntervalMs: Cardinal;
    FStopEvent: TEvent;
    FThread: TThread;
    FRunCount: Integer;

    procedure RunUntilStopped;
    procedure RunGuarded;

  public
    const DefaultIntervalMs = 10 * 60 * 1000;

    constructor Create(const Confirmations: IConfirmations; const IntervalMs: Cardinal = DefaultIntervalMs);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    procedure RunOnce;
    function RunCount: Integer;
  end;

implementation

uses
  MCPServer.Logger;

const
  CleanupFailedFormat = 'Maintenance failed with %s';

{ TServerMaintenance }

constructor TServerMaintenance.Create(const Confirmations: IConfirmations; const IntervalMs: Cardinal);
begin
  inherited Create;

  FConfirmations := Confirmations;
  FIntervalMs := IntervalMs;
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

destructor TServerMaintenance.Destroy;
begin
  Stop;
  FStopEvent.Free;

  inherited Destroy;
end;

procedure TServerMaintenance.Start;
begin
  if Assigned(FThread) then
    Exit;

  FStopEvent.ResetEvent;
  FThread := TThread.CreateAnonymousThread(RunUntilStopped);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TServerMaintenance.Stop;
begin
  if not Assigned(FThread) then
    Exit;

  FStopEvent.SetEvent;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

procedure TServerMaintenance.RunUntilStopped;
begin
  while FStopEvent.WaitFor(FIntervalMs) = TWaitResult.wrTimeout do
  begin
    RunGuarded;
  end;
end;

procedure TServerMaintenance.RunGuarded;
begin
  // A failing cleanup must not end the thread; the next interval tries again.
  try
    RunOnce;
  except
    on E: Exception do
      TLogger.Error(CleanupFailedFormat, [E.ClassName]);
  end;
end;

procedure TServerMaintenance.RunOnce;
begin
  FConfirmations.DeleteExpired;

  TInterlocked.Increment(FRunCount);
end;

function TServerMaintenance.RunCount: Integer;
begin
  Result := TInterlocked.CompareExchange(FRunCount, 0, 0);
end;

end.
