unit MicrosoftMcp.Tools.Calendar.Time;

interface

type
  // The start and end of an event as the calendar tools hand them to Graph. Start and Finish are 0 when the caller left them out.
  TCalendarMoment = record
    Start: TDateTime;
    Finish: TDateTime;
    TimeZone: string;
    AssumedUtc: Boolean;

    // The time as the summaries and notes show it: ISO 8601 UTC, or as written plus the time zone it is meant in.
    function Show(const Value: TDateTime): string;
    function Describe: string;
    function Note: string;
  end;

  TCalendarTime = class
  private
    type
      TParsedTime = record
        Value: TDateTime;
        HasOffset: Boolean;
      end;

    class function HasOffset(const Text: string): Boolean; static;
    class function Parse(const Text, ParamName: string): TParsedTime; static;

  public
    const Utc = 'UTC';

    // Start and end as given by the caller. ISO 8601 with an offset is converted to UTC. Without an offset the time is taken
    // as UTC (and the moment says so), unless a time zone is given: then the time is meant in that zone.
    class function Resolve(const StartText, EndText, TimeZone: string; const BothRequired: Boolean): TCalendarMoment; static;

    class function ToIso(const Value: TDateTime): string; static;
    class function ToGraph(const Value: TDateTime): string; static;

    // Graph answers with a date time without zone designator (we always ask for UTC); the tools show it with the Z.
    class function FromGraph(const Value: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  MicrosoftMcp.Tools.Exceptions;

resourcestring
  DateRequired = 'The parameter "%s" is required: give a date and time in ISO 8601, for example 2026-11-20T09:00:00+01:00.';
  DateInvalid = 'The parameter "%s" is not a valid ISO 8601 date and time: "%s". Use for example 2026-11-20T09:00:00+01:00 or 2026-11-20T08:00:00Z.';
  MixedOffsets = 'With a time_zone, give start and end both without an offset or both with an offset.';
  EndBeforeStart = 'The parameter "end" must be later than "start".';
  AssumedUtcNote = 'No time zone offset was given, so the time was taken as UTC.';
  ZoneFormat = '%s (time zone %s)';
  RangeFormat = '%s to %s';

const
  StartName = 'start';
  EndName = 'end';
  GraphFormat = 'yyyy-mm-dd"T"hh:nn:ss';
  IsoFormat = 'yyyy-mm-dd"T"hh:nn:ss"Z"';
  GraphDateLength = 19;

{ TCalendarMoment }

function TCalendarMoment.Show(const Value: TDateTime): string;
begin
  const IsUtc = SameText(TimeZone, TCalendarTime.Utc);
  if IsUtc then
    Exit(TCalendarTime.ToIso(Value));

  Result := Format(ZoneFormat, [TCalendarTime.ToGraph(Value), TimeZone]);
end;

function TCalendarMoment.Describe: string;
begin
  Result := Format(RangeFormat, [Show(Start), Show(Finish)]);
end;

function TCalendarMoment.Note: string;
begin
  if AssumedUtc then
    Result := AssumedUtcNote
  else
    Result := '';
end;

{ TCalendarTime }

class function TCalendarTime.Resolve(const StartText, EndText, TimeZone: string; const BothRequired: Boolean): TCalendarMoment;
begin
  Result := Default(TCalendarMoment);
  Result.TimeZone := Utc;

  const HasStart = not StartText.Trim.IsEmpty;
  const HasEnd = not EndText.Trim.IsEmpty;
  if BothRequired and not HasStart then
    raise EToolArgumentError.CreateFmt(DateRequired, [StartName]);
  if BothRequired and not HasEnd then
    raise EToolArgumentError.CreateFmt(DateRequired, [EndName]);

  var AnyOffset := False;
  var AnyNaive := False;

  if HasStart then
  begin
    const Parsed = Parse(StartText, StartName);
    Result.Start := Parsed.Value;
    AnyOffset := AnyOffset or Parsed.HasOffset;
    AnyNaive := AnyNaive or not Parsed.HasOffset;
  end;

  if HasEnd then
  begin
    const Parsed = Parse(EndText, EndName);
    Result.Finish := Parsed.Value;
    AnyOffset := AnyOffset or Parsed.HasOffset;
    AnyNaive := AnyNaive or not Parsed.HasOffset;
  end;

  if AnyNaive then
  begin
    const HasZone = not TimeZone.Trim.IsEmpty;
    if HasZone and AnyOffset then
      raise EToolArgumentError.Create(MixedOffsets);

    if HasZone then
      Result.TimeZone := TimeZone.Trim
    else
      Result.AssumedUtc := True;
  end;

  const IsReversed = (HasStart and HasEnd and (Result.Finish <= Result.Start));
  if IsReversed then
    raise EToolArgumentError.Create(EndBeforeStart);
end;

class function TCalendarTime.Parse(const Text, ParamName: string): TParsedTime;
begin
  const Trimmed = Text.Trim;

  Result.HasOffset := HasOffset(Trimmed);
  try
    // ISO8601ToDate reads a text without offset as UTC, so with AReturnUTC it returns that time unchanged (False would shift it to local time).
    Result.Value := ISO8601ToDate(Trimmed, True);
  except
    on EDateTimeException do
      raise EToolArgumentError.CreateFmt(DateInvalid, [ParamName, Trimmed]);
    on EConvertError do
      raise EToolArgumentError.CreateFmt(DateInvalid, [ParamName, Trimmed]);
  end;
end;

class function TCalendarTime.HasOffset(const Text: string): Boolean;
begin
  const TimePosition = Text.IndexOf('T');
  const HasTime = (TimePosition >= 0);
  if not HasTime then
    Exit(False);

  const TimePart = Text.Substring(TimePosition);
  Result := (TimePart.Contains('Z') or TimePart.Contains('z') or TimePart.Contains('+') or TimePart.Contains('-'));
end;

class function TCalendarTime.ToIso(const Value: TDateTime): string;
begin
  Result := FormatDateTime(IsoFormat, Value, TFormatSettings.Invariant);
end;

class function TCalendarTime.ToGraph(const Value: TDateTime): string;
begin
  Result := FormatDateTime(GraphFormat, Value, TFormatSettings.Invariant);
end;

class function TCalendarTime.FromGraph(const Value: string): string;
begin
  const IsComplete = (Value.Length >= GraphDateLength);
  if IsComplete then
    Result := Value.Substring(0, GraphDateLength) + 'Z'
  else
    Result := Value;
end;

end.
