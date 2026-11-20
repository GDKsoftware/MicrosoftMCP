unit MicrosoftMcp.Graph.Errors;

interface

uses
  System.SysUtils,
  System.JSON,
  MSGraph.Graph.Http.Types,
  MicrosoftMcp.Mailbox.Types;

type
  // Turns the ways Microsoft365-4D reports a failure into one English message for Claude.
  // The message never contains tokens or the text Graph returned, because that can hold mail content.
  //
  // Clients from TGraphClientFactory raise EGraphHttpError, which Translate handles. A bare TGraphHttpClient does not
  // raise for an HTTP error: Get, Post, Patch and Delete return a JSON object {"error": "Microsoft Graph API error (HTTP 403): ..."}
  // and PostRaw returns the response, hence the two other entry points.
  TGraphErrorTranslator = class
  private
    FAccountPageUrl: string;

    function DescribeStatus(const StatusCode: Integer; const RetryAfterSeconds: Integer; const Mailbox: TMailbox): string;
    function DescribeAccessDenied(const Mailbox: TMailbox): string;
    function DescribeThrottled(const RetryAfterSeconds: Integer): string;
    function ParseStatusCode(const ErrorText: string): Integer;
    function ParseRetryAfter(const Response: TGraphHttpResponse): Integer;

  public
    constructor Create(const AccountPageUrl: string);

    function Translate(const E: Exception; const Mailbox: TMailbox): string;

    // The result of a Get, Post, Patch or Delete of TGraphHttpClient that has an 'error' member; False when it has none.
    function TryTranslateErrorObject(const Json: TJSONObject; const Mailbox: TMailbox; out Message: string): Boolean;

    function TranslateResponse(const Response: TGraphHttpResponse; const Mailbox: TMailbox): string;
  end;

implementation

uses
  System.Net.URLClient,
  MSGraph.OAuth2.Types,
  MSGraph.Graph.Drive.Exceptions,
  MicrosoftMcp.Mailbox.Exceptions,
  MicrosoftMcp.Graph.Exceptions;

const
  ErrorMember = 'error';
  RetryAfterHeader = 'Retry-After';
  StatusMarker = '(HTTP ';
  StatusMarkerAlternative = 'HTTP ';
  StatusUnknown = 0;
  NoRetryAfter = 0;
  StatusUnauthorized = 401;
  StatusForbidden = 403;
  StatusNotFound = 404;
  StatusConflict = 409;
  StatusTooManyRequests = 429;
  StatusServerError = 500;

resourcestring
  AccessDeniedSharedFormat = 'Microsoft refused access to the shared mailbox "%s" (HTTP 403). The user needs FullAccess on this mailbox in Exchange, ' +
                             'and must give consent again for the .Shared scopes via the account page: %s';
  AccessDeniedOwnFormat = 'Microsoft refused access to mailbox "%s" (HTTP 403). The account has not given the permission that this action needs; ' +
                          'ask the user to give consent again on the account page: %s';
  UnauthorizedFormat = 'Microsoft rejected the access token of mailbox "%s" (HTTP 401). Ask the user to reconnect the account on the account page: %s';
  NotFoundMessage = 'Microsoft Graph: item not found (HTTP 404). Check the id; the item may have been moved or deleted.';
  ConflictMessage = 'Microsoft Graph refused the change because of a conflict (HTTP 409): an item with that name already exists or the item is locked.';
  ThrottledMessage = 'Microsoft Graph throttled the request (HTTP 429); retry after %d s.';
  ThrottledUnknownMessage = 'Microsoft Graph throttled the request (HTTP 429); retry later.';
  ServerErrorFormat = 'Microsoft Graph is temporarily unavailable (HTTP %d); try again later.';
  OtherStatusFormat = 'Microsoft Graph returned an error (HTTP %d).';
  UnknownFailure = 'The request to Microsoft Graph failed; the cause is not known. Try again later.';
  ExceptionFailureFormat = 'The request to Microsoft Graph failed (%s). Try again later.';

{ TGraphErrorTranslator }

constructor TGraphErrorTranslator.Create(const AccountPageUrl: string);
begin
  inherited Create;

  FAccountPageUrl := AccountPageUrl;
end;

function TGraphErrorTranslator.Translate(const E: Exception; const Mailbox: TMailbox): string;
begin
  if E is EMailboxError then
    Exit(E.Message);

  if E is EGraphHttpError then
  begin
    const HttpError = EGraphHttpError(E);
    Exit(DescribeStatus(HttpError.StatusCode, HttpError.RetryAfterSeconds, Mailbox));
  end;

  if E is EGraphDriveValidationError then
    Exit(E.Message);

  if E is EGraphDriveError then
  begin
    const DriveStatus = EGraphDriveError(E).StatusCode;
    if DriveStatus <> StatusUnknown then
      Exit(DescribeStatus(DriveStatus, NoRetryAfter, Mailbox));

    Exit(Format(ExceptionFailureFormat, [E.ClassName]));
  end;

  if E is EGraphApiException then
  begin
    const StatusCode = ParseStatusCode(E.Message);
    if StatusCode = StatusUnknown then
      Exit(Format(ExceptionFailureFormat, [E.ClassName]));

    Exit(DescribeStatus(StatusCode, NoRetryAfter, Mailbox));
  end;

  Result := Format(ExceptionFailureFormat, [E.ClassName]);
end;

function TGraphErrorTranslator.TryTranslateErrorObject(const Json: TJSONObject; const Mailbox: TMailbox; out Message: string): Boolean;
begin
  Message := '';

  var ErrorValue: TJSONValue := nil;
  const HasError = Assigned(Json) and Json.TryGetValue<TJSONValue>(ErrorMember, ErrorValue);
  if not HasError then
    Exit(False);

  const StatusCode = ParseStatusCode(ErrorValue.Value);
  if StatusCode = StatusUnknown then
    Message := UnknownFailure
  else
    Message := DescribeStatus(StatusCode, NoRetryAfter, Mailbox);

  Result := True;
end;

function TGraphErrorTranslator.TranslateResponse(const Response: TGraphHttpResponse; const Mailbox: TMailbox): string;
begin
  Result := DescribeStatus(Response.StatusCode, ParseRetryAfter(Response), Mailbox);
end;

function TGraphErrorTranslator.DescribeStatus(const StatusCode: Integer; const RetryAfterSeconds: Integer; const Mailbox: TMailbox): string;
begin
  case StatusCode of
    StatusUnauthorized    : Result := Format(UnauthorizedFormat, [Mailbox.Slug, FAccountPageUrl]);
    StatusForbidden       : Result := DescribeAccessDenied(Mailbox);
    StatusNotFound        : Result := NotFoundMessage;
    StatusConflict        : Result := ConflictMessage;
    StatusTooManyRequests : Result := DescribeThrottled(RetryAfterSeconds);
  else
    if StatusCode >= StatusServerError then
      Result := Format(ServerErrorFormat, [StatusCode])
    else
      Result := Format(OtherStatusFormat, [StatusCode]);
  end;
end;

function TGraphErrorTranslator.DescribeAccessDenied(const Mailbox: TMailbox): string;
begin
  if Mailbox.Kind = TMailboxKind.Shared then
    Result := Format(AccessDeniedSharedFormat, [Mailbox.Slug, FAccountPageUrl])
  else
    Result := Format(AccessDeniedOwnFormat, [Mailbox.Slug, FAccountPageUrl]);
end;

function TGraphErrorTranslator.DescribeThrottled(const RetryAfterSeconds: Integer): string;
begin
  const IsRetryAfterKnown = (RetryAfterSeconds > NoRetryAfter);
  if IsRetryAfterKnown then
    Result := Format(ThrottledMessage, [RetryAfterSeconds])
  else
    Result := ThrottledUnknownMessage;
end;

function TGraphErrorTranslator.ParseStatusCode(const ErrorText: string): Integer;
begin
  var MarkerLength := StatusMarker.Length;
  var MarkerPosition := ErrorText.IndexOf(StatusMarker);
  if MarkerPosition < 0 then
  begin
    MarkerLength := StatusMarkerAlternative.Length;
    MarkerPosition := ErrorText.IndexOf(StatusMarkerAlternative);
  end;

  if MarkerPosition < 0 then
    Exit(StatusUnknown);

  var Digits := '';
  for var Position := MarkerPosition + MarkerLength to ErrorText.Length - 1 do
  begin
    const IsDigit = CharInSet(ErrorText.Chars[Position], ['0'..'9']);
    if not IsDigit then
      Break;

    Digits := Digits + ErrorText.Chars[Position];
  end;

  Result := StrToIntDef(Digits, StatusUnknown);
end;

function TGraphErrorTranslator.ParseRetryAfter(const Response: TGraphHttpResponse): Integer;
begin
  // Retry-After can also be an HTTP date; then the wait is unknown and the message says "retry later".
  Result := StrToIntDef(Response.HeaderValue(RetryAfterHeader).Trim, NoRetryAfter);
end;

end.
