unit MicrosoftMcp.Tools.Mailbox.Tests;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport,
  MicrosoftMcp.Fakes.UpstreamAccounts;

type
  [TestFixture]
  TMailboxToolsTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    procedure AddAccount(const Key, UserName, DisplayName: string; const NeedsReconnect: Boolean);
    procedure AddMailbox(const Slug, AccountKey: string; const Kind: TMailboxKind; const Address: string);
    function Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function FindMailbox(const Mailboxes: TJSONArray; const Slug: string): TJSONObject;
    function StoredSlugs: string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure ListAccountsReturnsLinkedAccountsAndAccountPage;

    [Test]
    procedure ListMailboxesSuggestsAvailableAccounts;

    [Test]
    procedure ListMailboxesMarksBrokenMailboxes;

    [Test]
    procedure AddOwnMailboxStoresIt;

    [Test]
    procedure AddAcceptsUpnAsAccount;

    [Test]
    procedure AddSharedMailboxChecksItsInbox;

    [Test]
    procedure AddingInaccessibleSharedMailboxIsRefused;

    [Test]
    procedure AddSharedMailboxWithoutAddressGivesClearError;

    [Test]
    procedure AddWithInvalidOrTakenSlugGivesClearError;

    [Test]
    procedure AddWithUnknownAccountGivesClearError;

    [Test]
    procedure RenameChangesSlugAndDisplayName;

    [Test]
    procedure RenameToTakenSlugGivesClearError;

    [Test]
    procedure AddWithUnknownKindGivesClearError;

    [Test]
    procedure RenameReportsSuccessWhenAccountsCannotBeListed;

    [Test]
    procedure RemoveNeedsConfirmation;

    [Test]
    procedure RemoveWorksForUnlinkedAccount;

    [Test]
    procedure ToolsCarryTheirAnnotations;
  end;

implementation

uses
  System.SysUtils,
  MCPAuth.Clock,
  MCPAuth.Secret.Token,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Tools.Services,
  MicrosoftMcp.Tools.Mailbox.ListAccounts,
  MicrosoftMcp.Tools.Mailbox.List,
  MicrosoftMcp.Tools.Mailbox.Add,
  MicrosoftMcp.Tools.Mailbox.Rename,
  MicrosoftMcp.Tools.Mailbox.Remove,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  WorkKey = 'acc-work';
  PrivateKey = 'acc-private';
  GoneKey = 'acc-gone';
  WorkUpn = 'kees@gdk.example.test';
  PrivateUpn = 'kees@outlook.example.test';
  AccountPage = 'https://auth.example.test/account';
  InboxJson = '{"id":"inbox"}';
  AccessDeniedJson = '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}';

{ TMailboxToolsTests }

procedure TMailboxToolsTests.Setup;
begin
  FMailboxes := TMailboxStoreMemory.Create;

  FAccounts := TFakeUpstreamAccounts.Create;
  FAccountsInterface := FAccounts;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;

  const Confirmations = TConfirmationsMemory.Create(TTokenGenerator.Create, TSystemClock.Create);
  FServices := TToolServices.Create(FMailboxes, FAccounts, TGraphClientFactory.Create(FTransport), Confirmations, AccountPage);

  AddAccount(WorkKey, WorkUpn, 'Kees (GDK)', False);
  AddAccount(PrivateKey, PrivateUpn, 'Kees private', False);
end;

procedure TMailboxToolsTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TMailboxToolsTests.AddAccount(const Key, UserName, DisplayName: string; const NeedsReconnect: Boolean);
begin
  var Account := Default(TRemoteAccount);
  Account.Key            := Key;
  Account.Provider       := 'microsoft';
  Account.UserName       := UserName;
  Account.DisplayName    := DisplayName;
  Account.NeedsReconnect := NeedsReconnect;

  FAccounts.AddAccount(Kees, Account, Format('token-%s', [Key]));
end;

procedure TMailboxToolsTests.AddMailbox(const Slug, AccountKey: string; const Kind: TMailboxKind; const Address: string);
begin
  var Mailbox := Default(TMailbox);
  Mailbox.UserId      := Kees;
  Mailbox.Slug        := Slug;
  Mailbox.DisplayName := Format('Mailbox %s', [Slug]);
  Mailbox.Address     := Address;
  Mailbox.AccountKey  := AccountKey;
  Mailbox.Kind        := Kind;

  FMailboxes.Save(Mailbox);
end;

function TMailboxToolsTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  Result := TToolCall.Run(Tool, Kees, ArgumentsJson);
end;

function TMailboxToolsTests.FindMailbox(const Mailboxes: TJSONArray; const Slug: string): TJSONObject;
begin
  for var Item in Mailboxes do
  begin
    const Mailbox = Item as TJSONObject;
    if Mailbox.GetValue<string>('slug') = Slug then
      Exit(Mailbox);
  end;

  raise EAssertionFailed.CreateFmt('Mailbox "%s" is not in the list', [Slug]);
end;

function TMailboxToolsTests.StoredSlugs: string;
begin
  var Slugs: TArray<string> := [];
  for var Mailbox in FMailboxes.ListForUser(Kees) do
  begin
    Slugs := Slugs + [Mailbox.Slug];
  end;

  Result := string.Join(',', Slugs);
end;

procedure TMailboxToolsTests.ListAccountsReturnsLinkedAccountsAndAccountPage;
begin
  const Tool: IMCPTool = TListAccountsTool.Create(FServices);

  const CallResult = Call(Tool, '{}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Answer = TToolCall.Structured(CallResult);
    Assert.AreEqual(2, Answer.GetValue<TJSONArray>('accounts').Count);
    Assert.AreEqual(WorkKey, Answer.GetValue<string>('accounts[0].key'));
    Assert.AreEqual('Kees (GDK)', Answer.GetValue<string>('accounts[0].display_name'));
    Assert.AreEqual(WorkUpn, Answer.GetValue<string>('accounts[0].user_name'));
    Assert.IsFalse(Answer.GetValue<Boolean>('accounts[0].needs_reconnect'));
    Assert.AreEqual(AccountPage, Answer.GetValue<string>('account_page_url'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.ListMailboxesSuggestsAvailableAccounts;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  AddMailbox('kees', WorkKey, TMailboxKind.Shared, 'kees-team@gdk.example.test');
  const Tool: IMCPTool = TListMailboxesTool.Create(FServices);

  const CallResult = Call(Tool, '{}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Mailboxes = TToolCall.Structured(CallResult).GetValue<TJSONArray>('mailboxes');
    Assert.AreEqual(3, Mailboxes.Count);

    const Own = FindMailbox(Mailboxes, 'gdk');
    Assert.AreEqual('ok', Own.GetValue<string>('status'));
    Assert.AreEqual(WorkUpn, Own.GetValue<string>('address'));
    Assert.AreEqual('own', Own.GetValue<string>('kind'));
    Assert.AreEqual(WorkUpn, Own.GetValue<string>('account'));

    // "kees" is taken by the shared mailbox, so the private account gets the next free short name.
    const Available = FindMailbox(Mailboxes, 'kees-2');
    Assert.AreEqual('available', Available.GetValue<string>('status'));
    Assert.AreEqual(PrivateUpn, Available.GetValue<string>('account'));
    Assert.AreEqual('Kees private', Available.GetValue<string>('display_name'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.ListMailboxesMarksBrokenMailboxes;
begin
  AddAccount('acc-stale', 'stale@example.test', 'Stale', True);
  AddMailbox('stale', 'acc-stale', TMailboxKind.Own, '');
  AddMailbox('gone', GoneKey, TMailboxKind.Shared, 'gone@example.test');
  const Tool: IMCPTool = TListMailboxesTool.Create(FServices);

  const CallResult = Call(Tool, '{}');
  try
    const Mailboxes = TToolCall.Structured(CallResult).GetValue<TJSONArray>('mailboxes');

    Assert.AreEqual('reconnect_required', FindMailbox(Mailboxes, 'stale').GetValue<string>('status'));
    Assert.AreEqual('account_unlinked', FindMailbox(Mailboxes, 'gone').GetValue<string>('status'));
    Assert.AreEqual(GoneKey, FindMailbox(Mailboxes, 'gone').GetValue<string>('account'));
    Assert.AreEqual(AccountPage, TToolCall.Structured(CallResult).GetValue<string>('account_page_url'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddOwnMailboxStoresIt;
begin
  FTransport.Respond(200, InboxJson);
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, Format('{"account":"%s","kind":"own"}', [WorkKey]));
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Mailbox = TToolCall.Structured(CallResult).GetValue<TJSONObject>('mailbox');
    Assert.AreEqual('kees', Mailbox.GetValue<string>('slug'));
    Assert.AreEqual('Kees (GDK)', Mailbox.GetValue<string>('display_name'));
    Assert.AreEqual('kees', StoredSlugs);
    Assert.Contains(FTransport.LastRequest.Url, '/me/mailFolders/inbox');
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddAcceptsUpnAsAccount;
begin
  FTransport.Respond(200, InboxJson);
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, '{"account":"KEES@Outlook.example.test","kind":"own","slug":"prive","display_name":"Priv'#$00E9'"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    var Stored: TMailbox;
    Assert.IsTrue(FMailboxes.TryGet(Kees, 'prive', Stored));
    Assert.AreEqual(PrivateKey, Stored.AccountKey);
    Assert.AreEqual('Priv'#$00E9, Stored.DisplayName);
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddSharedMailboxChecksItsInbox;
begin
  FTransport.Respond(200, InboxJson);
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, Format('{"account":"%s","kind":"shared","address":"sales@gdk.example.test"}', [WorkKey]));
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('sales', StoredSlugs);
    Assert.Contains(FTransport.LastRequest.Url, '/users/sales');
    Assert.Contains(FTransport.LastRequest.Url, '/mailFolders/inbox');
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddingInaccessibleSharedMailboxIsRefused;
begin
  FTransport.Respond(403, AccessDeniedJson);
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, Format('{"account":"%s","kind":"shared","address":"board@gdk.example.test","slug":"board"}', [WorkKey]));
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'FullAccess');
    Assert.Contains(TToolCall.Text(CallResult), AccountPage);
    Assert.AreEqual('', StoredSlugs, 'A mailbox the server cannot read must not be stored');
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddSharedMailboxWithoutAddressGivesClearError;
begin
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, Format('{"account":"%s","kind":"shared"}', [WorkKey]));
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'address');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddWithInvalidOrTakenSlugGivesClearError;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const InvalidResult = Call(Tool, Format('{"account":"%s","kind":"own","slug":"Priv'#$00E9' Mail"}', [PrivateKey]));
  const TakenResult = Call(Tool, Format('{"account":"%s","kind":"own","slug":"gdk"}', [PrivateKey]));
  try
    Assert.IsTrue(TToolCall.IsError(InvalidResult));
    Assert.Contains(TToolCall.Text(InvalidResult), 'not valid');
    Assert.Contains(TToolCall.Text(InvalidResult), '"prive-mail"');

    Assert.IsTrue(TToolCall.IsError(TakenResult));
    Assert.Contains(TToolCall.Text(TakenResult), 'already used');
    Assert.Contains(TToolCall.Text(TakenResult), '"gdk-2"');

    Assert.AreEqual('gdk', StoredSlugs);
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    TakenResult.Free;
    InvalidResult.Free;
  end;
end;

procedure TMailboxToolsTests.AddWithUnknownAccountGivesClearError;
begin
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, '{"account":"someone@else.example.test","kind":"own"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'someone@else.example.test');
    Assert.Contains(TToolCall.Text(CallResult), WorkUpn);
    Assert.Contains(TToolCall.Text(CallResult), AccountPage);
    Assert.AreEqual('', StoredSlugs);
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.RenameChangesSlugAndDisplayName;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  const Tool: IMCPTool = TMailboxRenameTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","new_slug":"werk","display_name":"Werk"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    var Stored: TMailbox;
    Assert.IsTrue(FMailboxes.TryGet(Kees, 'werk', Stored));
    Assert.AreEqual('Werk', Stored.DisplayName);
    Assert.AreEqual('werk', TToolCall.Structured(CallResult).GetValue<string>('mailbox.slug'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.RenameToTakenSlugGivesClearError;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  AddMailbox('prive', PrivateKey, TMailboxKind.Own, '');
  const Tool: IMCPTool = TMailboxRenameTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","new_slug":"prive"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'already used');
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.RemoveNeedsConfirmation;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  const Tool: IMCPTool = TMailboxRemoveTool.Create(FServices);

  const FirstResult = Call(Tool, '{"mailbox":"gdk"}');
  try
    const Answer = TToolCall.Structured(FirstResult);
    Assert.IsTrue(Answer.GetValue<Boolean>('confirmation_required'));
    Assert.Contains(Answer.GetValue<string>('summary'), '"gdk"');
    Assert.AreEqual('gdk', StoredSlugs, 'Without confirmation the mailbox must stay');

    const Token = Answer.GetValue<string>('confirmation_token');
    const SecondResult = Call(Tool, Format('{"mailbox":"gdk","confirmation_token":"%s"}', [Token]));
    try
      Assert.IsFalse(TToolCall.IsError(SecondResult), SecondResult.ToJSON);
      Assert.AreEqual('gdk', TToolCall.Structured(SecondResult).GetValue<string>('removed'));
      Assert.AreEqual('', StoredSlugs);
    finally
      SecondResult.Free;
    end;
  finally
    FirstResult.Free;
  end;
end;

procedure TMailboxToolsTests.RemoveWorksForUnlinkedAccount;
begin
  AddMailbox('gone', GoneKey, TMailboxKind.Shared, 'gone@example.test');
  const Tool: IMCPTool = TMailboxRemoveTool.Create(FServices);

  const FirstResult = Call(Tool, '{"mailbox":"gone"}');
  try
    const Token = TToolCall.Structured(FirstResult).GetValue<string>('confirmation_token');
    const SecondResult = Call(Tool, Format('{"mailbox":"gone","confirmation_token":"%s"}', [Token]));
    try
      Assert.IsFalse(TToolCall.IsError(SecondResult), SecondResult.ToJSON);
      Assert.AreEqual('', StoredSlugs);
    finally
      SecondResult.Free;
    end;
  finally
    FirstResult.Free;
  end;
end;

procedure TMailboxToolsTests.ToolsCarryTheirAnnotations;
begin
  const ListTool: IMCPToolMetadata = TListMailboxesTool.Create(FServices);
  const RemoveTool: IMCPToolMetadata = TMailboxRemoveTool.Create(FServices);
  const AddTool: IMCPToolMetadata = TMailboxAddTool.Create(FServices);

  Assert.IsTrue(ListTool.Annotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsTrue(RemoveTool.Annotations.GetValue<Boolean>('destructiveHint'));
  Assert.IsTrue(RemoveTool.Annotations.GetValue<Boolean>('openWorldHint'));
  Assert.IsFalse(AddTool.Annotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsFalse(AddTool.Annotations.GetValue<Boolean>('destructiveHint'));
end;

procedure TMailboxToolsTests.AddWithUnknownKindGivesClearError;
begin
  const Tool: IMCPTool = TMailboxAddTool.Create(FServices);

  const CallResult = Call(Tool, Format('{"account":"%s","kind":"team","slug":"team"}', [WorkKey]));
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'shared');
    Assert.DoesNotContain(TToolCall.Text(CallResult), 'Graph');
  finally
    CallResult.Free;
  end;
end;

procedure TMailboxToolsTests.RenameReportsSuccessWhenAccountsCannotBeListed;
begin
  AddMailbox('gdk', WorkKey, TMailboxKind.Own, '');
  FAccounts.FailListWith(
    function: Exception
    begin
      Result := EInvalidOpException.Create('auth server down');
    end);
  const Tool: IMCPTool = TMailboxRenameTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","new_slug":"werk"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('werk', TToolCall.Structured(CallResult).GetValue<string>('mailbox.slug'));
    Assert.AreEqual('unknown', TToolCall.Structured(CallResult).GetValue<string>('mailbox.status'));
  finally
    CallResult.Free;
  end;
end;

end.
