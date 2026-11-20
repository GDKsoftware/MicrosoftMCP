unit MicrosoftMcp.Tools.SharePoint.ListFiles;

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
  TSharePointListFilesParams = class(TSiteParams)
  private
    FFolderId: string;

  public
    [Optional]
    [SchemaName('folder_id')]
    [SchemaDescription('Id of the folder to list, from an earlier listing; empty lists the root of the document library')]
    property FolderId: string read FFolderId write FFolderId;
  end;

  TSharePointListFilesTool = class(TMicrosoftTool<TSharePointListFilesParams, TFileListResponse>)
  protected
    function Run(const Params: TSharePointListFilesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse; override;

  public
    const ToolName = 'sharepoint_list_files';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MSGraph.Graph.SharePoint.Types,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  PageSize = 50;

resourcestring
  ToolDescription = 'Lists the files and folders of the default document library of a SharePoint site, or of one folder in it. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TSharePointListFilesTool }

constructor TSharePointListFilesTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointListFilesTool.Run(const Params: TSharePointListFilesParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse;
begin
  TAccountSupport.UseOwnAccount(Graph);
  const Found = TFilesSupport.SharePointClient(Graph).ListDriveItems(Params.SiteId, Params.FolderId, PageSize);

  var Entries: TArray<TFileEntry> := [];
  for var Item in Found do
  begin
    Entries := Entries + [TFileEntry.FromDriveItem(Item)];
  end;

  const HasMore = (Length(Found) >= PageSize);
  Result := TFileListResponse.From(Entries, HasMore, TAccountSupport.Note(Mailbox));
end;

end.
