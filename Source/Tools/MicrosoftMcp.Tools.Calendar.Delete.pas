unit MicrosoftMcp.Tools.Calendar.Delete;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarDeleteTool = class(TConfirmedMicrosoftTool<TConfirmedEventParams, TCalendarActionResponse>)
  protected
    function Summarize(const Params: TConfirmedEventParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TConfirmedEventParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse; override;

  public
    const ToolName = 'calendar_delete';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Calendar.Support;

resourcestring
  ToolDescription = 'Deletes an event from a mailbox calendar. When the user organizes it, the attendees get a cancellation. It needs ' +
                    'confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Delete the event %s from mailbox %s. Attendees: %s. Attendees of an event you organize receive a cancellation.';
  DeletedStatus = 'deleted';

{ TCalendarDeleteTool }

constructor TCalendarDeleteTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TCalendarDeleteTool.Summarize(const Params: TConfirmedEventParams; const Mailbox: TResolvedMailbox): string;
begin
  const Event = TCalendarSupport.LoadEvent(FServices.GraphClients, Mailbox, Params.EventId);

  Result := Format(SummaryFormat, [TCalendarSupport.EventText(Event), TMailSupport.MailboxLabel(Mailbox), TCalendarSupport.AttendeesText(Event.Attendees)]);
end;

function TCalendarDeleteTool.Run(const Params: TConfirmedEventParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarActionResponse;
begin
  TCalendarSupport.Client(Graph).DeleteEvent(Params.EventId);

  Result := TCalendarActionResponse.Done(DeletedStatus, '');
end;

end.
