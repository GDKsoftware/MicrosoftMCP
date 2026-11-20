unit MicrosoftMcp.Mailbox.Resolver;

interface

uses
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

type
  TMailboxResolver = class(TInterfacedObject, IMailboxResolver)
  private
    FMailboxes: IMailboxRepository;
    FAccounts: IUpstreamAccounts;
    FAccountPageUrl: string;

    function GetMailbox(const UserId, Slug: string): TMailbox;
    function DescribeMailboxes(const UserId: string): string;
    function GetAccount(const Mailbox: TMailbox): TRemoteAccount;
    function GetAccessToken(const Mailbox: TMailbox): string;

  public
    constructor Create(const Mailboxes: IMailboxRepository; const Accounts: IUpstreamAccounts; const AccountPageUrl: string);

    function Resolve(const UserId, Slug: string): TResolvedMailbox;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  MCPAuth.Client.UpstreamAccounts.Exceptions,
  MicrosoftMcp.Mailbox.Exceptions;

resourcestring
  UnknownMailboxFormat = 'There is no mailbox with the short name "%s". Available mailboxes: %s.';
  NoMailboxes = 'none yet, add one with mailbox_add';
  MailboxDescriptionFormat = '"%s" (%s)';
  UnlinkedFormat = 'The Microsoft account behind mailbox "%s" is not linked (any more). Ask the user to link it again on the account page: %s';
  NeedsReconnectFormat = 'The Microsoft account behind mailbox "%s" needs to be reconnected (reason: %s). Ask the user to reconnect it on the account page: %s';
  UnknownReason = 'unknown';
  ForbiddenFormat = 'The user has not given this server access to their linked accounts. Ask the user to allow it on the account page: %s';

{ TMailboxResolver }

constructor TMailboxResolver.Create(const Mailboxes: IMailboxRepository; const Accounts: IUpstreamAccounts; const AccountPageUrl: string);
begin
  inherited Create;

  FMailboxes := Mailboxes;
  FAccounts := Accounts;
  FAccountPageUrl := AccountPageUrl;
end;

function TMailboxResolver.Resolve(const UserId, Slug: string): TResolvedMailbox;
begin
  Result.Mailbox := GetMailbox(UserId, Slug);
  Result.Account := GetAccount(Result.Mailbox);
  Result.AccessToken := GetAccessToken(Result.Mailbox);
end;

function TMailboxResolver.GetMailbox(const UserId, Slug: string): TMailbox;
begin
  const IsFound = FMailboxes.TryGet(UserId, Slug, Result);
  if not IsFound then
    raise EMailboxUnknown.CreateFmt(UnknownMailboxFormat, [Slug, DescribeMailboxes(UserId)]);
end;

function TMailboxResolver.DescribeMailboxes(const UserId: string): string;
begin
  var Descriptions: TArray<string> := [];
  for var Mailbox in FMailboxes.ListForUser(UserId) do
  begin
    Descriptions := Descriptions + [Format(MailboxDescriptionFormat, [Mailbox.Slug, Mailbox.DisplayName])];
  end;

  const HasMailboxes = (Length(Descriptions) > 0);
  if HasMailboxes then
    Result := string.Join(', ', Descriptions)
  else
    Result := NoMailboxes;
end;

function TMailboxResolver.GetAccount(const Mailbox: TMailbox): TRemoteAccount;
begin
  var Accounts: TArray<TRemoteAccount>;
  try
    Accounts := FAccounts.ListForUser(Mailbox.UserId);
  except
    on EUpstreamAccessForbidden do
    begin
      raise EMailboxAccessForbidden.CreateFmt(ForbiddenFormat, [FAccountPageUrl]);
    end;
  end;

  for var Account in Accounts do
  begin
    if Account.Key = Mailbox.AccountKey then
      Exit(Account);
  end;

  raise EMailboxAccountUnlinked.CreateFmt(UnlinkedFormat, [Mailbox.Slug, FAccountPageUrl]);
end;

function TMailboxResolver.GetAccessToken(const Mailbox: TMailbox): string;
begin
  try
    Result := FAccounts.GetAccessToken(Mailbox.UserId, Mailbox.AccountKey);
  except
    on EUpstreamAccountNotFound do
    begin
      raise EMailboxAccountUnlinked.CreateFmt(UnlinkedFormat, [Mailbox.Slug, FAccountPageUrl]);
    end;
    on Error: EUpstreamAccountNeedsReconnect do
    begin
      const Reason = IfThen(Error.Reason.IsEmpty, UnknownReason, Error.Reason);
      raise EMailboxNeedsReconnect.CreateFmt(NeedsReconnectFormat, [Mailbox.Slug, Reason, FAccountPageUrl]);
    end;
    on EUpstreamAccessForbidden do
    begin
      raise EMailboxAccessForbidden.CreateFmt(ForbiddenFormat, [FAccountPageUrl]);
    end;
  end;
end;

end.
