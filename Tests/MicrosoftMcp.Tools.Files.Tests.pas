unit MicrosoftMcp.Tools.Files.Tests;

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
  TFilesToolsTests = class
  private
    FMailboxes: IMailboxRepository;
    FAccounts: TFakeUpstreamAccounts;
    FAccountsInterface: IInterface;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FServices: IToolServices;

    procedure AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
    function Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
    function CountRequests(const Method: string): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure SharePointSearchSitesReturnsSites;

    [Test]
    procedure SharePointListFilesUsesSiteAndFolder;

    [Test]
    procedure SharePointSearchFilesPassesQuery;

    [Test]
    procedure SharePointSearchFilesDoublesApostrophes;

    [Test]
    procedure SharePointReadReturnsTextForTextFiles;

    [Test]
    procedure SharePointReadReturnsEmbeddedResourceForOfficeFiles;

    [Test]
    procedure BinaryOver10MbIsRefused;

    [Test]
    procedure SharePointListAndReadPages;

    [Test]
    procedure OneDriveListUsesRootForSlash;

    [Test]
    procedure OneDriveListUsesPath;

    [Test]
    procedure OneDriveReadReturnsText;

    [Test]
    procedure OneDriveReadOver10MbIsRefused;

    [Test]
    procedure OneDriveUploadSendsTextContent;

    [Test]
    procedure OneDriveUploadSendsBase64Content;

    [Test]
    procedure OneDriveUploadReplacesOnlyWhenAsked;

    [Test]
    procedure OneDriveUploadRejectsBothContentFields;

    [Test]
    procedure OneDriveUploadRejectsMissingContent;

    [Test]
    procedure OneDriveUploadOver10MbIsRefused;

    [Test]
    procedure OneDriveCreateFolderPostsFolder;

    [Test]
    procedure OneDriveMoveKeepsNameWhenOnlyParentGiven;

    [Test]
    procedure OneDriveDeleteNeedsConfirmation;

    [Test]
    procedure SharedMailboxFilesUseUnderlyingAccountAndSayItInResult;

    [Test]
    procedure ToolsCarryTheirAnnotations;

    [Test]
    procedure UploadIsMarkedDestructive;

    [Test]
    procedure DeleteAndMoveRefuseTheRoot;
  end;

implementation

uses
  System.SysUtils,
  System.NetEncoding,
  MCPAuth.Clock,
  MCPAuth.Secret.Token,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Tools.Services,
  MicrosoftMcp.Tools.SharePoint.SearchSites,
  MicrosoftMcp.Tools.SharePoint.ListFiles,
  MicrosoftMcp.Tools.SharePoint.SearchFiles,
  MicrosoftMcp.Tools.SharePoint.ReadFile,
  MicrosoftMcp.Tools.SharePoint.ListPages,
  MicrosoftMcp.Tools.SharePoint.ReadPage,
  MicrosoftMcp.Tools.OneDrive.List,
  MicrosoftMcp.Tools.OneDrive.Read,
  MicrosoftMcp.Tools.OneDrive.Upload,
  MicrosoftMcp.Tools.OneDrive.CreateFolder,
  MicrosoftMcp.Tools.OneDrive.Move,
  MicrosoftMcp.Tools.OneDrive.Delete,
  MicrosoftMcp.Tests.ToolCall;

const
  Kees = 'user-kees';
  WorkKey = 'acc-work';
  WorkUpn = 'kees@gdk.example.test';
  OwnSlug = 'gdk';
  SharedSlug = 'sales';
  SharedAddress = 'sales@gdk.example.test';
  TextFileJson = '{"id":"i1","name":"notes.txt","size":5,"file":{"mimeType":"text/plain"}}';
  WordFileJson = '{"id":"i2","name":"plan.docx","size":4,"file":{"mimeType":"application/vnd.openxmlformats-officedocument.wordprocessingml.document"}}';
  HugeFileJson = '{"id":"i3","name":"video.mp4","size":11000000,"file":{"mimeType":"video/mp4"}}';
  DriveTextJson = '{"id":"d1","name":"notes.txt","size":5,"file":{"mimeType":"text/plain"},"@microsoft.graph.downloadUrl":"https://download.example.test/d1"}';
  DriveHugeJson = '{"id":"d2","name":"video.mp4","size":11000000,"file":{"mimeType":"video/mp4"},"@microsoft.graph.downloadUrl":"https://download.example.test/d2"}';
  DriveFolderJson = '{"id":"d3","name":"Docs","size":0,"folder":{"childCount":2},"parentReference":{"id":"root-id"}}';
  UploadedJson = '{"id":"u1","name":"a.txt","size":5,"file":{"mimeType":"text/plain"}}';
  MaximumBytes = 10 * 1024 * 1024;

{ TFilesToolsTests }

procedure TFilesToolsTests.Setup;
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

procedure TFilesToolsTests.TearDown;
begin
  FServices := nil;
  FTransport := nil;
  FTransportInterface := nil;
  FAccounts := nil;
  FAccountsInterface := nil;
  FMailboxes := nil;
end;

procedure TFilesToolsTests.AddMailbox(const Slug: string; const Kind: TMailboxKind; const Address: string);
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

function TFilesToolsTests.Call(const Tool: IMCPTool; const ArgumentsJson: string): TJSONObject;
begin
  Result := TToolCall.Run(Tool, Kees, ArgumentsJson);
end;

function TFilesToolsTests.CountRequests(const Method: string): Integer;
begin
  Result := 0;
  for var Index := 0 to FTransport.RequestCount - 1 do
  begin
    if FTransport.RequestAt(Index).Method = Method then
      Inc(Result);
  end;
end;

procedure TFilesToolsTests.SharePointSearchSitesReturnsSites;
begin
  FTransport.Respond(200, '{"value":[{"id":"gdk.example.test,s1,w1","name":"sales","displayName":"Sales","webUrl":"https://gdk.example.test/sites/sales"}]}');
  const Tool: IMCPTool = TSharePointSearchSitesTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","query":"sales"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/sites');
    Assert.Contains(FTransport.LastRequest.Url, 'search=sales');
    Assert.AreEqual('Sales', TToolCall.Structured(CallResult).GetValue<string>('sites[0].display_name'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.SharePointListFilesUsesSiteAndFolder;
begin
  FTransport.Respond(200, '{"value":[' + TextFileJson + ']}');
  const Tool: IMCPTool = TSharePointListFilesTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","folder_id":"folder1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/sites/site1/drive/items/folder1/children');
    Assert.AreEqual('notes.txt', TToolCall.Structured(CallResult).GetValue<string>('items[0].name'));
    Assert.AreEqual('file', TToolCall.Structured(CallResult).GetValue<string>('items[0].type'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.SharePointSearchFilesPassesQuery;
begin
  FTransport.Respond(200, '{"value":[' + TextFileJson + ']}');
  const Tool: IMCPTool = TSharePointSearchFilesTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","query":"budget"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/sites/site1/drive/root/search');
    Assert.Contains(FTransport.LastRequest.Url, 'budget');
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.SharePointReadReturnsTextForTextFiles;
begin
  FTransport.Respond(200, TextFileJson);
  FTransport.Respond(200, 'Hello');
  const Tool: IMCPTool = TSharePointReadFileTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","item_id":"i1"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('Hello', CallResult.GetValue<string>('content[1].text'));
    Assert.IsTrue(TToolCall.Structured(CallResult).GetValue<Boolean>('is_text'));
    Assert.AreEqual('text/plain', TToolCall.Structured(CallResult).GetValue<string>('content_type'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.SharePointReadReturnsEmbeddedResourceForOfficeFiles;
begin
  FTransport.Respond(200, WordFileJson);
  FTransport.RespondBytes(200, [1, 2, 3, 4]);
  const Tool: IMCPTool = TSharePointReadFileTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","item_id":"i2"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Resource = CallResult.GetValue<TJSONObject>('content[1].resource');
    Assert.AreEqual('AQIDBA==', Resource.GetValue<string>('blob'));
    Assert.Contains(Resource.GetValue<string>('mimeType'), 'wordprocessingml');
    Assert.IsFalse(TToolCall.Structured(CallResult).GetValue<Boolean>('is_text'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.BinaryOver10MbIsRefused;
begin
  FTransport.Respond(200, HugeFileJson);
  const Tool: IMCPTool = TSharePointReadFileTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","item_id":"i3"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), '10 MB');
    Assert.AreEqual(1, FTransport.RequestCount, 'The content must not be downloaded');
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.SharePointListAndReadPages;
begin
  FTransport.Respond(200, '{"value":[{"id":"pg1","title":"Welcome","name":"home.aspx","webUrl":"https://gdk.example.test/sites/sales/home.aspx"}]}');
  FTransport.Respond(200, '{"id":"pg1","title":"Welcome","canvasLayout":{"horizontalSections":[{"columns":[{"webparts":[{"innerHtml":"<p>Hi all</p>"}]}]}]}}');

  const ListTool: IMCPTool = TSharePointListPagesTool.Create(FServices);
  const ListResult = Call(ListTool, '{"mailbox":"gdk","site_id":"site1"}');
  try
    Assert.IsFalse(TToolCall.IsError(ListResult), ListResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/sites/site1/pages');
    Assert.AreEqual('Welcome', TToolCall.Structured(ListResult).GetValue<string>('pages[0].title'));
  finally
    ListResult.Free;
  end;

  const ReadTool: IMCPTool = TSharePointReadPageTool.Create(FServices);
  const ReadResult = Call(ReadTool, '{"mailbox":"gdk","site_id":"site1","page_id":"pg1"}');
  try
    Assert.IsFalse(TToolCall.IsError(ReadResult), ReadResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/sites/site1/pages/pg1');
    Assert.Contains(TToolCall.Structured(ReadResult).GetValue<string>('content_html'), 'Hi all');
  finally
    ReadResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveListUsesRootForSlash;
begin
  FTransport.Respond(200, '{"value":[' + DriveFolderJson + ',' + DriveTextJson + ']}');
  const Tool: IMCPTool = TOneDriveListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"/"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/drive/root/children');
    Assert.AreEqual('folder', TToolCall.Structured(CallResult).GetValue<string>('items[0].type'));
    Assert.AreEqual('file', TToolCall.Structured(CallResult).GetValue<string>('items[1].type'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveListUsesPath;
begin
  FTransport.Respond(200, '{"value":[]}');
  const Tool: IMCPTool = TOneDriveListTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"Docs/Sub folder"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/drive/root:/Docs/Sub%20folder:/children');
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveReadReturnsText;
begin
  FTransport.Respond(200, DriveTextJson);
  FTransport.Respond(200, 'Hello');
  const Tool: IMCPTool = TOneDriveReadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"notes.txt"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('Hello', CallResult.GetValue<string>('content[1].text'));
    Assert.AreEqual('https://download.example.test/d1', FTransport.LastRequest.Url);
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveReadOver10MbIsRefused;
begin
  FTransport.Respond(200, DriveHugeJson);
  const Tool: IMCPTool = TOneDriveReadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"video.mp4"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), '10 MB');
    Assert.AreEqual(1, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveUploadSendsTextContent;
begin
  FTransport.Respond(201, UploadedJson);
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"Notes/a.txt","content":"Hello"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);

    const Request = FTransport.LastRequest;
    Assert.AreEqual('PUT', Request.Method);
    Assert.Contains(Request.Url, '/me/drive/root:/Notes/a.txt:/content');
    Assert.AreEqual('Hello', TEncoding.UTF8.GetString(Request.BodyBytes));
    Assert.AreEqual('u1', TToolCall.Structured(CallResult).GetValue<string>('item_id'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveUploadSendsBase64Content;
begin
  FTransport.Respond(201, UploadedJson);
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"a.bin","content_base64":"AQIDBA=="}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual(4, Integer(Length(FTransport.LastRequest.BodyBytes)));
    Assert.AreEqual(3, Integer(FTransport.LastRequest.BodyBytes[2]));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveUploadReplacesOnlyWhenAsked;
begin
  FTransport.Respond(201, UploadedJson);
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);

  const KeepResult = Call(Tool, '{"mailbox":"gdk","path":"a.txt","content":"x"}');
  KeepResult.Free;
  Assert.Contains(FTransport.LastRequest.Url, 'conflictBehavior=fail');

  const ReplaceResult = Call(Tool, '{"mailbox":"gdk","path":"a.txt","content":"x","overwrite":true}');
  ReplaceResult.Free;
  Assert.Contains(FTransport.LastRequest.Url, 'conflictBehavior=replace');
end;

procedure TFilesToolsTests.OneDriveUploadRejectsBothContentFields;
begin
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"a.txt","content":"Hello","content_base64":"SGVsbG8="}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), 'content_base64');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveUploadRejectsMissingContent;
begin
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"a.txt"}');
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveUploadOver10MbIsRefused;
begin
  const Tool: IMCPTool = TOneDriveUploadTool.Create(FServices);
  const Huge = StringOfChar('A', (MaximumBytes div 3 + 2) * 4);

  const CallResult = Call(Tool, Format('{"mailbox":"gdk","path":"big.bin","content_base64":"%s"}', [Huge]));
  try
    Assert.IsTrue(TToolCall.IsError(CallResult));
    Assert.Contains(TToolCall.Text(CallResult), '10 MB');
    Assert.AreEqual(0, FTransport.RequestCount);
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveCreateFolderPostsFolder;
begin
  FTransport.Respond(201, '{"id":"nf1","name":"Archive","folder":{"childCount":0}}');
  const Tool: IMCPTool = TOneDriveCreateFolderTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","parent_path":"Docs","name":"Archive"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('POST', FTransport.LastRequest.Method);
    Assert.Contains(FTransport.LastRequest.Url, '/me/drive/root:/Docs:/children');
    Assert.Contains(FTransport.LastRequest.Body, 'Archive');
    Assert.AreEqual('nf1', TToolCall.Structured(CallResult).GetValue<string>('item_id'));
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveMoveKeepsNameWhenOnlyParentGiven;
begin
  FTransport.Respond(200, '{"id":"d1","name":"notes.txt","size":5,"file":{"mimeType":"text/plain"},"parentReference":{"id":"old-parent"}}');
  FTransport.Respond(200, '{"id":"d1","name":"notes.txt","size":5,"file":{"mimeType":"text/plain"}}');
  const Tool: IMCPTool = TOneDriveMoveTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","path":"notes.txt","new_parent_id":"new-parent"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.AreEqual('PATCH', FTransport.LastRequest.Method);

    const Body = TJSONObject.ParseJSONValue(FTransport.LastRequest.Body) as TJSONObject;
    try
      Assert.AreEqual('new-parent', Body.GetValue<string>('parentReference.id'));
      Assert.AreEqual('notes.txt', Body.GetValue<string>('name'));
    finally
      Body.Free;
    end;
  finally
    CallResult.Free;
  end;
end;

procedure TFilesToolsTests.OneDriveDeleteNeedsConfirmation;
begin
  FTransport.Respond(200, DriveTextJson);
  FTransport.Respond(204, '');
  const Tool: IMCPTool = TOneDriveDeleteTool.Create(FServices);

  const FirstAnswer = Call(Tool, '{"mailbox":"gdk","path":"notes.txt"}');
  try
    Assert.IsTrue(TToolCall.Structured(FirstAnswer).GetValue<Boolean>('confirmation_required'), FirstAnswer.ToJSON);
    Assert.Contains(TToolCall.Structured(FirstAnswer).GetValue<string>('summary'), 'notes.txt');
    Assert.AreEqual(0, CountRequests('DELETE'));

    const Token = TToolCall.Structured(FirstAnswer).GetValue<string>('confirmation_token');
    const SecondAnswer = Call(Tool, Format('{"mailbox":"gdk","path":"notes.txt","confirmation_token":"%s"}', [Token]));
    try
      Assert.IsFalse(TToolCall.IsError(SecondAnswer), SecondAnswer.ToJSON);
      Assert.AreEqual(1, CountRequests('DELETE'));
      Assert.Contains(FTransport.LastRequest.Url, '/me/drive/root:/notes.txt:');
    finally
      SecondAnswer.Free;
    end;
  finally
    FirstAnswer.Free;
  end;
end;

procedure TFilesToolsTests.SharedMailboxFilesUseUnderlyingAccountAndSayItInResult;
begin
  FTransport.Respond(200, '{"value":[]}');

  const DriveTool: IMCPTool = TOneDriveListTool.Create(FServices);
  const DriveResult = Call(DriveTool, '{"mailbox":"sales","path":"/"}');
  try
    Assert.IsFalse(TToolCall.IsError(DriveResult), DriveResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, '/me/drive');
    Assert.DoesNotContain(FTransport.LastRequest.Url, '/users/');
    Assert.Contains(TToolCall.Structured(DriveResult).GetValue<string>('note'), WorkUpn);
    Assert.Contains(TToolCall.Structured(DriveResult).GetValue<string>('note'), 'shared mailbox');
  finally
    DriveResult.Free;
  end;

  const SiteTool: IMCPTool = TSharePointSearchSitesTool.Create(FServices);
  const SiteResult = Call(SiteTool, '{"mailbox":"sales","query":"sales"}');
  try
    Assert.IsFalse(TToolCall.IsError(SiteResult), SiteResult.ToJSON);
    Assert.DoesNotContain(FTransport.LastRequest.Url, '/users/');
    Assert.Contains(TToolCall.Structured(SiteResult).GetValue<string>('note'), WorkUpn);
  finally
    SiteResult.Free;
  end;

  const OwnResult = Call(DriveTool, '{"mailbox":"gdk","path":"/"}');
  try
    Assert.AreEqual('', TToolCall.Structured(OwnResult).GetValue<string>('note'));
  finally
    OwnResult.Free;
  end;
end;

procedure TFilesToolsTests.ToolsCarryTheirAnnotations;
begin
  const List = TOneDriveListTool.Create(FServices);
  const ListTool: IMCPTool = List;
  Assert.IsTrue(List.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('onedrive_list', ListTool.Name);

  const Delete = TOneDriveDeleteTool.Create(FServices);
  const DeleteTool: IMCPTool = Delete;
  Assert.IsFalse(Delete.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('destructiveHint'));
  Assert.IsTrue(Delete.GetAnnotations.GetValue<Boolean>('openWorldHint'));
  Assert.IsNull(DeleteTool.OutputSchema);
  Assert.AreEqual('onedrive_delete', DeleteTool.Name);

  const Read = TSharePointReadFileTool.Create(FServices);
  const ReadTool: IMCPTool = Read;
  Assert.IsTrue(Read.GetAnnotations.GetValue<Boolean>('readOnlyHint'));
  Assert.AreEqual('sharepoint_read_file', ReadTool.Name);
end;

procedure TFilesToolsTests.UploadIsMarkedDestructive;
begin
  const Upload = TOneDriveUploadTool.Create(FServices);
  const UploadTool: IMCPTool = Upload;

  Assert.IsTrue(Upload.GetAnnotations.GetValue<Boolean>('destructiveHint'), 'overwrite:true replaces a file');
  Assert.AreEqual('onedrive_upload', UploadTool.Name);
end;

procedure TFilesToolsTests.DeleteAndMoveRefuseTheRoot;
begin
  FTransport.Respond(200, DriveTextJson);
  const DeleteTool: IMCPTool = TOneDriveDeleteTool.Create(FServices);
  const MoveTool: IMCPTool = TOneDriveMoveTool.Create(FServices);

  const DeleteResult = Call(DeleteTool, '{"mailbox":"gdk","path":" / "}');
  try
    Assert.IsTrue(TToolCall.IsError(DeleteResult), DeleteResult.ToJSON);
  finally
    DeleteResult.Free;
  end;

  const MoveResult = Call(MoveTool, '{"mailbox":"gdk","path":"","new_name":"x"}');
  try
    Assert.IsTrue(TToolCall.IsError(MoveResult), MoveResult.ToJSON);
  finally
    MoveResult.Free;
  end;

  Assert.AreEqual(0, FTransport.RequestCount, 'The root of the drive is never read, moved or deleted');
end;

procedure TFilesToolsTests.SharePointSearchFilesDoublesApostrophes;
begin
  FTransport.Respond(200, '{"value":[]}');
  const Tool: IMCPTool = TSharePointSearchFilesTool.Create(FServices);

  const CallResult = Call(Tool, '{"mailbox":"gdk","site_id":"site1","query":"O''Brien"}');
  try
    Assert.IsFalse(TToolCall.IsError(CallResult), CallResult.ToJSON);
    Assert.Contains(FTransport.LastRequest.Url, 'q=''O''''Brien'')');
  finally
    CallResult.Free;
  end;
end;

end.
