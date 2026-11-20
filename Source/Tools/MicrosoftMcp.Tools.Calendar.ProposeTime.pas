unit MicrosoftMcp.Tools.Calendar.ProposeTime;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarProposeTimeParams = class(TConfirmedEventParams)
  private
    FStartTime: string;
    FEndTime: string;
    FComment: string;

  public
    [SchemaName('start')]
    [SchemaDescription('Proposed start, ISO 8601 with offset. Without offset UTC is assumed')]
    property StartTime: string read FStartTime write FStartTime;

    [SchemaName('end')]
    [SchemaDescription('Proposed end, ISO 8601 with offset')]
    property EndTime: string read FEndTime write FEndTime;

    [Optional]
    [SchemaDescription('Text that goes with the proposal')]
    property Comment: string read FComment write FComment;
  end;

  TCalendarProposeTimeTool = class(TConfirmedMicrosoftTool<TCalendarProposeTimeParams, TCalendarActionResponse>)
  protected
    function Summarize(const Params: TCalendarProposeTimeParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TCalendarProposeTimeParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse; override;

  public
    const ToolName = 'calendar_propose_time';

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
  ToolDescription = 'Proposes another time for an invitation: the organizer gets a tentative response with the new time. It needs ' +
                    'confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Propose %s instead of the current time for the event %s in mailbox %s; the organizer receives the proposal.';
  ProposedStatus = 'proposal sent to the organizer';

{ TCalendarProposeTimeTool }

constructor TCalendarProposeTimeTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TCalendarProposeTimeTool.Summarize(const Params: TCalendarProposeTimeParams; const Mailbox: TResolvedMailbox): string;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, '', True);
  const Event = TCalendarSupport.LoadEvent(FServices.GraphClients, Mailbox, Params.EventId);

  Result := Format(SummaryFormat, [Moment.Describe, TCalendarSupport.EventText(Event), TMailSupport.MailboxLabel(Mailbox)]);
end;

function TCalendarProposeTimeTool.Run(const Params: TCalendarProposeTimeParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, '', True);

  var NewTime := Default(TProposedNewTime);
  NewTime.StartDateTime := TCalendarTime.ToGraph(Moment.Start);
  NewTime.EndDateTime   := TCalendarTime.ToGraph(Moment.Finish);
  NewTime.TimeZone      := TCalendarTime.Utc;

  const SendResponse = True;
  TCalendarSupport.Client(Graph).ProposeNewTime(Params.EventId, NewTime, Params.Comment, SendResponse);

  Result := TCalendarActionResponse.Done(ProposedStatus, Moment.Note);
end;

end.
