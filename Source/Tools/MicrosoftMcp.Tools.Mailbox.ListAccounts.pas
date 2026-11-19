unit MicrosoftMcp.Tools.Mailbox.ListAccounts;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mailbox.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TListAccountsResponse = class
  private
    FAccounts: TArray<TAccountItem>;
    FAccountPageUrl: string;

  public
    property Accounts: TArray<TAccountItem> read FAccounts write FAccounts;

    [SchemaName('account_page_url')]
    [SchemaDescription('Where the user links another Microsoft account or reconnects one')]
    property AccountPageUrl: string read FAccountPageUrl write FAccountPageUrl;
  end;

  TListAccountsTool = class(TMicrosoftUserTool<TNoToolParams, TListAccountsResponse>)
  protected
    function Run(const Params: TNoToolParams; const UserId: string): TListAccountsResponse; override;

  public
    const ToolName = 'list_accounts';

    constructor Create(const Services: IToolServices);
  end;

implementation

resourcestring
  ToolDescription = 'Lists the Microsoft accounts the user has linked, and the URL of the account page where the user links another one. ' +
                    'A mailbox (own or shared) is always reached through one of these accounts.';

{ TListAccountsTool }

constructor TListAccountsTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(False);
end;

function TListAccountsTool.Run(const Params: TNoToolParams; const UserId: string): TListAccountsResponse;
begin
  var Items: TArray<TAccountItem> := [];
  for var Account in FServices.Mailboxes.ListAccounts(UserId) do
  begin
    Items := Items + [TAccountItem.FromAccount(Account)];
  end;

  Result := TListAccountsResponse.Create;
  Result.Accounts := Items;
  Result.AccountPageUrl := FServices.AccountPageUrl;
end;

end.
