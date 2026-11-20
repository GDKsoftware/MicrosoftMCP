unit MicrosoftMcp.Tools.Calendar.List;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarListParams = class(TMicrosoftToolParams)
  private
    FStartTime: string;
    FEndTime: string;
    FTop: Integer;

  public
    [SchemaName('start')]
    [SchemaDescription('Start of the period, ISO 8601 with offset, for example 2026-11-20T00:00:00+01:00. Without offset UTC is assumed')]
    property StartTime: string read FStartTime write FStartTime;

    [SchemaName('end')]
    [SchemaDescription('End of the period, ISO 8601 with offset. Without offset UTC is assumed')]
    property EndTime: string read FEndTime write FEndTime;

    [Optional]
    [SchemaDescription('Number of events to return, default 50, at most 100')]
    property Top: Integer read FTop write FTop;
  end;

  TCalendarListTool = class(TMicrosoftTool<TCalendarListParams, TCalendarListResponse>)
  protected
    function Run(const Params: TCalendarListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarListResponse; override;

  public
    const ToolName = 'calendar_list';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tools.Calendar.Support;

const
  DefaultTop = 50;
  MaximumTop = 100;

resourcestring
  ToolDescription = 'Lists the events of a mailbox calendar between two moments, in time order. Times in the answer are ISO 8601 UTC.';

{ TCalendarListTool }

constructor TCalendarListTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TCalendarListTool.Run(const Params: TCalendarListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarListResponse;
begin
  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, '', True);

  var Top := Params.Top;
  if Top < 1 then
    Top := DefaultTop;
  if Top > MaximumTop then
    Top := MaximumTop;

  const Events = TCalendarSupport.Client(Graph).ListEvents(Moment.Start, Moment.Finish, Top, TCalendarTime.Utc);

  const HasMore = (Length(Events) >= Top);
  Result := TCalendarListResponse.From(Events, HasMore, Moment.Note);
end;

end.
