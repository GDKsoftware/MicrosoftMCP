unit MicrosoftMcp.Tools.Calendar.Update;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MSGraph.Graph.Calendar.Types,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarUpdateParams = class(TConfirmedEventParams)
  private
    FSubject: string;
    FStartTime: string;
    FEndTime: string;
    FTimeZone: string;
    FLocation: string;
    FAttendees: TArray<string>;
    FIsOnlineMeeting: Boolean;

  public
    [Optional]
    [SchemaDescription('New subject; leave out to keep the current one')]
    property Subject: string read FSubject write FSubject;

    [Optional]
    [SchemaName('start')]
    [SchemaDescription('New start, ISO 8601 with offset. Without offset UTC is assumed, unless time_zone is given')]
    property StartTime: string read FStartTime write FStartTime;

    [Optional]
    [SchemaName('end')]
    [SchemaDescription('New end, ISO 8601 with offset. Without offset UTC is assumed, unless time_zone is given')]
    property EndTime: string read FEndTime write FEndTime;

    [Optional]
    [SchemaName('time_zone')]
    [SchemaDescription('Time zone name, for example Europe/Amsterdam, in which a start and end without offset are meant')]
    property TimeZone: string read FTimeZone write FTimeZone;

    [Optional]
    [SchemaDescription('New location; leave out to keep the current one')]
    property Location: string read FLocation write FLocation;

    [Optional]
    [SchemaDescription('The complete new list of attendees (it replaces the current list); leave out to keep the current one')]
    property Attendees: TArray<string> read FAttendees write FAttendees;

    [Optional]
    [SchemaName('is_online_meeting')]
    [SchemaDescription('true adds a Teams meeting')]
    property IsOnlineMeeting: Boolean read FIsOnlineMeeting write FIsOnlineMeeting;
  end;

  TCalendarUpdateTool = class(TConfirmedMicrosoftTool<TCalendarUpdateParams, TCalendarActionResponse>)
  private
    class function ChangesOf(const Params: TCalendarUpdateParams; const Moment: TCalendarMoment): TEventChanges; static;
    class function ChangesText(const Params: TCalendarUpdateParams; const Moment: TCalendarMoment): string; static;

  protected
    function NeedsConfirmationIn(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox): Boolean; override;
    function Summarize(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse; override;

  public
    const ToolName = 'calendar_update';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Calendar.Support;

resourcestring
  ToolDescription = 'Changes an event in a mailbox calendar; only the fields you give are changed. When the event has attendees (or you add ' +
                    'some) they are notified, which needs confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Change the event %s in mailbox %s. Attendees: %s. Changes: %s.';
  NothingToChange = 'Give at least one field to change: subject, start, end, location, attendees or is_online_meeting.';
  SubjectChange = 'subject becomes "%s"';
  StartChange = 'start becomes %s';
  EndChange = 'end becomes %s';
  LocationChange = 'location becomes "%s"';
  AttendeesChange = 'the attendees become %s';
  OnlineChange = 'a Teams meeting is added';
  UpdatedStatus = 'updated';

{ TCalendarUpdateTool }

constructor TCalendarUpdateTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

class function TCalendarUpdateTool.ChangesOf(const Params: TCalendarUpdateParams; const Moment: TCalendarMoment): TEventChanges;
begin
  Result := Default(TEventChanges);
  Result.Subject         := Params.Subject.Trim;
  Result.StartDateTime   := Moment.Start;
  Result.EndDateTime     := Moment.Finish;
  Result.TimeZone        := Moment.TimeZone;
  Result.Location        := Params.Location.Trim;
  Result.Attendees       := TCalendarSupport.CleanAttendees(Params.Attendees);
  Result.IsOnlineMeeting := Params.IsOnlineMeeting;
end;

class function TCalendarUpdateTool.ChangesText(const Params: TCalendarUpdateParams; const Moment: TCalendarMoment): string;
begin
  const Changes = ChangesOf(Params, Moment);

  var Parts: TArray<string> := [];
  if not Changes.Subject.IsEmpty then
    Parts := Parts + [Format(SubjectChange, [Changes.Subject])];
  if Changes.StartDateTime <> 0 then
    Parts := Parts + [Format(StartChange, [Moment.Show(Changes.StartDateTime)])];
  if Changes.EndDateTime <> 0 then
    Parts := Parts + [Format(EndChange, [Moment.Show(Changes.EndDateTime)])];
  if not Changes.Location.IsEmpty then
    Parts := Parts + [Format(LocationChange, [Changes.Location])];
  if Length(Changes.Attendees) > 0 then
    Parts := Parts + [Format(AttendeesChange, [string.Join(', ', Changes.Attendees)])];
  if Changes.IsOnlineMeeting then
    Parts := Parts + [OnlineChange];

  if Length(Parts) = 0 then
    raise EToolArgumentError.Create(NothingToChange);

  Result := string.Join('; ', Parts);
end;

function TCalendarUpdateTool.NeedsConfirmationIn(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox): Boolean;
begin
  // Validates the input before anything is asked of Graph.
  ChangesText(Params, TCalendarTime.Resolve(Params.StartTime, Params.EndTime, Params.TimeZone, False));

  const AddsAttendees = (Length(TCalendarSupport.CleanAttendees(Params.Attendees)) > 0);
  if AddsAttendees then
    Exit(True);

  const Event = TCalendarSupport.LoadEvent(FServices.GraphClients, Mailbox, Params.EventId);
  Result := (Length(Event.Attendees) > 0);
end;

function TCalendarUpdateTool.Summarize(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox): string;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, Params.TimeZone, False);
  const Changes = ChangesText(Params, Moment);
  const Event = TCalendarSupport.LoadEvent(FServices.GraphClients, Mailbox, Params.EventId);

  Result := Format(SummaryFormat, [TCalendarSupport.EventText(Event), TMailSupport.MailboxLabel(Mailbox), TCalendarSupport.AttendeesText(Event.Attendees), Changes]);
  if Moment.AssumedUtc then
    Result := Result + ' ' + Moment.Note;
end;

function TCalendarUpdateTool.Run(const Params: TCalendarUpdateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, Params.TimeZone, False);
  ChangesText(Params, Moment);

  const Updated = TCalendarSupport.Client(Graph).ChangeEvent(Params.EventId, ChangesOf(Params, Moment));

  Result := TCalendarActionResponse.From(UpdatedStatus, Updated, Moment.Note);
end;

end.
