unit MicrosoftMcp.Tools.Mailbox.Add;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mailbox.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailboxAddParams = class
  private
    FAccount: string;
    FKind: string;
    FAddress: string;
    FSlug: string;
    FDisplayName: string;

  public
    [SchemaDescription('The linked Microsoft account to reach the mailbox through: its key or its user name, see list_accounts')]
    property Account: string read FAccount write FAccount;

    [SchemaDescription('own for the mailbox of the account itself, shared for a shared mailbox the account has FullAccess to')]
    [SchemaEnum('own', 'shared')]
    property Kind: string read FKind write FKind;

    [Optional]
    [SchemaDescription('E-mail address of the shared mailbox; required when kind is shared')]
    property Address: string read FAddress write FAddress;

    [Optional]
    [SchemaDescription('Short name: lowercase letters, digits and "-", at most 32 characters; leave empty for the suggested one')]
    property Slug: string read FSlug write FSlug;

    [Optional]
    [SchemaName('display_name')]
    [SchemaDescription('Name shown to the user; leave empty for the name of the account or the address')]
    property DisplayName: string read FDisplayName write FDisplayName;
  end;

  TMailboxChangeResponse = class
  private
    FMailbox: TMailboxItem;

  public
    property Mailbox: TMailboxItem read FMailbox write FMailbox;
  end;

  TMailboxAddTool = class(TMicrosoftUserTool<TMailboxAddParams, TMailboxChangeResponse>)
  protected
    function Run(const Params: TMailboxAddParams; const UserId: string): TMailboxChangeResponse; override;

  public
    const ToolName = 'mailbox_add';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Service.Interfaces;

resourcestring
  ToolDescription = 'Adds a mailbox under a short name: the own mailbox of a linked account, or a shared mailbox reached through one. ' +
                    'The server first checks that it can read the inbox and refuses the mailbox when it cannot.';

{ TMailboxAddTool }

constructor TMailboxAddTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailboxAddTool.Run(const Params: TMailboxAddParams; const UserId: string): TMailboxChangeResponse;
begin
  const Account = FServices.Mailboxes.GetAccount(UserId, Params.Account);
  const Kind = TMailboxKind.Parse(Params.Kind);
  const Mailbox = FServices.Mailboxes.Add(UserId, Account.Key, Kind, Params.Address, Params.Slug, Params.DisplayName);

  var Row := Default(TMailboxRow);
  Row.Mailbox := Mailbox;
  Row.AccountUserName := Account.UserName;
  Row.Status := TMailboxStatus.Ok;

  Result := TMailboxChangeResponse.Create;
  Result.Mailbox := TMailboxItem.FromRow(Row);
end;

end.
