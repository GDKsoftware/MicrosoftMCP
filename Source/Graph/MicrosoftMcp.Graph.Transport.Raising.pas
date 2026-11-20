unit MicrosoftMcp.Graph.Transport.Raising;

interface

uses
  MSGraph.Graph.Http.Types,
  MSGraph.Graph.Http.Interfaces;

type
  // TGraphHttpClient turns an HTTP error into a JSON object {"error": "..."} that the higher-level clients of
  // Microsoft365-4D sometimes read as an empty result. This transport raises EGraphHttpError before the client sees the
  // response, so no tool can miss a failure.
  //
  // HTTP 413 passes through: TAttachmentUploader answers it by switching to an upload session.
  TRaisingGraphTransport = class(TInterfacedObject, IGraphHttpTransport)
  private
    FInnerTransport: IGraphHttpTransport;

    class function ErrorCodeOf(const Response: TGraphHttpResponse): string; static;
    class function RetryAfterOf(const Response: TGraphHttpResponse): Integer; static;

    function Checked(const Response: TGraphHttpResponse): TGraphHttpResponse;

  public
    constructor Create(const Transport: IGraphHttpTransport);

    function Execute(const Request: TGraphHttpRequest): TGraphHttpResponse;
    function ExecuteBinary(const Request: TGraphHttpRequest): TGraphHttpResponse;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  MicrosoftMcp.Graph.Exceptions;

const
  StatusRequestEntityTooLarge = 413;
  ErrorMember = 'error';
  CodeMember = 'code';
  RetryAfterHeader = 'Retry-After';
  NoRetryAfter = 0;

{ TRaisingGraphTransport }

class function TRaisingGraphTransport.ErrorCodeOf(const Response: TGraphHttpResponse): string;
begin
  Result := '';

  const Parsed = TJSONObject.ParseJSONValue(Response.Content);
  try
    const IsObject = (Parsed is TJSONObject);
    if not IsObject then
      Exit;

    var ErrorObject: TJSONObject := nil;
    const HasErrorObject = TJSONObject(Parsed).TryGetValue<TJSONObject>(ErrorMember, ErrorObject);
    if HasErrorObject then
      ErrorObject.TryGetValue<string>(CodeMember, Result);
  finally
    Parsed.Free;
  end;
end;

class function TRaisingGraphTransport.RetryAfterOf(const Response: TGraphHttpResponse): Integer;
begin
  // Retry-After can also be an HTTP date; the wait is then unknown.
  const HeaderValue = Response.HeaderValue(RetryAfterHeader).Trim;
  Result := StrToIntDef(HeaderValue, NoRetryAfter);
end;

constructor TRaisingGraphTransport.Create(const Transport: IGraphHttpTransport);
begin
  inherited Create;

  FInnerTransport := Transport;
end;

function TRaisingGraphTransport.Execute(const Request: TGraphHttpRequest): TGraphHttpResponse;
begin
  Result := Checked(FInnerTransport.Execute(Request));
end;

function TRaisingGraphTransport.ExecuteBinary(const Request: TGraphHttpRequest): TGraphHttpResponse;
begin
  Result := Checked(FInnerTransport.ExecuteBinary(Request));
end;

function TRaisingGraphTransport.Checked(const Response: TGraphHttpResponse): TGraphHttpResponse;
begin
  const PassesThrough = (Response.IsSuccess or (Response.StatusCode = StatusRequestEntityTooLarge));
  if not PassesThrough then
    raise EGraphHttpError.Create(Response.StatusCode, ErrorCodeOf(Response), RetryAfterOf(Response));

  Result := Response;
end;

end.
