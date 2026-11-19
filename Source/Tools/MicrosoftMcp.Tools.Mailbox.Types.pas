unit MicrosoftMcp.Tools.Mailbox.Types;

interface

uses
  MCPServer.Types,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Service.Interfaces;

type
  // A mailbox as the mailbox tools show it.
  TMailboxItem = record
    [SchemaDescription('Short name; pass it as the mailbox parameter of the other tools')]
    Slug: string;

    [SchemaName('display_name')]
    DisplayName: string;

    [SchemaDescription('E-mail address; for an own mailbox the user name of the account')]
    Address: string;

    [SchemaDescription('own or shared')]
    Kind: string;

    [SchemaDescription('User name of the Microsoft account the mailbox is reached through; its key when the account is no longer linked')]
    Account: string;

    [SchemaDescription('ok, account_unlinked, reconnect_required, or available for a linked account that is not added yet')]
    Status: string;

    class function FromRow(const Row: TMailboxRow): TMailboxItem; static;
  end;

  TAccountItem = record
    [SchemaDescription('Key of the account; mailbox_add accepts it as account')]
    Key: string;

    [SchemaName('display_name')]
    DisplayName: string;

    [SchemaName('user_name')]
    UserName: string;

    [SchemaName('needs_reconnect')]
    NeedsReconnect: Boolean;

    class function FromAccount(const Account: TRemoteAccount): TAccountItem; static;
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Types;

{ TMailboxItem }

class function TMailboxItem.FromRow(const Row: TMailboxRow): TMailboxItem;
begin
  const IsOwn = (Row.Mailbox.Kind = TMailboxKind.Own);
  const HasAccountUserName = not Row.AccountUserName.IsEmpty;

  Result := Default(TMailboxItem);
  Result.Slug        := Row.Mailbox.Slug;
  Result.DisplayName := Row.Mailbox.DisplayName;
  Result.Kind        := Row.Mailbox.Kind.Code;
  Result.Status      := Row.Status.Code;

  if IsOwn then
    Result.Address := Row.AccountUserName
  else
    Result.Address := Row.Mailbox.Address;

  if HasAccountUserName then
    Result.Account := Row.AccountUserName
  else
    Result.Account := Row.Mailbox.AccountKey;
end;

{ TAccountItem }

class function TAccountItem.FromAccount(const Account: TRemoteAccount): TAccountItem;
begin
  Result := Default(TAccountItem);
  Result.Key            := Account.Key;
  Result.DisplayName    := Account.DisplayName;
  Result.UserName       := Account.UserName;
  Result.NeedsReconnect := Account.NeedsReconnect;
end;

end.
