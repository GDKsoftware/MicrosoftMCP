unit MicrosoftMcp.Tools.Calendar.Availability;

interface

uses
  System.JSON,
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TAvailabilitySlot = record
    Start: string;

    [SchemaName('end')]
    Finish: string;

    [SchemaDescription('free, tentative, busy, out_of_office, working_elsewhere or unknown')]
    Status: string;
  end;

  TAvailabilityItem = record
    Status: string;
    Subject: string;
    Start: string;

    [SchemaName('end')]
    Finish: string;
  end;

  TScheduleAvailability = record
    Schedule: string;

    [SchemaName('availability_view')]
    [SchemaDescription('One digit per slot: 0 free, 1 tentative, 2 busy, 3 out of office, 4 working elsewhere')]
    AvailabilityView: string;

    Slots: TArray<TAvailabilitySlot>;
    Items: TArray<TAvailabilityItem>;
  end;

  TCalendarAvailabilityResponse = class
  private
    FSchedules: TArray<TScheduleAvailability>;
    FIntervalMinutes: Integer;
    FNote: string;

  public
    property Schedules: TArray<TScheduleAvailability> read FSchedules write FSchedules;

    [SchemaName('interval_minutes')]
    property IntervalMinutes: Integer read FIntervalMinutes write FIntervalMinutes;

    [SchemaDescription('Remarks about how the times were read; empty when there is nothing to remark')]
    property Note: string read FNote write FNote;
  end;

  TCalendarAvailabilityParams = class(TMicrosoftToolParams)
  private
    FSchedules: TArray<string>;
    FStartTime: string;
    FEndTime: string;
    FIntervalMinutes: Integer;

  public
    [SchemaDescription('E-mail addresses of the people or rooms to check, including the mailbox itself if it is to be included')]
    property Schedules: TArray<string> read FSchedules write FSchedules;

    [SchemaName('start')]
    [SchemaDescription('Start of the period, ISO 8601 with offset. Without offset UTC is assumed')]
    property StartTime: string read FStartTime write FStartTime;

    [SchemaName('end')]
    [SchemaDescription('End of the period, ISO 8601 with offset')]
    property EndTime: string read FEndTime write FEndTime;

    [Optional]
    [SchemaName('interval_minutes')]
    [SchemaDescription('Length of one slot in minutes, between 5 and 1440, default 30')]
    property IntervalMinutes: Integer read FIntervalMinutes write FIntervalMinutes;
  end;

  // Calls Graph getSchedule itself: ICalendarClient.GetScheduleAvailability always asks for 30 minute slots.
  TCalendarAvailabilityTool = class(TMicrosoftTool<TCalendarAvailabilityParams, TCalendarAvailabilityResponse>)
  private
    class function ScheduleRequest(const Schedules: TArray<string>; const Moment: TCalendarMoment; const IntervalMinutes: Integer): string; static;
    class function ParseSchedule(const Schedule: TJSONObject; const Moment: TCalendarMoment; const IntervalMinutes: Integer): TScheduleAvailability; static;
    class function ParseItems(const Schedule: TJSONObject): TArray<TAvailabilityItem>; static;
    class function SlotsOf(const AvailabilityView: string; const Moment: TCalendarMoment; const IntervalMinutes: Integer): TArray<TAvailabilitySlot>; static;
    class function StatusOfDigit(const Digit: Char): string; static;

  protected
    function Run(const Params: TCalendarAvailabilityParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarAvailabilityResponse; override;

  public
    const ToolName = 'calendar_availability';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  MSGraph.Graph.JsonHelper,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Calendar.Support;

const
  DefaultInterval = 30;
  MinimumInterval = 5;
  MaximumInterval = 1440;
  ScheduleEndpoint = '/calendar/getSchedule';

resourcestring
  ToolDescription = 'Shows when people or rooms are free or busy in a period, in slots of a chosen length. Returns per schedule the ' +
                    'availability view, the slots and the calendar items Graph is willing to show. Times in the answer are ISO 8601 UTC.';
  NoSchedules = 'Give at least one e-mail address in "schedules".';
  FreeStatus = 'free';
  TentativeStatus = 'tentative';
  BusyStatus = 'busy';
  OutOfOfficeStatus = 'out_of_office';
  WorkingElsewhereStatus = 'working_elsewhere';
  UnknownStatus = 'unknown';

{ TCalendarAvailabilityTool }

constructor TCalendarAvailabilityTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TCalendarAvailabilityTool.Run(const Params: TCalendarAvailabilityParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarAvailabilityResponse;
begin
  const Schedules = TCalendarSupport.CleanAttendees(Params.Schedules);
  if Length(Schedules) = 0 then
    raise EToolArgumentError.Create(NoSchedules);

  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, '', True);

  var Interval := Params.IntervalMinutes;
  if Interval = 0 then
    Interval := DefaultInterval;
  Interval := Max(MinimumInterval, Min(MaximumInterval, Interval));

  const Answer = Graph.Post(Graph.GetUserPrefix + ScheduleEndpoint, ScheduleRequest(Schedules, Moment, Interval));
  try
    Result := TCalendarAvailabilityResponse.Create;
    Result.IntervalMinutes := Interval;
    Result.Note := Moment.Note;

    var Found: TArray<TScheduleAvailability> := [];
    const Values = TGraphJson.GetArray(Answer, 'value');
    if Assigned(Values) then
    begin
      for var Index := 0 to Values.Count - 1 do
      begin
        Found := Found + [ParseSchedule(TGraphJson.ArrayItem(Values, Index), Moment, Interval)];
      end;
    end;

    Result.Schedules := Found;
  finally
    Answer.Free;
  end;
end;

class function TCalendarAvailabilityTool.ScheduleRequest(const Schedules: TArray<string>; const Moment: TCalendarMoment; const IntervalMinutes: Integer): string;
begin
  const Request = TJSONObject.Create;
  try
    const Addresses = TJSONArray.Create;
    for var Schedule in Schedules do
    begin
      Addresses.Add(Schedule);
    end;
    Request.AddPair('schedules', Addresses);

    const StartObject = TJSONObject.Create;
    StartObject.AddPair('dateTime', TCalendarTime.ToGraph(Moment.Start));
    StartObject.AddPair('timeZone', TCalendarTime.Utc);
    Request.AddPair('startTime', StartObject);

    const EndObject = TJSONObject.Create;
    EndObject.AddPair('dateTime', TCalendarTime.ToGraph(Moment.Finish));
    EndObject.AddPair('timeZone', TCalendarTime.Utc);
    Request.AddPair('endTime', EndObject);

    Request.AddPair('availabilityViewInterval', TJSONNumber.Create(IntervalMinutes));

    Result := Request.ToJSON;
  finally
    Request.Free;
  end;
end;

class function TCalendarAvailabilityTool.ParseSchedule(const Schedule: TJSONObject; const Moment: TCalendarMoment; const IntervalMinutes: Integer): TScheduleAvailability;
begin
  Result := Default(TScheduleAvailability);
  Result.Schedule         := TGraphJson.GetString(Schedule, 'scheduleId');
  Result.AvailabilityView := TGraphJson.GetString(Schedule, 'availabilityView');
  Result.Slots            := SlotsOf(Result.AvailabilityView, Moment, IntervalMinutes);
  Result.Items            := ParseItems(Schedule);
end;

class function TCalendarAvailabilityTool.ParseItems(const Schedule: TJSONObject): TArray<TAvailabilityItem>;
begin
  Result := [];

  const Entries = TGraphJson.GetArray(Schedule, 'scheduleItems');
  if not Assigned(Entries) then
    Exit;

  for var Index := 0 to Entries.Count - 1 do
  begin
    const Entry = TGraphJson.ArrayItem(Entries, Index);

    var Item := Default(TAvailabilityItem);
    Item.Status  := TGraphJson.GetString(Entry, 'status');
    Item.Subject := TGraphJson.GetString(Entry, 'subject');

    const StartObject = TGraphJson.GetObject(Entry, 'start');
    if Assigned(StartObject) then
      Item.Start := TCalendarTime.FromGraph(TGraphJson.GetString(StartObject, 'dateTime'));

    const EndObject = TGraphJson.GetObject(Entry, 'end');
    if Assigned(EndObject) then
      Item.Finish := TCalendarTime.FromGraph(TGraphJson.GetString(EndObject, 'dateTime'));

    Result := Result + [Item];
  end;
end;

class function TCalendarAvailabilityTool.SlotsOf(const AvailabilityView: string; const Moment: TCalendarMoment; const IntervalMinutes: Integer): TArray<TAvailabilitySlot>;
begin
  Result := [];

  var SlotStart := Moment.Start;
  for var Digit in AvailabilityView do
  begin
    const SlotEnd = IncMinute(SlotStart, IntervalMinutes);

    var Slot := Default(TAvailabilitySlot);
    Slot.Start  := TCalendarTime.ToIso(SlotStart);
    Slot.Finish := TCalendarTime.ToIso(SlotEnd);
    Slot.Status := StatusOfDigit(Digit);
    Result := Result + [Slot];

    SlotStart := SlotEnd;
  end;
end;

class function TCalendarAvailabilityTool.StatusOfDigit(const Digit: Char): string;
begin
  case Digit of
    '0' : Result := FreeStatus;
    '1' : Result := TentativeStatus;
    '2' : Result := BusyStatus;
    '3' : Result := OutOfOfficeStatus;
    '4' : Result := WorkingElsewhereStatus;
  else
    Result := UnknownStatus;
  end;
end;

end.
