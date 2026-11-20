unit MicrosoftMcp.Tools.SharePoint.SearchFiles;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.SharePoint.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TSharePointSearchFilesParams = class(TSiteParams)
  private
    FQuery: string;

  public
    [SchemaDescription('Text to search for in file names and content')]
    property Query: string read FQuery write FQuery;
  end;

  TSharePointSearchFilesTool = class(TMicrosoftTool<TSharePointSearchFilesParams, TFileListResponse>)
  protected
    function Run(const Params: TSharePointSearchFilesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse; override;

  public
    const ToolName = 'sharepoint_search_files';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Support,
  MSGraph.Graph.SharePoint.Types,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  PageSize = 25;

resourcestring
  ToolDescription = 'Searches the files of the default document library of a SharePoint site. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  QueryMissing = 'Give the text to search for in query.';

{ TSharePointSearchFilesTool }

constructor TSharePointSearchFilesTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointSearchFilesTool.Run(const Params: TSharePointSearchFilesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse;
begin
  if Params.Query.Trim.IsEmpty then
    raise EToolArgumentError.Create(QueryMissing);

  TAccountSupport.UseOwnAccount(Graph);
  const Found = TFilesSupport.SharePointClient(Graph).SearchDriveItems(Params.SiteId, TToolSupport.ODataString(Params.Query), PageSize);

  var Entries: TArray<TFileEntry> := [];
  for var Item in Found do
  begin
    Entries := Entries + [TFileEntry.FromDriveItem(Item)];
  end;

  const HasMore = (Length(Found) >= PageSize);
  Result := TFileListResponse.From(Entries, HasMore, TAccountSupport.Note(Mailbox));
end;

end.
