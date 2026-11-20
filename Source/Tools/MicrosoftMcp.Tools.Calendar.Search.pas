unit MicrosoftMcp.Tools.Calendar.Search;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Calendar.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TCalendarSearchParams = class(TMicrosoftToolParams)
  private
    FQuery: string;
    FStartTime: string;
    FEndTime: string;

  public
    [SchemaDescription('Text to look for in the subject or body of the events')]
    property Query: string read FQuery write FQuery;

    [Optional]
    [SchemaName('start')]
    [SchemaDescription('Start of the period to search, ISO 8601 with offset. Default: 30 days ago')]
    property StartTime: string read FStartTime write FStartTime;

    [Optional]
    [SchemaName('end')]
    [SchemaDescription('End of the period to search, ISO 8601 with offset. Default: 90 days ahead')]
    property EndTime: string read FEndTime write FEndTime;
  end;

  TCalendarSearchTool = class(TMicrosoftTool<TCalendarSearchParams, TCalendarListResponse>)
  protected
    function Run(const Params: TCalendarSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarListResponse; override;

  public
    const ToolName = 'calendar_search';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Calendar.Time,
  MicrosoftMcp.Tools.Calendar.Support;

const
  DaysBack = 30;
  DaysAhead = 90;
  MaximumEvents = 100;

resourcestring
  ToolDescription = 'Searches the events of a mailbox calendar by text in the subject or body, within a period (default: 30 days back to ' +
                    '90 days ahead). Returns at most 100 events. Times in the answer are ISO 8601 UTC.';
  QueryRequired = 'The parameter "query" is required.';
  RangeReversed = 'The parameter "end" must be later than "start".';

{ TCalendarSearchTool }

constructor TCalendarSearchTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TCalendarSearchTool.Run(const Params: TCalendarSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TCalendarListResponse;
begin
  if Params.Query.Trim.IsEmpty then
    raise EToolArgumentError.Create(QueryRequired);

  const Moment = TCalendarTime.Resolve(Params.StartTime, Params.EndTime, '', False);
  const NowUtc = TTimeZone.Local.ToUniversalTime(Now);

  var Start := Moment.Start;
  if Start = 0 then
    Start := IncDay(NowUtc, -DaysBack);

  var Finish := Moment.Finish;
  if Finish = 0 then
    Finish := IncDay(NowUtc, DaysAhead);

  const IsReversed = (Finish <= Start);
  if IsReversed then
    raise EToolArgumentError.Create(RangeReversed);

  const Found = TCalendarSupport.Client(Graph).SearchEvents(Params.Query, Start, Finish, TCalendarTime.Utc, True);

  const HasMore = (Length(Found) > MaximumEvents);
  Result := TCalendarListResponse.From(Copy(Found, 0, MaximumEvents), HasMore, Moment.Note);
end;

end.
