unit MicrosoftMcp.Tools.Mail.List;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailListParams = class(TMicrosoftToolParams)
  private
    FFolder: string;
    FTop: Integer;
    FUnreadOnly: Boolean;

  public
    [Optional]
    [SchemaDescription('Folder: inbox (default), archive, deleteditems, junkemail, drafts, sentitems or a folder id from mail_list_folders')]
    property Folder: string read FFolder write FFolder;

    [Optional]
    [SchemaDescription('Number of messages to return, default 25, at most 100')]
    property Top: Integer read FTop write FTop;

    [Optional]
    [SchemaName('unread_only')]
    [SchemaDescription('Only unread messages (at most 50)')]
    property UnreadOnly: Boolean read FUnreadOnly write FUnreadOnly;
  end;

  TMailListTool = class(TMicrosoftTool<TMailListParams, TMailListResponse>)
  protected
    function Run(const Params: TMailListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListResponse; override;

  public
    const ToolName = 'mail_list';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Mail.Types,
  MicrosoftMcp.Tools.Mail.Support;

const
  DefaultFolder = 'inbox';
  UnreadQuery = 'is:unread';

resourcestring
  ToolDescription = 'Lists the newest messages of a folder, without their bodies (id, subject, sender, date, read state, attachment flag ' +
                    'and a short preview). Read a message in full with mail_read.';

{ TMailListTool }

constructor TMailListTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailListTool.Run(const Params: TMailListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListResponse;
begin
  const Top = TMailSupport.ClampTop(Params.Top);

  var Folder := Params.Folder;
  if Folder.Trim.IsEmpty then
    Folder := DefaultFolder;

  const FolderId = TMailSupport.FolderId(Folder);
  const Mail = TMailSupport.Client(Graph);

  var SearchResult: TSearchMessagesResult;
  if Params.UnreadOnly then
    SearchResult := Mail.SearchMessages(UnreadQuery, FolderId, Top, 0)
  else
    SearchResult := Mail.ListFolderMessages(FolderId, Top, 0);

  Result := TMailListResponse.FromResult(SearchResult);
end;

end.
