unit MicrosoftMcp.Tools.Calendar.Create;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarCreateParams = class(TConfirmableToolParams)
  private
    FSubject: string;
    FStartTime: string;
    FEndTime: string;
    FTimeZone: string;
    FLocation: string;
    FBody: string;
    FAttendees: TArray<string>;
    FIsOnlineMeeting: Boolean;

  public
    property Subject: string read FSubject write FSubject;

    [SchemaName('start')]
    [SchemaDescription('Start, ISO 8601 with offset, for example 2026-11-20T09:00:00+01:00. Without offset UTC is assumed, unless time_zone is given')]
    property StartTime: string read FStartTime write FStartTime;

    [SchemaName('end')]
    [SchemaDescription('End, ISO 8601 with offset. Without offset UTC is assumed, unless time_zone is given')]
    property EndTime: string read FEndTime write FEndTime;

    [Optional]
    [SchemaName('time_zone')]
    [SchemaDescription('Time zone name, for example Europe/Amsterdam, in which a start and end without offset are meant')]
    property TimeZone: string read FTimeZone write FTimeZone;

    [Optional]
    property Location: string read FLocation write FLocation;

    [Optional]
    [SchemaDescription('Description of the event (HTML is allowed)')]
    property Body: string read FBody write FBody;

    [Optional]
    [SchemaDescription('E-mail addresses of the people to invite. Inviting people sends them an invitation and needs confirmation')]
    property Attendees: TArray<string> read FAttendees write FAttendees;

    [Optional]
    [SchemaName('is_online_meeting')]
    [SchemaDescription('true adds a Teams meeting')]
    property IsOnlineMeeting: Boolean read FIsOnlineMeeting write FIsOnlineMeeting;
  end;

  TCalendarCreateTool = class(TConfirmedMicrosoftTool<TCalendarCreateParams, TCalendarActionResponse>)
  protected
    function NeedsConfirmation(const Params: TCalendarCreateParams): Boolean; override;
    function Summarize(const Params: TCalendarCreateParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TCalendarCreateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse; override;

  public
    const ToolName = 'calendar_create';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Calendar.Types,
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tools.Calendar.Support;

resourcestring
  ToolDescription = 'Creates an event in a mailbox calendar. Without attendees it is created at once. With attendees they receive an ' +
                    'invitation, which needs confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Create the event "%s" (%s) in mailbox %s and send an invitation to %s.';
  CreatedStatus = 'created';

{ TCalendarCreateTool }

constructor TCalendarCreateTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, True);
end;

function TCalendarCreateTool.NeedsConfirmation(const Params: TCalendarCreateParams): Boolean;
begin
  Result := (Length(TCalendarSupport.CleanAttendees(Params.Attendees)) > 0);
end;

function TCalendarCreateTool.Summarize(const Params: TCalendarCreateParams; const Mailbox: TResolvedMailbox): string;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, Params.TimeZone, True);
  const Attendees = string.Join(', ', TCalendarSupport.CleanAttendees(Params.Attendees));

  Result := Format(SummaryFormat, [Params.Subject, Moment.Describe, TMailSupport.MailboxLabel(Mailbox), Attendees]);
  if Moment.AssumedUtc then
    Result := Result + ' ' + Moment.Note;
end;

function TCalendarCreateTool.Run(const Params: TCalendarCreateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, Params.TimeZone, True);

  const IsAllDay = False;
  const Created = TCalendarSupport.Client(Graph).CreateEvent(Params.Subject, Moment.Start, Moment.Finish, Params.Location, Params.Body,
                                                             TCalendarSupport.CleanAttendees(Params.Attendees), IsAllDay, Moment.TimeZone,
                                                             TEventSensitivity.Normal, Params.IsOnlineMeeting);

  Result := TCalendarActionResponse.From(CreatedStatus, Created, Moment.Note);
end;

end.
