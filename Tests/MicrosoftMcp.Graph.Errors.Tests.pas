unit MicrosoftMcp.Graph.Errors.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Graph.Errors,
  MicrosoftMcp.Fakes.GraphTransport;

type
  [TestFixture]
  TGraphErrorsTests = class
  private
    FTranslator: TGraphErrorTranslator;
    FOwnMailbox: TMailbox;
    FSharedMailbox: TMailbox;
    FTransport: TFakeGraphTransport;
    FTransportInterface: IInterface;

    function TranslateGet(const Mailbox: TMailbox): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure SharedMailbox403ExplainsFullAccessAndConsent;

    [Test]
    procedure OwnMailbox403AsksForConsentOnly;

    [Test]
    procedure NotFoundSaysItemNotFound;

    [Test]
    procedure ThrottlingMentionsRetryAfter;

    [Test]
    procedure ThrottlingWithoutHeaderSaysRetryLater;

    [Test]
    procedure ThrottlingWithHttpDateSaysRetryLater;

    [Test]
    procedure UnauthorizedPointsToAccountPage;

    [Test]
    procedure ServerErrorSaysTryAgainLater;

    [Test]
    procedure ErrorBodyTextNeverReachesTheMessage;

    [Test]
    procedure SuccessObjectIsNotAnError;

    [Test]
    procedure GraphApiExceptionIsTranslatedByStatus;

    [Test]
    procedure MailboxExceptionKeepsItsOwnMessage;

    [Test]
    procedure OtherExceptionNamesOnlyTheClass;

    [Test]
    procedure OtherExceptionDoesNotBlameGraph;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Net.URLClient,
  MSGraph.OAuth2.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Exceptions;

const
  AccountPage = 'https://auth.example.test/account';
  SecretBody = 'Subject: salary review for Anna';

{ TGraphErrorsTests }

procedure TGraphErrorsTests.Setup;
begin
  FTranslator := TGraphErrorTranslator.Create(AccountPage);

  FOwnMailbox := Default(TMailbox);
  FOwnMailbox.Slug := 'prive';
  FOwnMailbox.Kind := TMailboxKind.Own;

  FSharedMailbox := Default(TMailbox);
  FSharedMailbox.Slug := 'projects';
  FSharedMailbox.Address := 'projects@example.test';
  FSharedMailbox.Kind := TMailboxKind.Shared;

  FTransport := TFakeGraphTransport.Create;
  FTransportInterface := FTransport;
end;

procedure TGraphErrorsTests.TearDown;
begin
  FTransport := nil;
  FTransportInterface := nil;
  FTranslator.Free;
end;

// Goes through the real TGraphHttpClient, which returns an {"error": ...} object instead of raising.
function TGraphErrorsTests.TranslateGet(const Mailbox: TMailbox): string;
begin
  const Client = TGraphHttpClient.Create('token', FTransport);
  try
    const Json = Client.Get('/me/messages/abc');
    try
      Assert.IsTrue(FTranslator.TryTranslateErrorObject(Json, Mailbox, Result), 'the error object was not recognised');
    finally
      Json.Free;
    end;
  finally
    Client.Free;
  end;
end;

procedure TGraphErrorsTests.SharedMailbox403ExplainsFullAccessAndConsent;
begin
  FTransport.Respond(403, '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}');

  const Message = TranslateGet(FSharedMailbox);

  Assert.Contains(Message, 'FullAccess');
  Assert.Contains(Message, 'Exchange');
  Assert.Contains(Message, '.Shared');
  Assert.Contains(Message, AccountPage);
end;

procedure TGraphErrorsTests.OwnMailbox403AsksForConsentOnly;
begin
  FTransport.Respond(403, '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}');

  const Message = TranslateGet(FOwnMailbox);

  Assert.Contains(Message, AccountPage);
  Assert.DoesNotContain(Message, 'FullAccess');
end;

procedure TGraphErrorsTests.NotFoundSaysItemNotFound;
begin
  FTransport.Respond(404, '{"error":{"code":"ErrorItemNotFound","message":"The specified object was not found."}}');

  const Message = TranslateGet(FOwnMailbox);

  Assert.Contains(Message, 'item not found');
end;

procedure TGraphErrorsTests.ThrottlingMentionsRetryAfter;
begin
  FTransport.Respond(429, '{"error":{"code":"TooManyRequests","message":"slow down"}}', [TNetHeader.Create('Retry-After', '17')]);
  const Client = TGraphHttpClient.Create('token', FTransport);
  try
    const Response = Client.PostRaw('/me/sendMail', '{}');

    const Message = FTranslator.TranslateResponse(Response, FOwnMailbox);

    Assert.Contains(Message, 'retry after 17 s');
  finally
    Client.Free;
  end;
end;

procedure TGraphErrorsTests.ThrottlingWithoutHeaderSaysRetryLater;
begin
  FTransport.Respond(429, '{"error":{"code":"TooManyRequests","message":"slow down"}}');

  const Message = TranslateGet(FOwnMailbox);

  Assert.Contains(Message, 'retry later');
end;

procedure TGraphErrorsTests.ThrottlingWithHttpDateSaysRetryLater;
begin
  FTransport.Respond(429, '{}', [TNetHeader.Create('Retry-After', 'Wed, 21 Oct 2026 07:28:00 GMT')]);
  const Client = TGraphHttpClient.Create('token', FTransport);
  try
    const Response = Client.PostRaw('/me/sendMail', '{}');

    const Message = FTranslator.TranslateResponse(Response, FOwnMailbox);

    Assert.Contains(Message, 'retry later');
  finally
    Client.Free;
  end;
end;

procedure TGraphErrorsTests.UnauthorizedPointsToAccountPage;
begin
  FTransport.Respond(401, '{"error":{"code":"InvalidAuthenticationToken","message":"expired"}}');

  const Message = TranslateGet(FOwnMailbox);

  Assert.Contains(Message, AccountPage);
  Assert.Contains(Message, '401');
end;

procedure TGraphErrorsTests.ServerErrorSaysTryAgainLater;
begin
  FTransport.Respond(503, '{"error":{"code":"serviceNotAvailable","message":"down"}}');

  const Message = TranslateGet(FOwnMailbox);

  Assert.Contains(Message, 'try again later');
end;

procedure TGraphErrorsTests.ErrorBodyTextNeverReachesTheMessage;
begin
  FTransport.Respond(400, Format('{"error":{"code":"BadRequest","message":"%s"}}', [SecretBody]));

  const Message = TranslateGet(FOwnMailbox);

  Assert.DoesNotContain(Message, SecretBody);
  Assert.DoesNotContain(Message, 'token');
end;

procedure TGraphErrorsTests.SuccessObjectIsNotAnError;
begin
  const Json = TJSONObject.ParseJSONValue('{"id":"abc"}') as TJSONObject;
  try
    var Message := '';

    Assert.IsFalse(FTranslator.TryTranslateErrorObject(Json, FOwnMailbox, Message));
  finally
    Json.Free;
  end;
end;

procedure TGraphErrorsTests.GraphApiExceptionIsTranslatedByStatus;
begin
  const Error = EGraphApiException.Create('HTTP 404 fetching raw content');
  try
    const Message = FTranslator.Translate(Error, FOwnMailbox);

    Assert.Contains(Message, 'item not found');
  finally
    Error.Free;
  end;
end;

procedure TGraphErrorsTests.MailboxExceptionKeepsItsOwnMessage;
begin
  const Error = EMailboxUnknown.Create('There is no mailbox "x".');
  try
    Assert.AreEqual('There is no mailbox "x".', FTranslator.Translate(Error, FOwnMailbox));
  finally
    Error.Free;
  end;
end;

procedure TGraphErrorsTests.OtherExceptionNamesOnlyTheClass;
begin
  const Error = EInvalidOpException.Create(SecretBody);
  try
    const Message = FTranslator.Translate(Error, FOwnMailbox);

    Assert.Contains(Message, 'EInvalidOpException');
    Assert.DoesNotContain(Message, SecretBody);
  finally
    Error.Free;
  end;
end;

procedure TGraphErrorsTests.OtherExceptionDoesNotBlameGraph;
begin
  const Error = EInvalidOpException.Create(SecretBody);
  try
    const Message = FTranslator.Translate(Error, FOwnMailbox);

    Assert.DoesNotContain(Message, 'Microsoft Graph');
    Assert.IsTrue(FTranslator.IsUnexpected(Error));
  finally
    Error.Free;
  end;
end;

end.
