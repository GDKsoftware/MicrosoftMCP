unit MicrosoftMcp.Mailbox.Resolver.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport,
  MicrosoftMcp.Fakes.UpstreamAccounts;

type
  [TestFixture]
  TMailboxResolverTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FResolver: IMailboxResolver;
    FFactory: IGraphClientFactory;

    procedure AddMailbox(const UserId, Slug, DisplayName, Address, AccountKey: string);
    procedure AddAccount(const UserId, AccountKey, AccessToken: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure ResolvesOwnMailboxWithToken;

    [Test]
    procedure UnknownSlugErrorListsAvailableMailboxes;

    [Test]
    procedure UnknownSlugWithoutMailboxesSaysSo;

    [Test]
    procedure SlugOfOtherUserIsUnknown;

    [Test]
    procedure MailboxWithUnlinkedAccountGivesClearError;

    [Test]
    procedure AccountMissingFromListGivesClearError;

    [Test]
    procedure NeedsReconnectPointsToAccountPage;

    [Test]
    procedure ForbiddenAccessPointsToAccountPage;

    [Test]
    procedure SharedMailboxUsesUsersPath;

    [Test]
    procedure OwnMailboxUsesMePath;
  end;

implementation

uses
  System.SysUtils,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MCPAuth.Client.UpstreamAccounts.Exceptions,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Exceptions,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Mailbox.Resolver,
  MicrosoftMcp.Graph.ClientFactory;

const
  Kees = 'user-kees';
  Anna = 'user-anna';
  KeesAccountKey = 'acc-kees';
  AccountPage = 'https://auth.example.test/account';
  KeesToken = 'token-of-kees';

{ TMailboxResolverTests }

procedure TMailboxResolverTests.Setup;
begin
  FMailboxes := TMailboxStoreMemory.Create;

  FAccounts := TFakeUpstreamAccounts.Create;
  FAccountsInterface := FAccounts;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;

  FResolver := TMailboxResolver.Create(FMailboxes, FAccounts, AccountPage);
  FFactory := TGraphClientFactory.Create(FTransport);

  AddAccount(Kees, KeesAccountKey, KeesToken);
  AddMailbox(Kees, 'prive', 'Prive Outlook', '', KeesAccountKey);
  AddMailbox(Kees, 'projects', 'Projects team', 'projects@example.test', KeesAccountKey);
end;

procedure TMailboxResolverTests.TearDown;
begin
  FFactory := nil;
  FResolver := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TMailboxResolverTests.AddMailbox(const UserId, Slug, DisplayName, Address, AccountKey: string);
begin
  var Mailbox := Default(TMailbox);
  Mailbox.UserId := UserId;
  Mailbox.Slug := Slug;
  Mailbox.DisplayName := DisplayName;
  Mailbox.Address := Address;
  Mailbox.AccountKey := AccountKey;
  Mailbox.CreatedAtUtc := Now;
  if Address.IsEmpty then
    Mailbox.Kind := TMailboxKind.Own
  else
    Mailbox.Kind := TMailboxKind.Shared;

  FMailboxes.Save(Mailbox);
end;

procedure TMailboxResolverTests.AddAccount(const UserId, AccountKey, AccessToken: string);
begin
  var Account := Default(TRemoteAccount);
  Account.Key := AccountKey;
  Account.Provider := 'microsoft';
  Account.DisplayName := 'Account';

  FAccounts.AddAccount(UserId, Account, AccessToken);
end;

procedure TMailboxResolverTests.ResolvesOwnMailboxWithToken;
begin
  const Resolved = FResolver.Resolve(Kees, 'prive');

  Assert.AreEqual('prive', Resolved.Mailbox.Slug);
  Assert.AreEqual(KeesAccountKey, Resolved.Account.Key);
  Assert.AreEqual(KeesToken, Resolved.AccessToken);
end;

procedure TMailboxResolverTests.UnknownSlugErrorListsAvailableMailboxes;
begin
  var Message := '';
  try
    FResolver.Resolve(Kees, 'priv'#$00E9);
  except
    on Error: EMailboxUnknown do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.Contains(Message, 'prive');
  Assert.Contains(Message, 'Prive Outlook');
  Assert.Contains(Message, 'projects');
  Assert.Contains(Message, 'Projects team');
end;

procedure TMailboxResolverTests.UnknownSlugWithoutMailboxesSaysSo;
begin
  var Message := '';
  try
    FResolver.Resolve('user-without-mailboxes', 'prive');
  except
    on Error: EMailboxUnknown do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.Contains(Message, 'mailbox_add');
end;

procedure TMailboxResolverTests.SlugOfOtherUserIsUnknown;
begin
  AddAccount(Anna, 'acc-anna', 'token-of-anna');
  AddMailbox(Anna, 'secret', 'Annas private mail', '', 'acc-anna');

  var Message := '';
  try
    FResolver.Resolve(Kees, 'secret');
  except
    on Error: EMailboxUnknown do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.IsNotEmpty(Message, 'EMailboxUnknown expected');
  Assert.DoesNotContain(Message, 'Annas private mail');
  Assert.DoesNotContain(Message, 'token-of-anna');
end;

procedure TMailboxResolverTests.MailboxWithUnlinkedAccountGivesClearError;
begin
  FAccounts.FailGetAccessTokenWith(
    function: Exception
    begin
      Result := EUpstreamAccountNotFound.Create('gone');
    end);

  var Message := '';
  try
    FResolver.Resolve(Kees, 'prive');
  except
    on Error: EMailboxAccountUnlinked do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.Contains(Message, AccountPage);
  Assert.Contains(Message, 'prive');
end;

procedure TMailboxResolverTests.AccountMissingFromListGivesClearError;
begin
  AddMailbox(Kees, 'orphan', 'Orphan', '', 'acc-removed');

  Assert.WillRaise(
    procedure
    begin
      FResolver.Resolve(Kees, 'orphan');
    end,
    EMailboxAccountUnlinked);
end;

procedure TMailboxResolverTests.NeedsReconnectPointsToAccountPage;
begin
  FAccounts.FailGetAccessTokenWith(
    function: Exception
    begin
      Result := EUpstreamAccountNeedsReconnect.Create('missing_scopes');
    end);

  var Message := '';
  try
    FResolver.Resolve(Kees, 'prive');
  except
    on Error: EMailboxNeedsReconnect do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.Contains(Message, AccountPage);
  Assert.Contains(Message, 'missing_scopes');
end;

procedure TMailboxResolverTests.ForbiddenAccessPointsToAccountPage;
begin
  FAccounts.FailListWith(
    function: Exception
    begin
      Result := EUpstreamAccessForbidden.Create('no access');
    end);

  var Message := '';
  try
    FResolver.Resolve(Kees, 'prive');
  except
    on Error: EMailboxAccessForbidden do
    begin
      Message := Error.Message;
    end;
  end;

  Assert.Contains(Message, AccountPage);
end;

procedure TMailboxResolverTests.SharedMailboxUsesUsersPath;
begin
  FTransport.Respond(200, '{"id":"x"}');
  const Resolved = FResolver.Resolve(Kees, 'projects');

  const Client = FFactory.Create(Resolved);
  try
    Client.Get(Client.GetUserPrefix + '/messages').Free;
  finally
    Client.Free;
  end;

  Assert.Contains(FTransport.LastRequest.Url, '/users/projects@example.test/messages');
  Assert.DoesNotContain(FTransport.LastRequest.Url, '/me/');
end;

procedure TMailboxResolverTests.OwnMailboxUsesMePath;
begin
  FTransport.Respond(200, '{"id":"x"}');
  const Resolved = FResolver.Resolve(Kees, 'prive');

  const Client = FFactory.Create(Resolved);
  try
    Client.Get(Client.GetUserPrefix + '/messages').Free;
  finally
    Client.Free;
  end;

  Assert.Contains(FTransport.LastRequest.Url, '/me/messages');
  Assert.DoesNotContain(FTransport.LastRequest.Url, '/users/');
end;

end.
