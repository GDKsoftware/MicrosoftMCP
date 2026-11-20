unit MicrosoftMcp.Tools.SharePoint.ReadFile;

interface

uses
  System.Rtti,
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.SharePoint.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TSharePointReadFileParams = class(TSiteParams)
  private
    FItemId: string;

  public
    [SchemaName('item_id')]
    [SchemaDescription('Id of the file, from sharepoint_list_files or sharepoint_search_files')]
    property ItemId: string read FItemId write FItemId;
  end;

  // The content itself is a text block or an embedded resource; the structured content only describes it.
  TSharePointReadFileTool = class(TMicrosoftTool<TSharePointReadFileParams, TFileReadInfo>)
  protected
    function RunValue(const Params: TSharePointReadFileParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue; override;

  public
    const ToolName = 'sharepoint_read_file';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  FolderType = 'folder';

resourcestring
  ToolDescription = 'Reads a file of a SharePoint site: text files come back as text, other files (Word, Excel, PDF, images) as an ' +
                    'embedded resource with their MIME type. Files over 10 MB are refused. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  IsFolder = 'The item "%s" is a folder; list it with sharepoint_list_files and read one of its files.';

{ TSharePointReadFileTool }

constructor TSharePointReadFileTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TSharePointReadFileTool.RunValue(const Params: TSharePointReadFileParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue;
begin
  TAccountSupport.UseOwnAccount(Graph);
  const SharePoint = TFilesSupport.SharePointClient(Graph);

  const Item = SharePoint.GetDriveItemContent(Params.SiteId, Params.ItemId);
  if Item.ItemType = FolderType then
    raise EToolError.CreateFmt(IsFolder, [Item.Name]);

  // The metadata is cheap; fetching the content of a large file is not, so the size is checked first.
  TFilesSupport.GuardSize(Item.Name, Item.Size);

  const Bytes = SharePoint.DownloadDriveItemBytes(Params.SiteId, Item);
  TFilesSupport.GuardSize(Item.Name, Length(Bytes));

  Result := TFilesSupport.ReadResult(Item.Name, Item.MimeType, Bytes, TAccountSupport.Note(Mailbox));
end;

end.
