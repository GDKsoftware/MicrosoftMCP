unit MicrosoftMcp.Tools.Mail.Search;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.GraphId,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailSearchParams = class(TMicrosoftToolParams)
  private
    FQuery: string;
    FFolder: string;
    FTop: Integer;

  public
    [SchemaDescription('What to search for, as in the Outlook search box. Use "is:unread" for unread mail; "*" or empty lists the newest mail')]
    property Query: string read FQuery write FQuery;

    [Optional]
    [GraphId]
    [SchemaDescription('Folder to search: inbox, archive, deleteditems, junkemail, drafts, sentitems or a folder id from mail_list_folders. Empty searches the whole mailbox; for a shared mailbox it searches the inbox')]
    property Folder: string read FFolder write FFolder;

    [Optional]
    [SchemaDescription('Number of messages to return, default 25, at most 100 (the search itself returns at most 50)')]
    property Top: Integer read FTop write FTop;
  end;

  TMailSearchTool = class(TMicrosoftTool<TMailSearchParams, TMailListResponse>)
  protected
    function Run(const Params: TMailSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListResponse; override;

  public
    const ToolName = 'mail_search';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Support,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Searches the mail of a mailbox and returns the matching messages without their bodies (id, subject, sender, ' +
                    'date, read state, attachment flag and a short preview). Read a message in full with mail_read.';

{ TMailSearchTool }

constructor TMailSearchTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailSearchTool.Run(const Params: TMailSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListResponse;
begin
  const Top = TMailSupport.ClampTop(Params.Top);
  const FolderId = TMailSupport.FolderId(Params.Folder);

  const SearchResult = TMailSupport.Client(Graph).SearchMessages(TToolSupport.SearchPhrase(Params.Query), FolderId, Top, 0);

  Result := TMailListResponse.FromResult(SearchResult);
end;

end.
