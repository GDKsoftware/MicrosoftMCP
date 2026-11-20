unit MicrosoftMcp.Tools.Mail.Tests;

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
  TMailToolsTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    procedure AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
    function Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function Confirm(const Tool: IMCPTool; const ArgumentsJson: string): string;
    function RequestBody(const Index: Integer): TJSONObject;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure SearchPassesQueryAndTop;

    [Test]
    procedure TopIsCappedAt100;

    [Test]
    procedure SearchEscapesQuotesInQuery;
    [Test]
    procedure SearchEscapesTrailingBackslash;
    [Test]
    procedure SearchEscapesBackslashBeforeQuote;

    [Test]
    procedure ReadReturnsTextBodyByDefault;

    [Test]
    procedure ListHidesBodies;

    [Test]
    procedure ListFoldersReturnsCounts;

    [Test]
    procedure GetAttachmentReturnsEmbeddedResource;

    [Test]
    procedure AttachmentOver10MbIsRefused;

    [Test]
    procedure CreateDraftSendsRecipients;

    [Test]
    procedure UpdateDraftKeepsOmittedFields;

    [Test]
    procedure ReplyDraftHonoursReplyAll;

    [Test]
    procedure SendWithoutTokenDoesNotCallGraph;

    [Test]
    procedure SendWithTokenCreatesAndSendsDraft;

    [Test]
    procedure SendDraftSummaryNamesRecipients;

    [Test]
    procedure SendDraftSummaryNamesCcAndBcc;

    [Test]
    procedure SendDraftWithTokenSendsUnchangedDraft;

    [Test]
    procedure UpdatedDraftInvalidatesToken;

    [Test]
    procedure DeleteDraftRefusesNonDraft;

    [Test]
    procedure DeleteDraftDeletesDraft;

    [Test]
    procedure ForwardSummaryNamesMailboxAndRecipients;

    [Test]
    procedure DeleteMovesToDeletedItems;

    [Test]
    procedure MoveAcceptsWellKnownFolderName;

    [Test]
    procedure MoveToDeletedItemsPointsToMailDelete;

    [Test]
    procedure AttachmentMissingFromListIsNotDownloaded;

    [Test]
    procedure MarkReadSendsIsRead;

    [Test]
    procedure SharedMailboxRequestsUseUsersPath;

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
  MicrosoftMcp.Tools.Mail.Search,
  MicrosoftMcp.Tools.Mail.List,
  MicrosoftMcp.Tools.Mail.Read,
  MicrosoftMcp.Tools.Mail.ListFolders,
  MicrosoftMcp.Tools.Mail.ListAttachments,
  MicrosoftMcp.Tools.Mail.GetAttachment,
  MicrosoftMcp.Tools.Mail.CreateDraft,
  MicrosoftMcp.Tools.Mail.UpdateDraft,
  MicrosoftMcp.Tools.Mail.CreateReplyDraft,
  MicrosoftMcp.Tools.Mail.CreateForwardDraft,
  MicrosoftMcp.Tools.Mail.DeleteDraft,
  MicrosoftMcp.Tools.Mail.SendDraft,
  MicrosoftMcp.Tools.Mail.Send,
  MicrosoftMcp.Tools.Mail.Forward,
  MicrosoftMcp.Tools.Mail.Move,
  MicrosoftMcp.Tools.Mail.MarkRead,
  MicrosoftMcp.Tools.Mail.Delete,
  MicrosoftMcp.Tools.Mail.GetSignature,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  WorkKey = 'acc-work';
  WorkUpn = 'kees@gdk.example.test';
  OwnSlug = 'gdk';
  SharedSlug = 'sales';
  SharedAddress = 'sales@gdk.example.test';
  EmptyList = '{"value":[]}';
  SignatureNone = '{"signatureHtml":""}';
  MessageJson = '{"id":"m1","subject":"Quarterly numbers","from":{"emailAddress":{"name":"Anna","address":"anna@other.example.test"}},' +
                '"toRecipients":[{"emailAddress":{"name":"Kees","address":"kees@gdk.example.test"}}],' +
                '"receivedDateTime":"2026-11-01T09:00:00Z","isRead":false,"hasAttachments":true,"bodyPreview":"Hello Kees",' +
                '"body":{"contentType":"text","content":"SECRET BODY TEXT"}}';
  DraftFormat = '{"id":"d1","subject":"Offer","isDraft":true,"changeKey":"%s","lastModifiedDateTime":"2026-11-02T10:00:00Z",' +
                '"toRecipients":[{"emailAddress":{"name":"Anna","address":"anna@other.example.test"}}],' +
                '"ccRecipients":[{"emailAddress":{"address":"cc@other.example.test"}}],' +
                '"bccRecipients":[{"emailAddress":{"address":"hidden@outside.example.test"}}]}';
  SendDraftArguments = '{"mailbox":"gdk","draft_id":"d1"}';

{ TMailToolsTests }

procedure TMailToolsTests.Setup;
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

  AddMailbox(OwnSlug, TMailboxKind.Own, '');
  AddMailbox(SharedSlug, TMailboxKind.Shared, SharedAddress);
end;

procedure TMailToolsTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TMailToolsTests.AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
begin
  var Mailbox := Default(TMailbox);
  Mailbox.UserId      := Kees;
  Mailbox.Slug        := Slug;
  Mailbox.DisplayName := Slug;
  Mailbox.Address     := Address;
  Mailbox.AccountKey  := WorkKey;
  Mailbox.Kind        := Kind;

  FMailboxes.Save(Mailbox);
end;

function TMailToolsTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  Result := TToolCall.Run(Tool, Kees, ArgumentsJson);
end;

// Calls a confirmed tool twice, as Claude does, and returns the answer of the second call.
function TMailToolsTests.Confirm(const Tool: IMCPTool; const ArgumentsJson: string): string;
begin
  const FirstAnswer = Call(Tool, ArgumentsJson);
  try
    const Token = TToolCall.Structured(FirstAnswer).GetValue<string>('confirmation_token');
    const WithToken = ArgumentsJson.TrimRight(['}']) + Format(',"confirmation_token":"%s"}', [Token]);

    const SecondAnswer = Call(Tool, WithToken);
    try
      Assert.IsFalse(TToolCall.IsError(SecondAnswer), SecondAnswer.ToJSON);
      Result := SecondAnswer.ToJSON;
    finally
      SecondAnswer.Free;
    end;
  finally
    FirstAnswer.Free;
  end;
end;

function TMailToolsTests.RequestBody(const Index: Integer): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(FTransport.RequestAt(Index).Body) as TJSONObject;
end;

procedure TMailToolsTests.SearchPassesQueryAndTop;
begin
  FTransport.Respond(200, '{"value":[' + MessageJson + ']}');
  const Tool: IMCPTool = TMailSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"quarterly","top":10}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Request = FTransport.LastRequest;
    Assert.AreEqual('GET', Request.Method);
    Assert.Contains(Request.Url, '/me/messages');
    Assert.Contains(Request.Url, 'quarterly');
    Assert.Contains(Request.Url, 'top=10');
    Assert.AreEqual('Quarterly numbers', TToolCall.Structured(CallResult).GetValue<string>('messages[0].subject'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.TopIsCappedAt100;
begin
  FTransport.Respond(200, EmptyList);
  const Tool: IMCPTool = TMailListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","top":500}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, 'top=100');
    Assert.IsFalse(FTransport.LastRequest.Url.Contains('top=500'));
    Assert.Contains(FTransport.LastRequest.Url, '/me/mailFolders/inbox/messages');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ReadReturnsTextBodyByDefault;
begin
  FTransport.Respond(200, MessageJson);
  const Tool: IMCPTool = TMailReadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    var AskedForText := False;
    for var Header in FTransport.LastRequest.Headers do
    begin
      AskedForText := AskedForText or Header.Value.Contains('body-content-type="text"');
    end;
    Assert.IsTrue(AskedForText, 'The request must ask Graph for a text body');

    const Answer = TToolCall.Structured(CallResult);
    Assert.AreEqual('SECRET BODY TEXT', Answer.GetValue<string>('body'));
    Assert.AreEqual('text', Answer.GetValue<string>('body_format'));
    Assert.AreEqual('Anna <anna@other.example.test>', Answer.GetValue<string>('from'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ListHidesBodies;
begin
  FTransport.Respond(200, '{"value":[' + MessageJson + ']}');
  const Tool: IMCPTool = TMailListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk"}');
  try
    const Item = TToolCall.Structured(CallResult).GetValue<TJSONObject>('messages[0]');

    Assert.IsFalse(CallResult.ToJSON.Contains('SECRET BODY TEXT'), 'A list must not carry bodies');
    Assert.IsNull(Item.GetValue('body'));
    Assert.AreEqual('Hello Kees', Item.GetValue<string>('preview'));
    Assert.AreEqual('m1', Item.GetValue<string>('id'));
    Assert.IsTrue(Item.GetValue<Boolean>('has_attachments'));
    Assert.IsFalse(Item.GetValue<Boolean>('is_read'));
    Assert.AreEqual('2026-11-01T09:00:00Z', Item.GetValue<string>('received'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ListFoldersReturnsCounts;
begin
  FTransport.Respond(200, '{"value":[{"id":"f1","displayName":"Inbox","childFolderCount":2,"totalItemCount":40,"unreadItemCount":3}]}');
  const Tool: IMCPTool = TMailListFoldersTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk"}');
  try
    const Folder = TToolCall.Structured(CallResult).GetValue<TJSONObject>('folders[0]');
    Assert.AreEqual('Inbox', Folder.GetValue<string>('display_name'));
    Assert.AreEqual(3, Folder.GetValue<Integer>('unread_item_count'));
    Assert.Contains(FTransport.LastRequest.Url, '/me/mailFolders');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.GetAttachmentReturnsEmbeddedResource;
begin
  FTransport.Respond(200, '{"value":[{"id":"a1","name":"note.txt","contentType":"text/plain","size":5}]}');
  FTransport.Respond(200, '{"@odata.type":"#microsoft.graph.fileAttachment","id":"a1","name":"note.txt","contentType":"text/plain",' +
                          '"size":5,"contentBytes":"SGVsbG8="}');
  const Tool: IMCPTool = TMailGetAttachmentTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","attachment_id":"a1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Resource = CallResult.GetValue<TJSONObject>('content[1].resource');
    Assert.AreEqual('SGVsbG8=', Resource.GetValue<string>('blob'));
    Assert.AreEqual('text/plain', Resource.GetValue<string>('mimeType'));
    Assert.AreEqual('note.txt', TToolCall.Structured(CallResult).GetValue<string>('name'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.AttachmentOver10MbIsRefused;
begin
  FTransport.Respond(200, '{"value":[{"id":"a1","name":"video.mp4","contentType":"video/mp4","size":11000000}]}');
  const Tool: IMCPTool = TMailGetAttachmentTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","attachment_id":"a1"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), '10 MB');
    Assert.AreEqual(1, FTransport.RequestCount, 'The content must not be downloaded');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.CreateDraftSendsRecipients;
begin
  FTransport.Respond(200, SignatureNone);
  FTransport.Respond(201, '{"id":"d1","subject":"Offer"}');
  const Tool: IMCPTool = TMailCreateDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","to":["a@x.example.test"," b@x.example.test"],"cc":["c@x.example.test"],' +
                                '"subject":"Offer","body":"Dear Anna"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('d1', TToolCall.Structured(CallResult).GetValue<string>('draft_id'));

    Assert.AreEqual('POST', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Url, '/me/messages');

    const Body = RequestBody(1);
    try
      Assert.AreEqual('Offer', Body.GetValue<string>('subject'));
      Assert.AreEqual(2, Body.GetValue<TJSONArray>('toRecipients').Count);
      Assert.AreEqual('b@x.example.test', Body.GetValue<string>('toRecipients[1].emailAddress.address'));
      Assert.AreEqual('c@x.example.test', Body.GetValue<string>('ccRecipients[0].emailAddress.address'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.UpdateDraftKeepsOmittedFields;
begin
  FTransport.Respond(200, '{"id":"d1","subject":"Old subject","toRecipients":[{"emailAddress":{"address":"a@x.example.test"}}],' +
                          '"body":{"contentType":"html","content":"<p>old</p>"}}');
  FTransport.Respond(200, '{"id":"d1","subject":"New subject"}');
  const Tool: IMCPTool = TMailUpdateDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","draft_id":"d1","subject":"New subject"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('PATCH', FTransport.LastRequest.Method);

    const Body = RequestBody(1);
    try
      Assert.AreEqual('New subject', Body.GetValue<string>('subject'));
      Assert.AreEqual('a@x.example.test', Body.GetValue<string>('toRecipients[0].emailAddress.address'));
      Assert.AreEqual('<p>old</p>', Body.GetValue<string>('body.content'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ReplyDraftHonoursReplyAll;
begin
  FTransport.Respond(200, MessageJson);
  FTransport.Respond(201, '{"id":"r1","subject":"RE: Quarterly numbers"}');
  const Tool: IMCPTool = TMailCreateReplyDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","body":"Thanks","reply_all":true}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.RequestAt(1).Url, '/createReplyAll');
    Assert.AreEqual('r1', TToolCall.Structured(CallResult).GetValue<string>('draft_id'));
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SendWithoutTokenDoesNotCallGraph;
begin
  FTransport.Respond(200, SignatureNone);
  const Tool: IMCPTool = TMailSendTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","to":["a@x.example.test"],"subject":"Offer","body":"Dear Anna"}');
  try
    const Answer = TToolCall.Structured(CallResult);
    Assert.IsTrue(Answer.GetValue<Boolean>('confirmation_required'));
    Assert.IsNotEmpty(Answer.GetValue<string>('confirmation_token'));
    Assert.Contains(Answer.GetValue<string>('summary'), 'a@x.example.test');
    Assert.Contains(Answer.GetValue<string>('summary'), 'Offer');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SendWithTokenCreatesAndSendsDraft;
begin
  FTransport.Respond(200, SignatureNone);
  FTransport.Respond(201, '{"id":"d9","subject":"Offer"}');
  FTransport.Respond(202, '');
  const Tool: IMCPTool = TMailSendTool.Create(FServices);

  const Answer = Confirm(Tool, '{"mailbox":"gdk","to":["a@x.example.test"],"subject":"Offer","body":"Dear Anna"}');

  Assert.Contains(Answer, 'sent');
  Assert.AreEqual(3, FTransport.RequestCount);
  Assert.AreEqual('POST', FTransport.RequestAt(1).Method);
  Assert.Contains(FTransport.RequestAt(1).Url, '/me/messages');
  Assert.AreEqual('POST', FTransport.RequestAt(2).Method);
  Assert.Contains(FTransport.RequestAt(2).Url, '/messages/d9/send');
end;

procedure TMailToolsTests.SendDraftSummaryNamesRecipients;
begin
  FTransport.Respond(200, MessageJson);
  const Tool: IMCPTool = TMailSendDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","draft_id":"m1"}');
  try
    const Summary = TToolCall.Structured(CallResult).GetValue<string>('summary');
    Assert.Contains(Summary, 'kees@gdk.example.test');
    Assert.Contains(Summary, 'Quarterly numbers');
    for var Index := 0 to FTransport.RequestCount - 1 do
    begin
      Assert.AreEqual('GET', FTransport.RequestAt(Index).Method, 'Only the draft is read; nothing is sent');
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SendDraftSummaryNamesCcAndBcc;
begin
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  const Tool: IMCPTool = TMailSendDraftTool.Create(FServices);

  const CallResult = Call(Tool, SendDraftArguments);
  try
    const Summary = TToolCall.Structured(CallResult).GetValue<string>('summary');
    Assert.Contains(Summary, 'anna@other.example.test');
    Assert.Contains(Summary, 'cc@other.example.test');
    Assert.Contains(Summary, 'hidden@outside.example.test');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SendDraftWithTokenSendsUnchangedDraft;
begin
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  FTransport.Respond(202, '');
  const Tool: IMCPTool = TMailSendDraftTool.Create(FServices);

  const Answer = Confirm(Tool, SendDraftArguments);

  Assert.Contains(Answer, 'sent');
  Assert.AreEqual('POST', FTransport.LastRequest.Method);
  Assert.Contains(FTransport.LastRequest.Url, '/messages/d1/send');
end;

procedure TMailToolsTests.UpdatedDraftInvalidatesToken;
begin
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  FTransport.Respond(200, Format(DraftFormat, ['ck1']));
  FTransport.Respond(200, Format(DraftFormat, ['ck2']));
  const Tool: IMCPTool = TMailSendDraftTool.Create(FServices);

  const FirstAnswer = Call(Tool, SendDraftArguments);
  try
    const Token = TToolCall.Structured(FirstAnswer).GetValue<string>('confirmation_token');

    const SecondAnswer = Call(Tool, Format('{"mailbox":"gdk","draft_id":"d1","confirmation_token":"%s"}', [Token]));
    try
      Assert.IsTrue(TToolCall.Structured(SecondAnswer).GetValue<Boolean>('confirmation_required'), SecondAnswer.ToJSON);
      for var Index := 0 to FTransport.RequestCount - 1 do
      begin
        Assert.AreEqual('GET', FTransport.RequestAt(Index).Method, 'A draft that changed after the summary must not be sent');
      end;
    finally
      SecondAnswer.Free;
    end;
  finally
    FirstAnswer.Free;
  end;
end;

procedure TMailToolsTests.DeleteDraftRefusesNonDraft;
begin
  FTransport.Respond(200, '{"id":"m1","isDraft":false}');
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TMailDeleteDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","draft_id":"m1"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Text(CallResult), 'mail_delete');
    Assert.AreEqual(1, FTransport.RequestCount, 'A message that is not a draft must not be deleted');
    Assert.AreEqual('GET', FTransport.LastRequest.Method);
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.DeleteDraftDeletesDraft;
begin
  FTransport.Respond(200, '{"id":"d1","isDraft":true}');
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TMailDeleteDraftTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","draft_id":"d1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual(2, FTransport.RequestCount);
    Assert.Contains(FTransport.RequestAt(0).Url, 'isDraft');
    Assert.AreEqual('DELETE', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Url, '/messages/d1');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ForwardSummaryNamesMailboxAndRecipients;
begin
  FTransport.Respond(200, MessageJson);
  const Tool: IMCPTool = TMailForwardTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","to":["boss@x.example.test"],"comment":"FYI"}');
  try
    const Summary = TToolCall.Structured(CallResult).GetValue<string>('summary');
    Assert.Contains(Summary, '"gdk"');
    Assert.Contains(Summary, WorkUpn);
    Assert.Contains(Summary, 'boss@x.example.test');
    Assert.Contains(Summary, 'Quarterly numbers');
    Assert.AreEqual(1, FTransport.RequestCount, 'Nothing is forwarded before the confirmation');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.DeleteMovesToDeletedItems;
begin
  FTransport.Respond(200, MessageJson);
  FTransport.Respond(201, '{"id":"m1-moved"}');
  const Tool: IMCPTool = TMailDeleteTool.Create(FServices);

  const FirstAnswer = Call(Tool, '{"mailbox":"gdk","message_id":"m1"}');
  try
    const Summary = TToolCall.Structured(FirstAnswer).GetValue<string>('summary');
    Assert.Contains(Summary, 'Quarterly numbers');
    Assert.Contains(Summary, 'anna@other.example.test');
  finally
    FirstAnswer.Free;
  end;

  const Answer = Confirm(Tool, '{"mailbox":"gdk","message_id":"m1"}');
  Assert.Contains(Answer, 'Deleted Items');

  Assert.Contains(FTransport.LastRequest.Url, '/messages/m1/move');
  const Body = RequestBody(FTransport.RequestCount - 1);
  try
    Assert.AreEqual('deleteditems', Body.GetValue<string>('destinationId'));
  finally
    Body.Free;
  end;
end;

procedure TMailToolsTests.MoveAcceptsWellKnownFolderName;
begin
  FTransport.Respond(201, '{"id":"m1-moved"}');
  const Tool: IMCPTool = TMailMoveTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","destination_folder":"Archive"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('m1-moved', TToolCall.Structured(CallResult).GetValue<string>('message_id'));

    const Body = RequestBody(0);
    try
      Assert.AreEqual('archive', Body.GetValue<string>('destinationId'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.MarkReadSendsIsRead;
begin
  FTransport.Respond(200, '{"id":"m1"}');
  const Tool: IMCPTool = TMailMarkReadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","is_read":true}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('PATCH', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Body, '"isRead":true');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SharedMailboxRequestsUseUsersPath;
begin
  FTransport.Respond(200, EmptyList);
  const Tool: IMCPTool = TMailListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"sales"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/users/sales');
    Assert.IsFalse(FTransport.LastRequest.Url.Contains('/me/'), 'A shared mailbox must not be read through /me');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.ToolsCarryTheirAnnotations;
begin
  const Search = TMailSearchTool.Create(FServices);
  const SearchTool: IMCPTool = Search;
  Assert.IsTrue(Search.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('mail_search', SearchTool.Name);

  const Send = TMailSendTool.Create(FServices);
  const SendTool: IMCPTool = Send;
  Assert.IsFalse(Send.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsTrue(Send.GetAnnotations.GetValue<Boolean>('destructiveHint'));
  Assert.IsTrue(Send.GetAnnotations.GetValue<Boolean>('openWorldHint'));
  Assert.IsNull(SendTool.OutputSchema, 'A confirmed tool has two answer shapes and publishes no output schema');

  const Draft = TMailCreateDraftTool.Create(FServices);
  const DraftTool: IMCPTool = Draft;
  Assert.IsFalse(Draft.GetAnnotations.GetValue<Boolean>('destructiveHint'));
  Assert.AreEqual('mail_create_draft', DraftTool.Name);
end;

procedure TMailToolsTests.MoveToDeletedItemsPointsToMailDelete;
begin
  FTransport.Respond(201, '{"id":"m1-moved"}');
  const Tool: IMCPTool = TMailMoveTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","destination_folder":"DeletedItems"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Text(CallResult), 'mail_delete');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.AttachmentMissingFromListIsNotDownloaded;
begin
  FTransport.Respond(200, '{"value":[{"id":"a1","name":"note.txt","contentType":"text/plain","size":5}]}');
  FTransport.Respond(200, '{"@odata.type":"#microsoft.graph.fileAttachment","id":"a2","name":"big.bin","size":5,"contentBytes":"SGVsbG8="}');
  const Tool: IMCPTool = TMailGetAttachmentTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","message_id":"m1","attachment_id":"a2"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(TToolCall.Text(CallResult), 'mail_list_attachments');
    Assert.AreEqual(1, FTransport.RequestCount, 'Only the list is read');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SearchEscapesQuotesInQuery;
begin
  FTransport.Respond(200, EmptyList);
  const Tool: IMCPTool = TMailSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"subject:\"Q3 plan\""}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '%5C%22Q3');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SearchEscapesTrailingBackslash;
begin
  FTransport.Respond(200, EmptyList);
  const Tool: IMCPTool = TMailSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"C:\\temp\\"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, 'temp%5C%5C"');
  finally
    CallResult.Free;
  end;
end;

procedure TMailToolsTests.SearchEscapesBackslashBeforeQuote;
begin
  FTransport.Respond(200, EmptyList);
  const Tool: IMCPTool = TMailSearchTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"a\\\"b"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, 'a%5C%5C%5C%22b');
  finally
    CallResult.Free;
  end;
end;

end.
