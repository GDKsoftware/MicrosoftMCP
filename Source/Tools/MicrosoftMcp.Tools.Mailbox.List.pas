unit MicrosoftMcp.Tools.Mailbox.List;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mailbox.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TListMailboxesResponse = class
  private
    FMailboxes: TArray<TMailboxItem>;
    FAccountPageUrl: string;

  public
    property Mailboxes: TArray<TMailboxItem> read FMailboxes write FMailboxes;

    [SchemaName('account_page_url')]
    [SchemaDescription('Where the user links or reconnects a Microsoft account')]
    property AccountPageUrl: string read FAccountPageUrl write FAccountPageUrl;
  end;

  TListMailboxesTool = class(TMicrosoftUserTool<TNoToolParams, TListMailboxesResponse>)
  protected
    function Run(const Params: TNoToolParams; const UserId: string): TListMailboxesResponse; override;

  public
    const ToolName = 'list_mailboxes';

    constructor Create(const Services: IToolServices);
  end;

implementation

resourcestring
  ToolDescription = 'Lists the mailboxes of the user by short name, with their state. A row with status "available" is a linked account ' +
                    'whose own mailbox is not added yet; add it with mailbox_add, using the suggested short name. ' +
                    'A row with status account_unlinked or reconnect_required needs the user to visit the account page.';

{ TListMailboxesTool }

constructor TListMailboxesTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(False);
end;

function TListMailboxesTool.Run(const Params: TNoToolParams; const UserId: string): TListMailboxesResponse;
begin
  const Rows = FServices.Mailboxes.List(UserId) + FServices.Mailboxes.ListAvailable(UserId);

  var Items: TArray<TMailboxItem> := [];
  for var Row in Rows do
  begin
    Items := Items + [TMailboxItem.FromRow(Row)];
  end;

  Result := TListMailboxesResponse.Create;
  Result.Mailboxes := Items;
  Result.AccountPageUrl := FServices.AccountPageUrl;
end;

end.
