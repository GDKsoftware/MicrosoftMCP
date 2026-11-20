unit MicrosoftMcp.Tools.SharePoint.SearchSites;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.SharePoint.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TSharePointSearchSitesParams = class(TMicrosoftToolParams)
  private
    FQuery: string;

  public
    [Optional]
    [SchemaDescription('Text to search for in site names; empty lists the sites that Graph returns first')]
    property Query: string read FQuery write FQuery;
  end;

  TSharePointSearchSitesTool = class(TMicrosoftTool<TSharePointSearchSitesParams, TSitesResponse>)
  protected
    function Run(const Params: TSharePointSearchSitesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TSitesResponse; override;

  public
    const ToolName = 'sharepoint_search_sites';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

resourcestring
  ToolDescription = 'Searches the SharePoint sites the account can see. The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TSharePointSearchSitesTool }

constructor TSharePointSearchSitesTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointSearchSitesTool.Run(const Params: TSharePointSearchSitesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TSitesResponse;
begin
  TAccountSupport.UseOwnAccount(Graph);
  const Sites = TFilesSupport.SharePointClient(Graph).ListSites(Params.Query);

  Result := TSitesResponse.From(Sites, TAccountSupport.Note(Mailbox));
end;

end.
