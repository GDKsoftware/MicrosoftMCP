unit MicrosoftMcp.Tools.Base.Tests;

interface

uses
  DUnitX.TestFramework,
  MCPServer.Types,
  MCPServer.Tool.Base,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.GraphId,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport,
  MicrosoftMcp.Fakes.UpstreamAccounts;

type
  TMailboxOwnerResponse = class
  private
    FUserId: string;
    FAddress: string;

  public
    [SchemaName('user_id')]
    property UserId: string read FUserId write FUserId;

    property Address: string read FAddress write FAddress;
  end;

  // Reads the inbox and reports whose mailbox it got.
  TMailboxOwnerTool = class(TMicrosoftTool<TMicrosoftToolParams, TMailboxOwnerResponse>)
  protected
    function Run(const Params: TMicrosoftToolParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailboxOwnerResponse; override;

  public
    constructor Create(const Services: IToolServices);
  end;

  TDeleteMessageParams = class(TConfirmableToolParams)
  private
    FMessageId: string;

  public
    [GraphId]
    [SchemaName('message_id')]
    property MessageId: string read FMessageId write FMessageId;
  end;

  TDeleteMessageResponse = class
  private
    FDeleted: string;

  public
    property Deleted: string read FDeleted write FDeleted;
  end;

  TDeleteMessageTool = class(TConfirmedMicrosoftTool<TDeleteMessageParams, TDeleteMessageResponse>)
  protected
    function Summarize(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TDeleteMessageResponse; override;

  public
    constructor Create(const Services: IToolServices);
  end;

  // Reads the message before it summarizes, as the mail tools do.
  TDeleteLoadedMessageTool = class(TDeleteMessageTool)
  protected
    function Summarize(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox): string; override;
  end;

  [TestFixture]
  TToolBaseTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    procedure AddMailbox(const UserId, Slug, Address, AccountKey: string);
    procedure AddAccount(const UserId, AccountKey, AccessToken: string);
    function ConfirmationTokenOf(const Tool: IMCPTool; const ArgumentsJson: string): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure ToolUsesPrincipalNotParameterForUser;

    [Test]
    procedure UserParameterIsRejected;

    [Test]
    procedure RequestWithoutPrincipalIsToolError;

    [Test]
    procedure UnknownMailboxIsToolError;

    [Test]
    procedure GraphErrorBecomesToolError;

    [Test]
    procedure ConfirmedToolWithoutTokenReturnsSummaryAndDoesNothing;

    [Test]
    procedure ConfirmedToolWithTokenRuns;

    [Test]
    procedure ReusedTokenDoesNotRunAgain;

    [Test]
    procedure TokenWithOtherArgumentsDoesNotRun;

    [Test]
    procedure ConfirmedToolPublishesNoOutputSchema;

    [Test]
    procedure ConfirmationTokenParameterIsSnakeCase;

    [Test]
    procedure IdWithPathIsRefusedBeforeGraph;

    [Test]
    procedure EveryIdParameterIsGuarded;

    [Test]
    procedure SummaryOnSharedMailbox403ExplainsFullAccess;

    [Test]
    procedure TokenDoesNotFollowSlugToOtherMailbox;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Rtti,
  MCPAuth.Clock,
  MCPAuth.Secret.Token,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Tools.Services,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  Anna = 'user-anna';
  KeesAccountKey = 'acc-kees';
  AnnaAccountKey = 'acc-anna';
  KeesShared = 'team@example.test';
  AccountPage = 'https://auth.example.test/account';
  WorkMailbox = '{"mailbox":"work"}';
  DeleteArguments = '{"mailbox":"work","message_id":"AAMk1"}';
  DeleteWithTokenFormat = '{"mailbox":"work","message_id":"%s","confirmation_token":"%s"}';
  InboxJson = '{"id":"inbox"}';
  MethodDelete = 'DELETE';

{ TMailboxOwnerTool }

constructor TMailboxOwnerTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := 'test_mailbox_owner';
  MarkReadOnly(False);
end;

function TMailboxOwnerTool.Run(const Params: TMicrosoftToolParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailboxOwnerResponse;
begin
  const Inbox = Graph.Get(Format('%s/mailFolders/inbox', [Graph.GetUserPrefix]));
  Inbox.Free;

  Result := TMailboxOwnerResponse.Create;
  Result.UserId := Mailbox.Mailbox.UserId;
  Result.Address := Mailbox.Mailbox.Address;
end;

{ TDeleteMessageTool }

constructor TDeleteMessageTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := 'test_delete_message';
  MarkChanging(True, False);
end;

function TDeleteMessageTool.Summarize(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox): string;
begin
  Result := Format('Delete message %s from mailbox %s', [Params.MessageId, Mailbox.Mailbox.Slug]);
end;

function TDeleteMessageTool.Run(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TDeleteMessageResponse;
begin
  const Deleted = Graph.Delete(Format('%s/messages/%s', [Graph.GetUserPrefix, Params.MessageId]));
  Deleted.Free;

  Result := TDeleteMessageResponse.Create;
  Result.Deleted := Params.MessageId;
end;

{ TDeleteLoadedMessageTool }

function TDeleteLoadedMessageTool.Summarize(const Params: TDeleteMessageParams; const Mailbox: TResolvedMailbox): string;
begin
  const Graph = FServices.GraphClients.Create(Mailbox);
  try
    Graph.Get(Format('%s/messages/%s', [Graph.GetUserPrefix, Params.MessageId])).Free;
  finally
    Graph.Free;
  end;

  Result := inherited Summarize(Params, Mailbox);
end;

{ TToolBaseTests }

procedure TToolBaseTests.Setup;
begin
  FMailboxes := TMailboxStoreMemory.Create;

  FAccounts := TFakeUpstreamAccounts.Create;
  FAccountsInterface := FAccounts;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;

  const Confirmations = TConfirmationsMemory.Create(TTokenGenerator.Create, TSystemClock.Create);
  FServices := TToolServices.Create(FMailboxes, FAccounts, TGraphClientFactory.Create(FTransport), Confirmations, AccountPage);

  AddAccount(Kees, KeesAccountKey, 'token-kees');
  AddAccount(Anna, AnnaAccountKey, 'token-anna');
  AddMailbox(Kees, 'work', KeesShared, KeesAccountKey);
  AddMailbox(Anna, 'work', '', AnnaAccountKey);
end;

procedure TToolBaseTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TToolBaseTests.AddMailbox(const UserId, Slug, Address, AccountKey: string);
begin
  var Mailbox := Default(TMailbox);
  Mailbox.UserId      := UserId;
  Mailbox.Slug        := Slug;
  Mailbox.DisplayName := Slug;
  Mailbox.Address     := Address;
  Mailbox.AccountKey  := AccountKey;

  if Address.IsEmpty then
    Mailbox.Kind := TMailboxKind.Own
  else
    Mailbox.Kind := TMailboxKind.Shared;

  FMailboxes.Save(Mailbox);
end;

procedure TToolBaseTests.AddAccount(const UserId, AccountKey, AccessToken: string);
begin
  var Account := Default(TRemoteAccount);
  Account.Key := AccountKey;
  Account.UserName := Format('%s@example.test', [UserId]);
  Account.DisplayName := UserId;

  FAccounts.AddAccount(UserId, Account, AccessToken);
end;

function TToolBaseTests.ConfirmationTokenOf(const Tool: IMCPTool; const ArgumentsJson: string): string;
begin
  const CallResult = TToolCall.Run(Tool, Kees, ArgumentsJson);
  try
    Result := TToolCall.Structured(CallResult).GetValue<string>('confirmation_token');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.ToolUsesPrincipalNotParameterForUser;
begin
  FTransport.Respond(200, InboxJson);
  const Tool: IMCPTool = TMailboxOwnerTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Anna, WorkMailbox);
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Owner = TToolCall.Structured(CallResult);
    Assert.AreEqual(Anna, Owner.GetValue<string>('user_id'));
    Assert.AreEqual('', Owner.GetValue<string>('address'), 'Anna''s "work" is her own mailbox, not the shared one of Kees');
    Assert.Contains(FTransport.LastRequest.Url, '/me/mailFolders/inbox');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.UserParameterIsRejected;
begin
  const Tool: IMCPTool = TMailboxOwnerTool.Create(FServices);

  Assert.WillRaise(
    procedure
    begin
      TToolCall.Run(Tool, Anna, '{"mailbox":"work","user_id":"user-kees"}').Free;
    end,
    EArgumentException);

  Assert.AreEqual(0, FTransport.RequestCount);
end;

procedure TToolBaseTests.RequestWithoutPrincipalIsToolError;
begin
  const Tool: IMCPTool = TMailboxOwnerTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, '', WorkMailbox);
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'signed-in user');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.UnknownMailboxIsToolError;
begin
  const Tool: IMCPTool = TMailboxOwnerTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Kees, '{"mailbox":"prive"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), '"work"');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.GraphErrorBecomesToolError;
begin
  FTransport.Respond(403, '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}');
  const Tool: IMCPTool = TMailboxOwnerTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Kees, WorkMailbox);
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'FullAccess');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.ConfirmedToolWithoutTokenReturnsSummaryAndDoesNothing;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Kees, DeleteArguments);
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Answer = TToolCall.Structured(CallResult);
    Assert.IsTrue(Answer.GetValue<Boolean>('confirmation_required'));
    Assert.Contains(Answer.GetValue<string>('summary'), 'AAMk1');
    Assert.IsFalse(Answer.GetValue<string>('confirmation_token').IsEmpty);
    Assert.AreEqual(0, FTransport.RequestCount, 'Without a token nothing may reach Graph');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.ConfirmedToolWithTokenRuns;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);
  const Token = ConfirmationTokenOf(Tool, DeleteArguments);

  const CallResult = TToolCall.Run(Tool, Kees, Format(DeleteWithTokenFormat, ['AAMk1', Token]));
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('AAMk1', TToolCall.Structured(CallResult).GetValue<string>('deleted'));
    Assert.AreEqual(1, FTransport.RequestCount);
    Assert.AreEqual(MethodDelete, FTransport.LastRequest.Method);
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.ReusedTokenDoesNotRunAgain;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);
  const Token = ConfirmationTokenOf(Tool, DeleteArguments);
  const ArgumentsWithToken = Format(DeleteWithTokenFormat, ['AAMk1', Token]);
  TToolCall.Run(Tool, Kees, ArgumentsWithToken).Free;

  const CallResult = TToolCall.Run(Tool, Kees, ArgumentsWithToken);
  try
    Assert.IsTrue(TToolCall.Structured(CallResult).GetValue<Boolean>('confirmation_required'));
    Assert.AreEqual(1, FTransport.RequestCount, 'The second call with the used token must not delete again');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.TokenWithOtherArgumentsDoesNotRun;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);
  const Token = ConfirmationTokenOf(Tool, DeleteArguments);

  const CallResult = TToolCall.Run(Tool, Kees, Format(DeleteWithTokenFormat, ['AAMk2', Token]));
  try
    Assert.IsTrue(TToolCall.Structured(CallResult).GetValue<Boolean>('confirmation_required'));
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.ConfirmedToolPublishesNoOutputSchema;
begin
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);

  const OutputSchema = Tool.OutputSchema;

  Assert.IsNull(OutputSchema);
end;

procedure TToolBaseTests.ConfirmationTokenParameterIsSnakeCase;
begin
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);

  const InputSchema = Tool.InputSchema;
  try
    const Properties = InputSchema.GetValue<TJSONObject>('properties');
    Assert.IsNotNull(Properties.GetValue('confirmation_token'));
    Assert.IsNotNull(Properties.GetValue('mailbox'));
  finally
    InputSchema.Free;
  end;
end;

procedure TToolBaseTests.IdWithPathIsRefusedBeforeGraph;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Kees, '{"mailbox":"work","message_id":"x/../../messages/d1/send?"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Text(CallResult), 'message_id');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

// Every parameter named *_id of a tool reaches a Graph URL path, so each must carry [GraphId].
procedure TToolBaseTests.EveryIdParameterIsGuarded;
begin
  var Unguarded := '';
  var CheckedCount := 0;

  const Context = TRttiContext.Create;
  for var RttiType in Context.GetTypes do
  begin
    const IsParams = ((RttiType is TRttiInstanceType) and TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TMicrosoftToolParams));
    if not IsParams then
      Continue;

    for var Prop in RttiType.GetProperties do
    begin
      const SchemaName = Prop.GetAttribute<SchemaNameAttribute>;
      const IsIdParameter = (Assigned(SchemaName) and SchemaName.Name.EndsWith('_id'));
      if not IsIdParameter then
        Continue;

      Inc(CheckedCount);
      if Prop.GetAttribute<GraphIdAttribute> = nil then
        Unguarded := Unguarded + Format(' %s.%s', [RttiType.Name, Prop.Name]);
    end;
  end;

  Assert.IsTrue(CheckedCount > 10, 'The tool parameter classes must be linked into the test program');
  Assert.AreEqual('', Unguarded, 'Id parameters without [GraphId]');
end;

procedure TToolBaseTests.SummaryOnSharedMailbox403ExplainsFullAccess;
begin
  FTransport.Respond(403, '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}');
  const Tool: IMCPTool = TDeleteLoadedMessageTool.Create(FServices);

  const CallResult = TToolCall.Run(Tool, Kees, DeleteArguments);
  try
    Assert.IsTrue(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Text(CallResult), 'FullAccess');
    Assert.Contains(TToolCall.Text(CallResult), 'work');
  finally
    CallResult.Free;
  end;
end;

procedure TToolBaseTests.TokenDoesNotFollowSlugToOtherMailbox;
begin
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TDeleteMessageTool.Create(FServices);
  const Token = ConfirmationTokenOf(Tool, DeleteArguments);

  FMailboxes.Delete(Kees, 'work');
  AddMailbox(Kees, 'work', 'board@example.test', KeesAccountKey);

  const CallResult = TToolCall.Run(Tool, Kees, Format(DeleteWithTokenFormat, ['AAMk1', Token]));
  try
    Assert.IsTrue(TToolCall.Structured(CallResult).GetValue<Boolean>('confirmation_required'));
    Assert.AreEqual(0, FTransport.RequestCount, 'A token for one mailbox must not act on another that took over its short name');
  finally
    CallResult.Free;
  end;
end;

end.
