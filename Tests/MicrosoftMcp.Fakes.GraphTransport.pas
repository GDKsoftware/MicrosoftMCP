unit MicrosoftMcp.Fakes.GraphTransport;

interface

uses
  System.SysUtils,
  System.Net.URLClient,
  Spring.Collections,
  MSGraph.Graph.Http.Types,
  MSGraph.Graph.Http.Interfaces;

type
  // Records every request and answers with the next canned response (the last one repeats).
  TFakeGraphTransport = class(TInterfacedObject, IGraphHttpTransport)
  private
    FRequests: IList<TGraphHttpRequest>;
    FResponses: IList<TGraphHttpResponse>;

    function NextResponse(const Request: TGraphHttpRequest): TGraphHttpResponse;

  public
    constructor Create;

    procedure Respond(const StatusCode: Integer; const Content: string); overload;
    procedure Respond(const StatusCode: Integer; const Content: string; const Headers: TArray<TNetHeader>); overload;

    function RequestCount: Integer;
    function LastRequest: TGraphHttpRequest;
    function RequestAt(const Index: Integer): TGraphHttpRequest;

    function Execute(const Request: TGraphHttpRequest): TGraphHttpResponse;
    function ExecuteBinary(const Request: TGraphHttpRequest): TGraphHttpResponse;
  end;

implementation

{ TFakeGraphTransport }

constructor TFakeGraphTransport.Create;
begin
  inherited Create;

  FRequests := TCollections.CreateList<TGraphHttpRequest>;
  FResponses := TCollections.CreateList<TGraphHttpResponse>;
end;

procedure TFakeGraphTransport.Respond(const StatusCode: Integer; const Content: string);
begin
  Respond(StatusCode, Content, nil);
end;

procedure TFakeGraphTransport.Respond(const StatusCode: Integer; const Content: string; const Headers: TArray<TNetHeader>);
begin
  var Response := Default(TGraphHttpResponse);
  Response.StatusCode := StatusCode;
  Response.Content := Content;
  Response.Headers := Headers;

  FResponses.Add(Response);
end;

function TFakeGraphTransport.RequestCount: Integer;
begin
  Result := FRequests.Count;
end;

function TFakeGraphTransport.LastRequest: TGraphHttpRequest;
begin
  Result := FRequests.Last;
end;

function TFakeGraphTransport.RequestAt(const Index: Integer): TGraphHttpRequest;
begin
  Result := FRequests[Index];
end;

function TFakeGraphTransport.Execute(const Request: TGraphHttpRequest): TGraphHttpResponse;
begin
  Result := NextResponse(Request);
end;

function TFakeGraphTransport.ExecuteBinary(const Request: TGraphHttpRequest): TGraphHttpResponse;
begin
  Result := NextResponse(Request);
end;

function TFakeGraphTransport.NextResponse(const Request: TGraphHttpRequest): TGraphHttpResponse;
begin
  FRequests.Add(Request);

  if FResponses.Count = 0 then
    raise EAbort.CreateFmt('Fake Graph transport: no response queued for %s %s', [Request.Method, Request.Url]);

  const Index = FRequests.Count - 1;
  if Index < FResponses.Count then
    Result := FResponses[Index]
  else
    Result := FResponses.Last;
end;

end.
