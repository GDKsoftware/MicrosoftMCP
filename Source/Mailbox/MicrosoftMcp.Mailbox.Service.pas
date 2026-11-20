unit MicrosoftMcp.Mailbox.Service;

interface

uses
  Spring.Collections,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Access.Interfaces,
  MicrosoftMcp.Mailbox.Service.Interfaces;

type
  TMailboxService = class(TInterfacedObject, IMailboxService)
  private
    FMailboxes: IMailboxRepository;
    FAccounts: IUpstreamAccounts;
    FAccess: IMailboxAccess;
    FAccountPageUrl: string;

    class function TryFindAccount(const Accounts: TArray<TRemoteAccount>; const AccountKey: string; out Account: TRemoteAccount): Boolean; static;
    class function HasOwnMailbox(const Mailboxes: IReadOnlyList<TMailbox>; const AccountKey: string): Boolean; static;
    class function UniqueSlug(const Text: string; const TakenSlugs: ISet<string>): string; static;
    class function WithSuffix(const BaseSlug: string; const Number: Integer): string; static;

    function RowOf(const Mailbox: TMailbox; const Accounts: TArray<TRemoteAccount>): TMailboxRow;
    function AvailableRowOf(const UserId: string; const Account: TRemoteAccount; const TakenSlugs: ISet<string>): TMailboxRow;
    function TakenSlugsOf(const UserId: string): ISet<string>;
    function DescribeMailboxes(const UserId: string): string;
    function DescribeAccounts(const Accounts: TArray<TRemoteAccount>): string;
    function NewMailbox(const UserId: string; const Account: TRemoteAccount; const Kind: TMailboxKind; const Address, Slug, DisplayName: string): TMailbox;
    function SuggestedSlug(const UserId: string; const Account: TRemoteAccount; const Kind: TMailboxKind; const Address: string): string;
    function GetAccessToken(const UserId: string; const Account: TRemoteAccount): string;
    procedure GuardAddress(const Kind: TMailboxKind; const Address: string);
    procedure GuardSlugValid(const Slug: string);
    procedure GuardSlugFree(const UserId, Slug: string);
    procedure GuardAccessible(const Mailbox: TMailbox; const AccessToken: string);

  public
    constructor Create(const Mailboxes: IMailboxRepository; const Accounts: IUpstreamAccounts; const Access: IMailboxAccess; const AccountPageUrl: string);

    function ListAccounts(const UserId: string): TArray<TRemoteAccount>;
    function List(const UserId: string): TArray<TMailboxRow>;
    function ListAvailable(const UserId: string): TArray<TMailboxRow>;
    function Get(const UserId, Slug: string): TMailbox;
    function GetAccount(const UserId, KeyOrUserName: string): TRemoteAccount;
    function Add(const UserId, AccountKey: string; const Kind: TMailboxKind; const Address, Slug, DisplayName: string): TMailbox;
    function Rename(const UserId, Slug, NewSlug, DisplayName: string): TMailbox;
    procedure Remove(const UserId, Slug: string);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.DateUtils,
  MCPAuth.Client.UpstreamAccounts.Exceptions,
  MicrosoftMcp.Mailbox.Exceptions,
  MicrosoftMcp.Mailbox.Slug;

const
  ListSeparator = ', ';
  SuffixFormat = '%s-%d';
  FirstSuffix = 2;

resourcestring
  ForbiddenFormat = 'The user has not given this server access to their linked accounts. Ask the user to allow it on the account page: %s';
  UnknownMailboxFormat = 'There is no mailbox with the short name "%s". Available mailboxes: %s.';
  NoMailboxes = 'none yet, add one with mailbox_add';
  MailboxDescriptionFormat = '"%s" (%s)';
  UnknownAccountFormat = 'There is no linked Microsoft account "%s". Linked accounts: %s. To link another account, the user can use the account page: %s';
  NoAccounts = 'none yet';
  AccountDescriptionFormat = '%s (key %s)';
  AccountGoneFormat = 'The Microsoft account "%s" is not linked (any more). Ask the user to link it again on the account page: %s';
  ReconnectFormat = 'The Microsoft account "%s" needs to be reconnected (reason: %s). Ask the user to reconnect it on the account page: %s';
  UnknownReason = 'unknown';
  AddressMissing = 'A shared mailbox needs its e-mail address: pass the parameter address.';
  InvalidSlugFormat = 'The short name "%s" is not valid: use 1 to 32 lowercase letters, digits and "-", starting with a letter or digit, for example "%s".';
  SlugTakenFormat = 'The short name "%s" is already used by another mailbox of this user. Choose another one, for example "%s".';
  NothingToRename = 'Pass a new short name (new_slug), a new display name (display_name) or both.';

{ TMailboxService }

class function TMailboxService.TryFindAccount(const Accounts: TArray<TRemoteAccount>; const AccountKey: string; out Account: TRemoteAccount): Boolean;
begin
  for var Candidate in Accounts do
  begin
    if Candidate.Key = AccountKey then
    begin
      Account := Candidate;
      Exit(True);
    end;
  end;

  Account := Default(TRemoteAccount);
  Result := False;
end;

class function TMailboxService.HasOwnMailbox(const Mailboxes: IReadOnlyList<TMailbox>; const AccountKey: string): Boolean;
begin
  for var Mailbox in Mailboxes do
  begin
    const IsOwnOfAccount = ((Mailbox.Kind = TMailboxKind.Own) and (Mailbox.AccountKey = AccountKey));
    if IsOwnOfAccount then
      Exit(True);
  end;

  Result := False;
end;

class function TMailboxService.UniqueSlug(const Text: string; const TakenSlugs: ISet<string>): string;
begin
  const BaseSlug = TMailboxSlug.Suggest(Text);

  Result := BaseSlug;
  var Number := FirstSuffix;
  while TakenSlugs.Contains(Result) do
  begin
    Result := WithSuffix(BaseSlug, Number);
    Inc(Number);
  end;
end;

class function TMailboxService.WithSuffix(const BaseSlug: string; const Number: Integer): string;
begin
  const Suffix = Format(SuffixFormat, ['', Number]);
  const RoomForBase = TMailboxSlug.MaxLength - Suffix.Length;
  const ShortenedBase = BaseSlug.Substring(0, RoomForBase).TrimRight(['-']);

  Result := Format(SuffixFormat, [ShortenedBase, Number]);
end;

constructor TMailboxService.Create(const Mailboxes: IMailboxRepository; const Accounts: IUpstreamAccounts; const Access: IMailboxAccess; const AccountPageUrl: string);
begin
  inherited Create;

  FMailboxes := Mailboxes;
  FAccounts := Accounts;
  FAccess := Access;
  FAccountPageUrl := AccountPageUrl;
end;

function TMailboxService.ListAccounts(const UserId: string): TArray<TRemoteAccount>;
begin
  try
    Result := FAccounts.ListForUser(UserId);
  except
    on EUpstreamAccessForbidden do
    begin
      raise EMailboxAccessForbidden.CreateFmt(ForbiddenFormat, [FAccountPageUrl]);
    end;
  end;
end;

function TMailboxService.List(const UserId: string): TArray<TMailboxRow>;
begin
  const Accounts = ListAccounts(UserId);

  Result := [];
  for var Mailbox in FMailboxes.ListForUser(UserId) do
  begin
    Result := Result + [RowOf(Mailbox, Accounts)];
  end;
end;

function TMailboxService.RowOf(const Mailbox: TMailbox; const Accounts: TArray<TRemoteAccount>): TMailboxRow;
begin
  Result := Default(TMailboxRow);
  Result.Mailbox := Mailbox;

  var Account: TRemoteAccount;
  const IsLinked = TryFindAccount(Accounts, Mailbox.AccountKey, Account);
  if not IsLinked then
  begin
    Result.Status := TMailboxStatus.AccountUnlinked;
    Exit;
  end;

  Result.AccountUserName := Account.UserName;
  if Account.NeedsReconnect then
    Result.Status := TMailboxStatus.ReconnectRequired
  else
    Result.Status := TMailboxStatus.Ok;
end;

function TMailboxService.ListAvailable(const UserId: string): TArray<TMailboxRow>;
begin
  const Accounts = ListAccounts(UserId);
  const Mailboxes = FMailboxes.ListForUser(UserId);
  const TakenSlugs = TakenSlugsOf(UserId);

  Result := [];
  for var Account in Accounts do
  begin
    if not HasOwnMailbox(Mailboxes, Account.Key) then
      Result := Result + [AvailableRowOf(UserId, Account, TakenSlugs)];
  end;
end;

function TMailboxService.AvailableRowOf(const UserId: string; const Account: TRemoteAccount; const TakenSlugs: ISet<string>): TMailboxRow;
begin
  Result := Default(TMailboxRow);
  Result.Mailbox.UserId      := UserId;
  Result.Mailbox.Slug        := UniqueSlug(Account.UserName, TakenSlugs);
  Result.Mailbox.DisplayName := IfThen(Account.DisplayName.IsEmpty, Account.UserName, Account.DisplayName);
  Result.Mailbox.AccountKey  := Account.Key;
  Result.Mailbox.Kind        := TMailboxKind.Own;
  Result.AccountUserName     := Account.UserName;
  Result.Status              := TMailboxStatus.Available;

  // Two available accounts must not get the same suggestion.
  TakenSlugs.Add(Result.Mailbox.Slug);
end;

function TMailboxService.TakenSlugsOf(const UserId: string): ISet<string>;
begin
  Result := TCollections.CreateSet<string>;
  for var Mailbox in FMailboxes.ListForUser(UserId) do
  begin
    Result.Add(Mailbox.Slug);
  end;
end;

function TMailboxService.Get(const UserId, Slug: string): TMailbox;
begin
  const IsFound = FMailboxes.TryGet(UserId, Slug, Result);
  if not IsFound then
    raise EMailboxUnknown.CreateFmt(UnknownMailboxFormat, [Slug, DescribeMailboxes(UserId)]);
end;

function TMailboxService.DescribeMailboxes(const UserId: string): string;
begin
  var Descriptions: TArray<string> := [];
  for var Mailbox in FMailboxes.ListForUser(UserId) do
  begin
    Descriptions := Descriptions + [Format(MailboxDescriptionFormat, [Mailbox.Slug, Mailbox.DisplayName])];
  end;

  const HasMailboxes = (Length(Descriptions) > 0);
  if HasMailboxes then
    Result := string.Join(ListSeparator, Descriptions)
  else
    Result := NoMailboxes;
end;

function TMailboxService.GetAccount(const UserId, KeyOrUserName: string): TRemoteAccount;
begin
  const Accounts = ListAccounts(UserId);

  const IsKey = TryFindAccount(Accounts, KeyOrUserName, Result);
  if IsKey then
    Exit;

  for var Account in Accounts do
  begin
    if SameText(Account.UserName, KeyOrUserName) then
      Exit(Account);
  end;

  raise EMailboxAccountUnknown.CreateFmt(UnknownAccountFormat, [KeyOrUserName, DescribeAccounts(Accounts), FAccountPageUrl]);
end;

function TMailboxService.DescribeAccounts(const Accounts: TArray<TRemoteAccount>): string;
begin
  var Descriptions: TArray<string> := [];
  for var Account in Accounts do
  begin
    Descriptions := Descriptions + [Format(AccountDescriptionFormat, [Account.UserName, Account.Key])];
  end;

  const HasAccounts = (Length(Descriptions) > 0);
  if HasAccounts then
    Result := string.Join(ListSeparator, Descriptions)
  else
    Result := NoAccounts;
end;

function TMailboxService.Add(const UserId, AccountKey: string; const Kind: TMailboxKind; const Address, Slug, DisplayName: string): TMailbox;
begin
  const Accounts = ListAccounts(UserId);

  var Account: TRemoteAccount;
  const IsLinked = TryFindAccount(Accounts, AccountKey, Account);
  if not IsLinked then
    raise EMailboxAccountUnknown.CreateFmt(UnknownAccountFormat, [AccountKey, DescribeAccounts(Accounts), FAccountPageUrl]);

  GuardAddress(Kind, Address);

  Result := NewMailbox(UserId, Account, Kind, Address, Slug, DisplayName);
  GuardSlugValid(Result.Slug);
  GuardSlugFree(UserId, Result.Slug);

  const AccessToken = GetAccessToken(UserId, Account);
  GuardAccessible(Result, AccessToken);

  FMailboxes.Save(Result);
end;

procedure TMailboxService.GuardAddress(const Kind: TMailboxKind; const Address: string);
begin
  const IsSharedWithoutAddress = ((Kind = TMailboxKind.Shared) and Address.Trim.IsEmpty);
  if IsSharedWithoutAddress then
    raise EMailboxInvalidInput.Create(AddressMissing);
end;

function TMailboxService.NewMailbox(const UserId: string; const Account: TRemoteAccount; const Kind: TMailboxKind; const Address, Slug, DisplayName: string): TMailbox;
begin
  const IsShared = (Kind = TMailboxKind.Shared);

  Result := Default(TMailbox);
  Result.UserId       := UserId;
  Result.AccountKey   := Account.Key;
  Result.Kind         := Kind;
  Result.Address      := IfThen(IsShared, Address.Trim, '');
  Result.CreatedAtUtc := TDateTime.NowUTC;

  if Slug.IsEmpty then
    Result.Slug := SuggestedSlug(UserId, Account, Kind, Result.Address)
  else
    Result.Slug := Slug;

  if not DisplayName.Trim.IsEmpty then
    Result.DisplayName := DisplayName.Trim
  else if IsShared then
    Result.DisplayName := Result.Address
  else if not Account.DisplayName.IsEmpty then
    Result.DisplayName := Account.DisplayName
  else
    Result.DisplayName := Account.UserName;
end;

function TMailboxService.SuggestedSlug(const UserId: string; const Account: TRemoteAccount; const Kind: TMailboxKind; const Address: string): string;
begin
  const IsShared = (Kind = TMailboxKind.Shared);
  const Source = IfThen(IsShared, Address, Account.UserName);

  Result := UniqueSlug(Source, TakenSlugsOf(UserId));
end;

procedure TMailboxService.GuardSlugValid(const Slug: string);
begin
  if not TMailboxSlug.IsValid(Slug) then
    raise EMailboxInvalidInput.CreateFmt(InvalidSlugFormat, [Slug, TMailboxSlug.Suggest(Slug)]);
end;

procedure TMailboxService.GuardSlugFree(const UserId, Slug: string);
begin
  const TakenSlugs = TakenSlugsOf(UserId);
  if TakenSlugs.Contains(Slug) then
    raise EMailboxSlugTaken.CreateFmt(SlugTakenFormat, [Slug, UniqueSlug(Slug, TakenSlugs)]);
end;

function TMailboxService.GetAccessToken(const UserId: string; const Account: TRemoteAccount): string;
begin
  try
    Result := FAccounts.GetAccessToken(UserId, Account.Key);
  except
    on EUpstreamAccountNotFound do
    begin
      raise EMailboxAccountUnlinked.CreateFmt(AccountGoneFormat, [Account.UserName, FAccountPageUrl]);
    end;
    on Error: EUpstreamAccountNeedsReconnect do
    begin
      const Reason = IfThen(Error.Reason.IsEmpty, UnknownReason, Error.Reason);
      raise EMailboxNeedsReconnect.CreateFmt(ReconnectFormat, [Account.UserName, Reason, FAccountPageUrl]);
    end;
    on EUpstreamAccessForbidden do
    begin
      raise EMailboxAccessForbidden.CreateFmt(ForbiddenFormat, [FAccountPageUrl]);
    end;
  end;
end;

procedure TMailboxService.GuardAccessible(const Mailbox: TMailbox; const AccessToken: string);
begin
  const Access = FAccess.Check(Mailbox, AccessToken);
  if not Access.IsAccessible then
    raise EMailboxNotAccessible.Create(Access.Message);
end;

function TMailboxService.Rename(const UserId, Slug, NewSlug, DisplayName: string): TMailbox;
begin
  const HasChange = (not NewSlug.IsEmpty or not DisplayName.Trim.IsEmpty);
  if not HasChange then
    raise EMailboxInvalidInput.Create(NothingToRename);

  Result := Get(UserId, Slug);

  const IsSlugChanged = (not NewSlug.IsEmpty and (NewSlug <> Slug));
  if IsSlugChanged then
  begin
    GuardSlugValid(NewSlug);
    GuardSlugFree(UserId, NewSlug);
    Result.Slug := NewSlug;
  end;

  if not DisplayName.Trim.IsEmpty then
    Result.DisplayName := DisplayName.Trim;

  FMailboxes.Rename(UserId, Slug, Result.Slug, Result.DisplayName);
end;

procedure TMailboxService.Remove(const UserId, Slug: string);
begin
  Get(UserId, Slug);
  FMailboxes.Delete(UserId, Slug);
end;

end.
