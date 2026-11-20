unit MicrosoftMcp.Tools.Calendar.Respond;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarRespondParams = class(TConfirmableToolParams)
  private
    FEventId: string;
    FResponse: string;
    FComment: string;
    FSendResponse: Boolean;

  public
    constructor Create;

    [SchemaName('event_id')]
    [SchemaDescription('Id of the event, from calendar_list or calendar_search')]
    property EventId: string read FEventId write FEventId;

    [SchemaEnum('accept', 'decline', 'tentative')]
    [SchemaDescription('accept, decline or tentative')]
    property Response: string read FResponse write FResponse;

    [Optional]
    [SchemaDescription('Text that goes with the response to the organizer')]
    property Comment: string read FComment write FComment;

    [Optional]
    [SchemaName('send_response')]
    [SchemaDescription('true (default) sends the response to the organizer, which needs confirmation; false only records it in the calendar')]
    property SendResponse: Boolean read FSendResponse write FSendResponse;
  end;

  TCalendarRespondTool = class(TConfirmedMicrosoftTool<TCalendarRespondParams, TCalendarActionResponse>)
  private
    type
      TAnswer = (Accept, Decline, Tentative);

    class function ParseAnswer(const Response: string): TAnswer; static;
    class function AnswerText(const Answer: TAnswer): string; static;

  protected
    function NeedsConfirmation(const Params: TCalendarRespondParams): Boolean; override;
    function Summarize(const Params: TCalendarRespondParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TCalendarRespondParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse; override;

  public
    const ToolName = 'calendar_respond';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Calendar.Support;

resourcestring
  ToolDescription = 'Answers an invitation in a mailbox calendar: accept, decline or tentative. By default the response is sent to the ' +
                    'organizer, which needs confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = '%s the invitation %s in mailbox %s and send the response to the organizer%s.';
  CommentFormat = ' with the comment "%s"';
  UnknownResponse = 'The parameter "response" must be accept, decline or tentative, not "%s".';
  AcceptText = 'Accept';
  DeclineText = 'Decline';
  TentativeText = 'Tentatively accept';
  RecordedStatus = 'recorded in the calendar';
  SentStatus = 'sent to the organizer';

const
  AcceptValue = 'accept';
  DeclineValue = 'decline';
  TentativeValue = 'tentative';

{ TCalendarRespondParams }

constructor TCalendarRespondParams.Create;
begin
  inherited Create;

  FSendResponse := True;
end;

{ TCalendarRespondTool }

constructor TCalendarRespondTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

class function TCalendarRespondTool.ParseAnswer(const Response: string): TAnswer;
begin
  const Value = Response.Trim.ToLower;

  if Value = AcceptValue then
    Exit(TAnswer.Accept);
  if Value = DeclineValue then
    Exit(TAnswer.Decline);
  if Value = TentativeValue then
    Exit(TAnswer.Tentative);

  raise EToolArgumentError.CreateFmt(UnknownResponse, [Response]);
end;

class function TCalendarRespondTool.AnswerText(const Answer: TAnswer): string;
begin
  case Answer of
    TAnswer.Accept    : Result := AcceptText;
    TAnswer.Decline   : Result := DeclineText;
    TAnswer.Tentative : Result := TentativeText;
  else
    raise ENotSupportedException.CreateFmt(UnknownResponse, [IntToStr(Ord(Answer))]);
  end;
end;

function TCalendarRespondTool.NeedsConfirmation(const Params: TCalendarRespondParams): Boolean;
begin
  ParseAnswer(Params.Response);

  Result := Params.SendResponse;
end;

function TCalendarRespondTool.Summarize(const Params: TCalendarRespondParams; const Mailbox: TResolvedMailbox): string;
begin
  const Answer = ParseAnswer(Params.Response);
  const Event = TCalendarSupport.LoadEvent(FServices.GraphClients, Mailbox, Params.EventId);

  var CommentText := '';
  if not Params.Comment.Trim.IsEmpty then
    CommentText := Format(CommentFormat, [Params.Comment]);

  Result := Format(SummaryFormat, [AnswerText(Answer), TCalendarSupport.EventText(Event), TMailSupport.MailboxLabel(Mailbox), CommentText]);
end;

function TCalendarRespondTool.Run(const Params: TCalendarRespondParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse;
begin
  const Answer = ParseAnswer(Params.Response);
  const Calendar = TCalendarSupport.Client(Graph);

  case Answer of
    TAnswer.Accept    : Calendar.AcceptEvent(Params.EventId, Params.Comment, Params.SendResponse);
    TAnswer.Decline   : Calendar.DeclineEvent(Params.EventId, Params.Comment, Params.SendResponse);
    TAnswer.Tentative : Calendar.TentativelyAcceptEvent(Params.EventId, Params.Comment, Params.SendResponse);
  else
    raise ENotSupportedException.CreateFmt(UnknownResponse, [IntToStr(Ord(Answer))]);
  end;

  if Params.SendResponse then
    Result := TCalendarActionResponse.Done(SentStatus, '')
  else
    Result := TCalendarActionResponse.Done(RecordedStatus, '');
end;

end.
