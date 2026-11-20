unit MicrosoftMcp.Tools.SharePoint.ListPages;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.SharePoint.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TSharePointListPagesParams = class(TSiteParams)
  private
    FTop: Integer;

  public
    [Optional]
    [SchemaDescription('Number of pages to return, default 25, at most 100')]
    property Top: Integer read FTop write FTop;
  end;

  TSharePointListPagesTool = class(TMicrosoftTool<TSharePointListPagesParams, TPagesResponse>)
  protected
    function Run(const Params: TSharePointListPagesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPagesResponse; override;

  public
    const ToolName = 'sharepoint_list_pages';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

resourcestring
  ToolDescription = 'Lists the pages of a SharePoint site. The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TSharePointListPagesTool }

constructor TSharePointListPagesTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointListPagesTool.Run(const Params: TSharePointListPagesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPagesResponse;
begin
  TAccountSupport.UseOwnAccount(Graph);
  const Pages = TFilesSupport.SharePointClient(Graph).ListSitePages(Params.SiteId, Params.Top);

  Result := TPagesResponse.From(Pages, TAccountSupport.Note(Mailbox));
end;

end.
