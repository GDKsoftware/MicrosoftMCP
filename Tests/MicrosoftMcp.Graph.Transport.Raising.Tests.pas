unit MicrosoftMcp.Graph.Transport.Raising.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces,
  MicrosoftMcp.Fakes.GraphTransport;

type
  [TestFixture]
  TRaisingGraphTransportTests = class
  private
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;
    FFactory: IGraphClientFactory;
    FMailbox: TResolvedMailbox;

    procedure ListFolders;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure HttpErrorPropagatesThroughMailClient;

    [Test]
    procedure ThrottlingCarriesRetryAfter;

    [Test]
    procedure ErrorMessageHasNoGraphText;

    [Test]
    procedure SuccessPassesThrough;

    [Test]
    procedure PayloadTooLargePassesThrough;

    [Test]
    procedure GraphHttpErrorIsTranslatedWithRetryAfter;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Net.URLClient,
  MSGraph.Graph.Http,
  MSGraph.Graph.Mail,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Graph.Errors,
  MicrosoftMcp.Graph.Exceptions;

const
  SecretMailText = 'Subject: salary of Anna';
  AccessDeniedBody = '{"error":{"code":"ErrorAccessDenied","message":"' + SecretMailText + '"}}';
  ThrottledBody = '{"error":{"code":"TooManyRequests","message":"Slow down"}}';
  AccountPage = 'https://auth.example.test/account';

{ TRaisingGraphTransportTests }

procedure TRaisingGraphTransportTests.Setup;
begin
  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;
  FFactory := TGraphClientFactory.Create(FTransport);

  FMailbox := Default(TResolvedMailbox);
  FMailbox.Mailbox.Slug := 'work';
  FMailbox.Mailbox.Kind := TMailboxKind.Own;
  FMailbox.AccessToken := 'token';
end;

procedure TRaisingGraphTransportTests.TearDown;
begin
  FFactory := nil;
  FTransport := nil;
  FTransportInterface := nil;
end;

procedure TRaisingGraphTransportTests.ListFolders;
begin
  const Graph = FFactory.Create(FMailbox);
  const MailClient = TMailClient.Create(Graph, True);
  try
    MailClient.ListMailFolders;
  finally
    MailClient.Free;
  end;
end;

procedure TRaisingGraphTransportTests.HttpErrorPropagatesThroughMailClient;
begin
  FTransport.Respond(403, AccessDeniedBody);

  var Raised: EGraphHttpError := nil;
  try
    ListFolders;
  except
    on EGraphHttpError do
    begin
      Raised := EGraphHttpError(AcquireExceptionObject);
    end;
  end;

  try
    Assert.IsNotNull(Raised, 'The HTTP error must reach the caller of TMailClient as EGraphHttpError');
    Assert.AreEqual(403, Raised.StatusCode);
    Assert.AreEqual('ErrorAccessDenied', Raised.ErrorCode);
  finally
    Raised.Free;
  end;
end;

procedure TRaisingGraphTransportTests.ThrottlingCarriesRetryAfter;
begin
  FTransport.Respond(429, ThrottledBody, [TNetHeader.Create('Retry-After', '17')]);

  var Raised: EGraphHttpError := nil;
  try
    ListFolders;
  except
    on EGraphHttpError do
    begin
      Raised := EGraphHttpError(AcquireExceptionObject);
    end;
  end;

  try
    Assert.IsNotNull(Raised);
    Assert.AreEqual(429, Raised.StatusCode);
    Assert.AreEqual(17, Raised.RetryAfterSeconds);
  finally
    Raised.Free;
  end;
end;

procedure TRaisingGraphTransportTests.ErrorMessageHasNoGraphText;
begin
  FTransport.Respond(403, AccessDeniedBody);

  var Message := '';
  try
    ListFolders;
  except
    on E: EGraphHttpError do
    begin
      Message := E.Message;
    end;
  end;

  Assert.IsFalse(Message.IsEmpty);
  Assert.IsFalse(Message.Contains(SecretMailText), 'The text of Graph can quote mail and must stay out of the message');
end;

procedure TRaisingGraphTransportTests.SuccessPassesThrough;
begin
  FTransport.Respond(200, '{"id":"inbox-id"}');

  const Graph = FFactory.Create(FMailbox);
  try
    const Inbox = Graph.Get('/me/mailFolders/inbox');
    try
      Assert.AreEqual('inbox-id', Inbox.GetValue<string>('id'));
    finally
      Inbox.Free;
    end;
  finally
    Graph.Free;
  end;
end;

procedure TRaisingGraphTransportTests.PayloadTooLargePassesThrough;
begin
  FTransport.Respond(413, '{"error":{"code":"ErrorRequestEntityTooLarge","message":"too large"}}');

  const Graph = FFactory.Create(FMailbox);
  try
    const Response = Graph.PostRaw('/me/messages/1/attachments', '{}');

    Assert.AreEqual(413, Response.StatusCode, 'The attachment uploader switches to an upload session on 413, so it must see it');
  finally
    Graph.Free;
  end;
end;

procedure TRaisingGraphTransportTests.GraphHttpErrorIsTranslatedWithRetryAfter;
begin
  const Translator = TGraphErrorTranslator.Create(AccountPage);
  const Error = EGraphHttpError.Create(429, 'TooManyRequests', 17);
  try
    const Message = Translator.Translate(Error, FMailbox.Mailbox);

    Assert.Contains(Message, '17 s');
  finally
    Error.Free;
    Translator.Free;
  end;
end;

end.
