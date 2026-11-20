unit MicrosoftMcp.Tools.Calendar.Get;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarGetTool = class(TMicrosoftTool<TEventParams, TCalendarEventResponse>)
  protected
    function Run(const Params: TEventParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarEventResponse; override;

  public
    const ToolName = 'calendar_get';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Calendar.Support;

resourcestring
  ToolDescription = 'Reads one event of a mailbox calendar in full: time, location, organizer, attendees with their responses and the body. ' +
                    'Times in the answer are ISO 8601 UTC.';

{ TCalendarGetTool }

constructor TCalendarGetTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TCalendarGetTool.Run(const Params: TEventParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarEventResponse;
begin
  Result := TCalendarEventResponse.From(TCalendarSupport.Client(Graph).GetEvent(Params.EventId));
end;

end.
