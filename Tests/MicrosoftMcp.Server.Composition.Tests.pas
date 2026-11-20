unit MicrosoftMcp.Server.Composition.Tests;

interface

uses
  DUnitX.TestFramework,
  System.Net.HttpClient,
  MicrosoftMcp.Server.Settings,
  MicrosoftMcp.Server.Composition;

type
  [TestFixture]
  TServerCompositionTests = class
  private
    FComposition: TServerComposition;
    FHttp: THTTPClient;

    function LocalUrl(const Path: string): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure RequestWithoutTokenIsRefusedWithResourceMetadata;

    [Test]
    procedure ResourceMetadataNamesTheIssuer;

    [Test]
    procedure StopClosesTheEndpoint;

    [Test]
    procedure RequestBodyLimitFitsTheLargestUpload;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MicrosoftMcp.Tools.Files.Support;

const
  ResourceUri = 'https://mcp.example.test/mcp';
  Issuer = 'https://auth.example.test';
  MetadataPath = '/.well-known/oauth-protected-resource/mcp';
  McpPath = '/mcp';
  StatusUnauthorized = 401;
  StatusOk = 200;

{ TServerCompositionTests }

procedure TServerCompositionTests.Setup;
begin
  var Settings := Default(TServerSettings);
  Settings.ResourceUri     := ResourceUri;
  Settings.AuthIssuer      := Issuer;
  Settings.AuthInternalUrl := 'http://127.0.0.1:1';
  Settings.ServiceId       := 'microsoftmcp';
  Settings.ServiceSecret   := 'test-secret';
  Settings.Port            := 0;
  Settings.Store           := TServerStoreKind.Memory;

  FComposition := TServerComposition.Create(Settings);
  FComposition.Start;

  FHttp := THTTPClient.Create;
end;

procedure TServerCompositionTests.TearDown;
begin
  FHttp.Free;
  FComposition.Free;
end;

function TServerCompositionTests.LocalUrl(const Path: string): string;
begin
  Result := Format('http://127.0.0.1:%d%s', [FComposition.BoundPort, Path]);
end;

procedure TServerCompositionTests.RequestWithoutTokenIsRefusedWithResourceMetadata;
begin
  const Body = TStringStream.Create('{"jsonrpc":"2.0","id":1,"method":"ping"}', TEncoding.UTF8);
  try
    const Response = FHttp.Post(LocalUrl(McpPath), Body);

    const Challenge = Response.HeaderValue['WWW-Authenticate'];
    Assert.AreEqual(StatusUnauthorized, Response.StatusCode);
    Assert.IsTrue(Challenge.Contains('resource_metadata='), 'The challenge points to the resource metadata');
    Assert.IsTrue(Challenge.Contains(MetadataPath), 'The metadata URL follows the resource URI');
  finally
    Body.Free;
  end;
end;

procedure TServerCompositionTests.ResourceMetadataNamesTheIssuer;
begin
  const Response = FHttp.Get(LocalUrl(MetadataPath));
  Assert.AreEqual(StatusOk, Response.StatusCode);

  const Metadata = TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    const AuthorizationServers = Metadata.Values['authorization_servers'] as TJSONArray;
    const Resource = Metadata.GetValue<string>('resource');
    const FirstAuthorizationServer = Metadata.GetValue<string>('authorization_servers[0]');

    Assert.AreEqual(1, AuthorizationServers.Count);
    Assert.AreEqual(Issuer, FirstAuthorizationServer);
    Assert.AreEqual(ResourceUri, Resource);
  finally
    Metadata.Free;
  end;
end;

procedure TServerCompositionTests.StopClosesTheEndpoint;
begin
  FComposition.Stop;

  Assert.IsFalse(FComposition.IsRunning);
end;

// onedrive_upload accepts 10 MB, which is about 13.4 MB as base64 inside the JSON-RPC request.
procedure TServerCompositionTests.RequestBodyLimitFitsTheLargestUpload;
begin
  const Base64Bytes = ((TFilesSupport.MaximumBytes + 2) div 3) * 4;

  Assert.IsTrue(FComposition.RequestBodyLimit > Base64Bytes, Format('Limit %d, base64 upload %d', [FComposition.RequestBodyLimit, Base64Bytes]));
end;

end.
