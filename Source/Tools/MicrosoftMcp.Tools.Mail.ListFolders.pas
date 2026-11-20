unit MicrosoftMcp.Tools.Mail.ListFolders;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MSGraph.Graph.Mail.Types,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TMailListFoldersParams = class(TMicrosoftToolParams)
  private
    FParentFolderId: string;

  public
    [Optional]
    [GraphId]
    [SchemaName('parent_folder_id')]
    [SchemaDescription('List the subfolders of this folder (an id, or inbox, archive, ...). Empty lists the top-level folders')]
    property ParentFolderId: string read FParentFolderId write FParentFolderId;
  end;

  TMailFolderItem = record
    Id: string;

    [SchemaName('display_name')]
    DisplayName: string;

    [SchemaName('child_folder_count')]
    ChildFolderCount: Integer;

    [SchemaName('total_item_count')]
    TotalItemCount: Integer;

    [SchemaName('unread_item_count')]
    UnreadItemCount: Integer;

    class function FromFolder(const Folder: TMailFolder): TMailFolderItem; static;
  end;

  TMailListFoldersResponse = class
  private
    FFolders: TArray<TMailFolderItem>;

  public
    property Folders: TArray<TMailFolderItem> read FFolders write FFolders;
  end;

  TMailListFoldersTool = class(TMicrosoftTool<TMailListFoldersParams, TMailListFoldersResponse>)
  protected
    function Run(const Params: TMailListFoldersParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListFoldersResponse; override;

  public
    const ToolName = 'mail_list_folders';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Lists the mail folders of a mailbox with their id and the number of (unread) messages. The well-known folders ' +
                    'can also be addressed by name: inbox, archive, deleteditems, junkemail, drafts and sentitems.';

{ TMailFolderItem }

class function TMailFolderItem.FromFolder(const Folder: TMailFolder): TMailFolderItem;
begin
  Result.Id               := Folder.Id;
  Result.DisplayName      := Folder.DisplayName;
  Result.ChildFolderCount := Folder.ChildFolderCount;
  Result.TotalItemCount   := Folder.TotalItemCount;
  Result.UnreadItemCount  := Folder.UnreadItemCount;
end;

{ TMailListFoldersTool }

constructor TMailListFoldersTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailListFoldersTool.Run(const Params: TMailListFoldersParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListFoldersResponse;
begin
  const ParentId = TMailSupport.FolderId(Params.ParentFolderId);
  const Folders = TMailSupport.Client(Graph).ListMailFolders(ParentId);

  var Items: TArray<TMailFolderItem> := [];
  for var Folder in Folders do
  begin
    Items := Items + [TMailFolderItem.FromFolder(Folder)];
  end;

  Result := TMailListFoldersResponse.Create;
  Result.Folders := Items;
end;

end.
