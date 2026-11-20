unit MicrosoftMcp.Tools.SharePoint.ReadPage;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.SharePoint.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TSharePointReadPageParams = class(TSiteParams)
  private
    FPageId: string;

  public
    [SchemaName('page_id')]
    [SchemaDescription('Id of the page, from sharepoint_list_pages')]
    property PageId: string read FPageId write FPageId;
  end;

  TSharePointReadPageTool = class(TMicrosoftTool<TSharePointReadPageParams, TPageContentResponse>)
  protected
    function Run(const Params: TSharePointReadPageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPageContentResponse; override;

  public
    const ToolName = 'sharepoint_read_page';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

resourcestring
  ToolDescription = 'Reads one page of a SharePoint site as HTML. The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TSharePointReadPageTool }

constructor TSharePointReadPageTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointReadPageTool.Run(const Params: TSharePointReadPageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPageContentResponse;
begin
  TAccountSupport.UseOwnAccount(Graph);
  const Page = TFilesSupport.SharePointClient(Graph).GetSitePageContent(Params.SiteId, Params.PageId);

  Result := TPageContentResponse.From(Page, TAccountSupport.Note(Mailbox));
end;

end.
