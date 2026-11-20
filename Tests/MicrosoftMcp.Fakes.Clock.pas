unit MicrosoftMcp.Fakes.Clock;

interface

uses
  MCPAuth.Clock.Interfaces;

type
  TFakeClock = class(TInterfacedObject, IClock)
  private
    FNowUtc: TDateTime;

  public
    constructor Create(const NowUtc: TDateTime);

    procedure AdvanceMinutes(const Minutes: Integer);

    function NowUtc: TDateTime;
  end;

implementation

uses
  System.DateUtils;

{ TFakeClock }

constructor TFakeClock.Create(const NowUtc: TDateTime);
begin
  inherited Create;

  FNowUtc := NowUtc;
end;

procedure TFakeClock.AdvanceMinutes(const Minutes: Integer);
begin
  FNowUtc := IncMinute(FNowUtc, Minutes);
end;

function TFakeClock.NowUtc: TDateTime;
begin
  Result := FNowUtc;
end;

end.
