unit MicrosoftMcp.Mailbox.Service.Interfaces;

interface

uses
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Types;

{$SCOPEDENUMS ON}

type
  // Available is a linked account that has no own mailbox yet; its row carries a suggested short name.
  TMailboxStatus = (Ok, AccountUnlinked, ReconnectRequired, Available);

  TMailboxStatusHelper = record helper for TMailboxStatus
    function Code: string;
  end;

  TMailboxRow = record
    Mailbox: TMailbox;
    // Empty when the account is no longer linked.
    AccountUserName: string;
    Status: TMailboxStatus;
  end;

  // Managing the mailboxes of one user. Errors are EMailboxError descendants with a message written for Claude.
  IMailboxService = interface
    ['{D47B2E95-6A13-4C8F-9E20-5B1F8A3C7D69}']
    function ListAccounts(const UserId: string): TArray<TRemoteAccount>;

    // The stored mailboxes, oldest first, each with the state of its account.
    function List(const UserId: string): TArray<TMailboxRow>;

    // A row per linked account without an own mailbox, with a free suggested short name.
    function ListAvailable(const UserId: string): TArray<TMailboxRow>;

    // Raises EMailboxUnknown with the available mailboxes in the message.
    function Get(const UserId, Slug: string): TMailbox;

    // KeyOrUserName is the key of a linked account (exact) or its user name (case-insensitive).
    // Raises EMailboxAccountUnknown with the linked accounts in the message.
    function GetAccount(const UserId, KeyOrUserName: string): TRemoteAccount;

    // An empty Slug takes the suggested one, an empty DisplayName that of the account or the address.
    // Checks access through Graph first and raises EMailboxNotAccessible without storing anything.
    function Add(const UserId, AccountKey: string; const Kind: TMailboxKind; const Address, Slug, DisplayName: string): TMailbox;

    // An empty NewSlug keeps the short name, an empty DisplayName the display name.
    function Rename(const UserId, Slug, NewSlug, DisplayName: string): TMailbox;

    procedure Remove(const UserId, Slug: string);
  end;

implementation

uses
  System.SysUtils;

const
  OkCode = 'ok';
  AccountUnlinkedCode = 'account_unlinked';
  ReconnectRequiredCode = 'reconnect_required';
  AvailableCode = 'available';

{ TMailboxStatusHelper }

function TMailboxStatusHelper.Code: string;
begin
  case Self of
    TMailboxStatus.Ok                : Result := OkCode;
    TMailboxStatus.AccountUnlinked   : Result := AccountUnlinkedCode;
    TMailboxStatus.ReconnectRequired : Result := ReconnectRequiredCode;
    TMailboxStatus.Available         : Result := AvailableCode;
  else
    raise ENotSupportedException.CreateFmt('Unsupported mailbox status: %d', [Ord(Self)]);
  end;
end;

end.
