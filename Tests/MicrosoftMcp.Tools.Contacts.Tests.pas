unit MicrosoftMcp.Tools.Contacts.Tests;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  MCPServer.Tool.Base,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport,
  MicrosoftMcp.Fakes.UpstreamAccounts;

type
  [TestFixture]
  TContactsToolsTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    function Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function CountRequests(const Method: string): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure ContactsSearchReturnsContacts;

    [Test]
    procedure ContactsGetReturnsDetails;

    [Test]
    procedure ContactsCreateSendsFields;

    [Test]
    procedure ContactsCreateWithoutNameOrEmailIsRefused;

    [Test]
    procedure ContactsUpdateSendsOnlyGivenFields;

    [Test]
    procedure ContactsUpdateWithoutChangesIsRefused;

    [Test]
    procedure ContactsDeleteNeedsConfirmation;

    [Test]
    procedure PeopleSearchPassesQuery;

    [Test]
    procedure PeopleSearchWithoutQueryIsRefused;

    [Test]
    procedure PeopleRelevantReturnsPeopleOfTheAccount;

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
  MicrosoftMcp.Tools.Contacts.Search,
  MicrosoftMcp.Tools.Contacts.Get,
  MicrosoftMcp.Tools.Contacts.Create,
  MicrosoftMcp.Tools.Contacts.Update,
  MicrosoftMcp.Tools.Contacts.Delete,
  MicrosoftMcp.Tools.People.Search,
  MicrosoftMcp.Tools.People.Relevant,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  WorkKey = 'acc-work';
  WorkUpn = 'kees@gdk.example.test';
  OwnSlug = 'gdk';
  ContactJson = '{"id":"c1","givenName":"Anna","surname":"Jansen","displayName":"Anna Jansen","emailAddresses":[{"address":"anna@other.example.test"}],' +
                '"businessPhones":["+31 20 1234567"],"mobilePhone":"+31 6 12345678","companyName":"Other BV","jobTitle":"Buyer"}';

{ TContactsToolsTests }

procedure TContactsToolsTests.Setup;
begin
  FMailboxes := TMailboxStoreMemory.Create;

  FAccounts := TFakeUpstreamAccounts.Create;
  FAccountsInterface := FAccounts;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;

  const Confirmations = TConfirmationsMemory.Create(TTokenGenerator.Create, TSystemClock.Create);
  FServices := TToolServices.Create(FMailboxes, FAccounts, TGraphClientFactory.Create(FTransport), Confirmations, 'https://auth.example.test/account');

  var Account := Default(TRemoteAccount);
  Account.Key         := WorkKey;
  Account.Provider    := 'microsoft';
  Account.UserName    := WorkUpn;
  Account.DisplayName := 'Kees (GDK)';
  FAccounts.AddAccount(Kees, Account, 'token-work');

  var Mailbox := Default(TMailbox);
  Mailbox.UserId      := Kees;
  Mailbox.Slug        := OwnSlug;
  Mailbox.DisplayName := OwnSlug;
  Mailbox.AccountKey  := WorkKey;
  Mailbox.Kind        := TMailboxKind.Own;
  FMailboxes.Save(Mailbox);
end;

procedure TContactsToolsTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

function TContactsToolsTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  Result := TToolCall.Run(Tool, Kees, ArgumentsJson);
end;

function TContactsToolsTests.CountRequests(const Method: string): Integer;
begin
  Result := 0;
  for var Index := 0 to FTransport.RequestCount - 1 do
  begin
    if FTransport.RequestAt(Index).Method = Method then
      Inc(Result);
  end;
end;

procedure TContactsToolsTests.ContactsSearchReturnsContacts;
begin
  FTransport.Respond(200, '{"value":[' + ContactJson + ']}');
  const Tool: IMCPTool = TContactsSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"anna","top":5}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/contacts');
    Assert.Contains(FTransport.LastRequest.Url, 'anna');
    Assert.Contains(FTransport.LastRequest.Url, 'top=5');
    Assert.AreEqual('anna@other.example.test', TToolCall.Structured(CallResult).GetValue<string>('contacts[0].email'));
    Assert.AreEqual('Anna Jansen', TToolCall.Structured(CallResult).GetValue<string>('contacts[0].display_name'));
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsGetReturnsDetails;
begin
  FTransport.Respond(200, ContactJson);
  const Tool: IMCPTool = TContactsGetTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","contact_id":"c1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/contacts/c1');
    Assert.AreEqual('Other BV', TToolCall.Structured(CallResult).GetValue<string>('company'));
    Assert.AreEqual('+31 6 12345678', TToolCall.Structured(CallResult).GetValue<string>('mobile_phone'));
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsCreateSendsFields;
begin
  FTransport.Respond(201, '{"id":"c2","displayName":"Piet Pietersen"}');
  const Tool: IMCPTool = TContactsCreateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","given_name":"Piet","surname":"Pietersen","email":"piet@other.example.test","company":"Other BV"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('POST', FTransport.LastRequest.Method);

    const Body = TJSONObject.ParseJSONValue(FTransport.LastRequest.Body) as TJSONObject;
    try
      Assert.AreEqual('Piet', Body.GetValue<string>('givenName'));
      Assert.AreEqual('piet@other.example.test', Body.GetValue<string>('emailAddresses[0].address'));
      Assert.AreEqual('Other BV', Body.GetValue<string>('companyName'));
    finally
      Body.Free;
    end;

    Assert.AreEqual('c2', TToolCall.Structured(CallResult).GetValue<string>('contact_id'));
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsCreateWithoutNameOrEmailIsRefused;
begin
  const Tool: IMCPTool = TContactsCreateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","company":"Other BV"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsUpdateSendsOnlyGivenFields;
begin
  FTransport.Respond(200, '{"id":"c1","displayName":"Anna Jansen"}');
  const Tool: IMCPTool = TContactsUpdateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","contact_id":"c1","job_title":"Head of purchasing"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('PATCH', FTransport.LastRequest.Method);

    const Body = TJSONObject.ParseJSONValue(FTransport.LastRequest.Body) as TJSONObject;
    try
      Assert.AreEqual('Head of purchasing', Body.GetValue<string>('jobTitle'));
      Assert.IsNull(Body.GetValue('givenName'));
      Assert.IsNull(Body.GetValue('companyName'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsUpdateWithoutChangesIsRefused;
begin
  const Tool: IMCPTool = TContactsUpdateTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","contact_id":"c1"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ContactsDeleteNeedsConfirmation;
begin
  FTransport.Respond(200, ContactJson);
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TContactsDeleteTool.Create(FServices);

  const FirstAnswer = Call(Tool, '{"mailbox":"gdk","contact_id":"c1"}');
  try
    Assert.IsTrue(TToolCall.Structured(FirstAnswer).GetValue<Boolean>('confirmation_required'), FirstAnswer.ToJSON);
    Assert.Contains(TToolCall.Structured(FirstAnswer).GetValue<string>('summary'), 'Anna Jansen');
    Assert.AreEqual(0, CountRequests('DELETE'), 'Nothing may be deleted before the confirmation');

    const Token = TToolCall.Structured(FirstAnswer).GetValue<string>('confirmation_token');
    const SecondAnswer = Call(Tool, Format('{"mailbox":"gdk","contact_id":"c1","confirmation_token":"%s"}', [Token]));
    try
      Assert.IsFalse(TToolCall.IsError(SecondAnswer), SecondAnswer.ToJSON);
      Assert.AreEqual(1, CountRequests('DELETE'));
      Assert.Contains(FTransport.LastRequest.Url, '/me/contacts/c1');
    finally
      SecondAnswer.Free;
    end;
  finally
    FirstAnswer.Free;
  end;
end;

procedure TContactsToolsTests.PeopleSearchPassesQuery;
begin
  FTransport.Respond(200, '{"value":[{"id":"p1","displayName":"Anna Jansen","scoredEmailAddresses":[{"address":"anna@other.example.test","relevanceScore":9.5}]}]}');
  const Tool: IMCPTool = TPeopleSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"anna","top":3}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/people');
    Assert.Contains(FTransport.LastRequest.Url, 'anna');
    Assert.Contains(FTransport.LastRequest.Url, 'top=3');
    Assert.AreEqual('anna@other.example.test', TToolCall.Structured(CallResult).GetValue<string>('people[0].email'));
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.PeopleSearchWithoutQueryIsRefused;
begin
  const Tool: IMCPTool = TPeopleSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"  "}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.PeopleRelevantReturnsPeopleOfTheAccount;
begin
  FTransport.Respond(200, '{"value":[{"id":"p1","displayName":"Anna Jansen","scoredEmailAddresses":[{"address":"anna@other.example.test"}]}]}');

  var Shared := Default(TMailbox);
  Shared.UserId      := Kees;
  Shared.Slug        := 'sales';
  Shared.DisplayName := 'sales';
  Shared.Address     := 'sales@gdk.example.test';
  Shared.AccountKey  := WorkKey;
  Shared.Kind        := TMailboxKind.Shared;
  FMailboxes.Save(Shared);

  const Tool: IMCPTool = TPeopleRelevantTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"sales","top":7}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/people');
    Assert.DoesNotContain(FTransport.LastRequest.Url, '/users/');
    Assert.Contains(TToolCall.Structured(CallResult).GetValue<string>('note'), WorkUpn);
  finally
    CallResult.Free;
  end;
end;

procedure TContactsToolsTests.ToolsCarryTheirAnnotations;
begin
  const Search = TContactsSearchTool.Create(FServices);
  const SearchTool: IMCPTool = Search;
  Assert.IsTrue(Search.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('contacts_search', SearchTool.Name);

  const Delete = TContactsDeleteTool.Create(FServices);
  const DeleteTool: IMCPTool = Delete;
  Assert.IsFalse(Delete.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('destructiveHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('openWorldHint'));
  Assert.AreEqual('contacts_delete', DeleteTool.Name);

  const People = TPeopleSearchTool.Create(FServices);
  const PeopleTool: IMCPTool = People;
  Assert.IsTrue(People.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('people_search', PeopleTool.Name);
end;

end.
