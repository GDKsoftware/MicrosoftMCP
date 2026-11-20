unit MicrosoftMcp.Graph.Exceptions;

interface

uses
  System.SysUtils;

type
  // An HTTP status outside 2xx from Microsoft Graph. The message holds the status and Graph's error code only, never the
  // error text of Graph, because that can quote mail content.
  EGraphHttpError = class(Exception)
  private
    FStatusCode: Integer;
    FErrorCode: string;
    FRetryAfterSeconds: Integer;

  public
    constructor Create(const StatusCode: Integer; const ErrorCode: string; const RetryAfterSeconds: Integer);

    property StatusCode: Integer read FStatusCode;
    property ErrorCode: string read FErrorCode;
    // 0 when Graph sent no Retry-After in seconds.
    property RetryAfterSeconds: Integer read FRetryAfterSeconds;
  end;

implementation

resourcestring
  GraphHttpErrorFormat = 'Microsoft Graph returned HTTP %d (%s)';
  NoErrorCode = 'no error code';

{ EGraphHttpError }

constructor EGraphHttpError.Create(const StatusCode: Integer; const ErrorCode: string; const RetryAfterSeconds: Integer);
begin
  const HasErrorCode = not ErrorCode.IsEmpty;
  if HasErrorCode then
    inherited CreateFmt(GraphHttpErrorFormat, [StatusCode, ErrorCode])
  else
    inherited CreateFmt(GraphHttpErrorFormat, [StatusCode, NoErrorCode]);

  FStatusCode := StatusCode;
  FErrorCode := ErrorCode;
  FRetryAfterSeconds := RetryAfterSeconds;
end;

end.
