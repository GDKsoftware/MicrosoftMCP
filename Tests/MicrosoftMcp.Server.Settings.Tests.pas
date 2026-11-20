unit MicrosoftMcp.Server.Settings.Tests;

interface

uses
  DUnitX.TestFramework,
  Spring.Collections,
  MicrosoftMcp.Server.Settings;

type
  [TestFixture]
  TServerSettingsTests = class
  private
    FVariables: IDictionary<string, string>;

    function Load: TServerSettings;
    function MessageOfFailedLoad: string;

  public
    [Setup]
    procedure Setup;

    [Test]
    procedure ReadsAllSettingsFromEnvironment;

    [Test]
    procedure UsesDefaultsForOptionalVariables;

    [Test]
    procedure MissingServiceSecretRaisesWithNameOnly;

    [Test]
    [TestCase('ResourceUri', 'MICROSOFTMCP_RESOURCE_URI')]
    [TestCase('AuthIssuer', 'MICROSOFTMCP_AUTH_ISSUER')]
    [TestCase('ServiceId', 'MICROSOFTMCP_SERVICE_ID')]
    procedure MissingRequiredVariableRaisesWithItsName(const Name: string);

    [Test]
    procedure PostgresStoreRequiresConnection;

    [Test]
    procedure InvalidPortRaisesWithoutTheValue;

    [Test]
    procedure UnknownStoreRaisesWithoutTheValue;

    [Test]
    procedure IssuerAndInternalUrlLoseTrailingSlash;

    [Test]
    procedure RequestStateKeyIsOptional;
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Server.Exceptions;

const
  ExecutableFolder = 'C:\does-not-exist\bin';
  ResourceUriVariable = 'MICROSOFTMCP_RESOURCE_URI';
  AuthIssuerVariable = 'MICROSOFTMCP_AUTH_ISSUER';
  AuthInternalUrlVariable = 'MICROSOFTMCP_AUTH_INTERNAL_URL';
  ServiceIdVariable = 'MICROSOFTMCP_SERVICE_ID';
  ServiceSecretVariable = 'MICROSOFTMCP_SERVICE_SECRET';
  PortVariable = 'MICROSOFTMCP_PORT';
  StoreVariable = 'MICROSOFTMCP_STORE';
  DatabaseVariable = 'MICROSOFTMCP_DB';
  MigrationsVariable = 'MICROSOFTMCP_MIGRATIONS';
  RequestStateKeyVariable = 'MICROSOFTMCP_REQUEST_STATE_KEY';
  ServiceSecret = 'secret-value-never-shown';

{ TServerSettingsTests }

procedure TServerSettingsTests.Setup;
begin
  FVariables := TCollections.CreateDictionary<string, string>;
  FVariables[ResourceUriVariable]   := 'https://mcp.example.test/microsoft/mcp';
  FVariables[AuthIssuerVariable]    := 'https://auth.example.test';
  FVariables[ServiceIdVariable]     := 'microsoftmcp';
  FVariables[ServiceSecretVariable] := ServiceSecret;
end;

function TServerSettingsTests.Load: TServerSettings;
begin
  Result := TServerSettings.FromVariables(
    function(const Name: string): string
    begin
      if not FVariables.TryGetValue(Name, Result) then
        Result := '';
    end,
    ExecutableFolder);
end;

function TServerSettingsTests.MessageOfFailedLoad: string;
begin
  Result := '';
  try
    Load;
  except
    on E: EServerConfiguration do
      Result := E.Message;
  end;
end;

procedure TServerSettingsTests.ReadsAllSettingsFromEnvironment;
begin
  FVariables[AuthInternalUrlVariable] := 'http://10.0.0.5:9101';
  FVariables[PortVariable]            := '9090';
  FVariables[StoreVariable]           := 'postgres';
  FVariables[DatabaseVariable]        := 'DriverID=PG;Server=db.example.test';
  FVariables[MigrationsVariable]      := '/opt/microsoftmcp/migrations';

  const Settings = Load;

  Assert.AreEqual('https://mcp.example.test/microsoft/mcp', Settings.ResourceUri);
  Assert.AreEqual('https://auth.example.test', Settings.AuthIssuer);
  Assert.AreEqual('http://10.0.0.5:9101', Settings.AuthInternalUrl);
  Assert.AreEqual('microsoftmcp', Settings.ServiceId);
  Assert.AreEqual(ServiceSecret, Settings.ServiceSecret);
  Assert.AreEqual<Word>(9090, Settings.Port);
  Assert.AreEqual<TServerStoreKind>(TServerStoreKind.Postgres, Settings.Store);
  Assert.AreEqual('DriverID=PG;Server=db.example.test', Settings.DatabaseConnection);
  Assert.AreEqual('/opt/microsoftmcp/migrations', Settings.MigrationsPath);
end;

procedure TServerSettingsTests.UsesDefaultsForOptionalVariables;
begin
  const Settings = Load;

  Assert.AreEqual('http://127.0.0.1:8101', Settings.AuthInternalUrl);
  Assert.AreEqual<Word>(8090, Settings.Port);
  Assert.AreEqual<TServerStoreKind>(TServerStoreKind.Memory, Settings.Store);
  Assert.AreEqual('', Settings.DatabaseConnection);
end;

procedure TServerSettingsTests.RequestStateKeyIsOptional;
begin
  Assert.AreEqual('', Load.RequestStateKey);

  FVariables[RequestStateKeyVariable] := ' shared-key ';

  Assert.AreEqual('shared-key', Load.RequestStateKey);
end;

procedure TServerSettingsTests.MissingServiceSecretRaisesWithNameOnly;
begin
  FVariables.Remove(ServiceSecretVariable);

  const Message = MessageOfFailedLoad;

  Assert.IsTrue(Message.Contains(ServiceSecretVariable), 'The message names the missing variable');
  Assert.IsFalse(Message.Contains('microsoftmcp'), 'The message carries no value of another variable');
end;

procedure TServerSettingsTests.MissingRequiredVariableRaisesWithItsName(const Name: string);
begin
  FVariables.Remove(Name);

  const Message = MessageOfFailedLoad;

  Assert.IsTrue(Message.Contains(Name), 'The message names the missing variable');
end;

procedure TServerSettingsTests.PostgresStoreRequiresConnection;
begin
  FVariables[StoreVariable] := 'postgres';

  const Message = MessageOfFailedLoad;

  Assert.IsTrue(Message.Contains(DatabaseVariable), 'The postgres store needs a connection string');
end;

procedure TServerSettingsTests.InvalidPortRaisesWithoutTheValue;
begin
  FVariables[PortVariable] := '70000';

  const Message = MessageOfFailedLoad;

  Assert.IsTrue(Message.Contains(PortVariable), 'The message names the variable');
  Assert.IsFalse(Message.Contains('70000'), 'The message carries no value');
end;

procedure TServerSettingsTests.UnknownStoreRaisesWithoutTheValue;
begin
  FVariables[StoreVariable] := 'sqlite';

  const Message = MessageOfFailedLoad;

  Assert.IsTrue(Message.Contains(StoreVariable), 'The message names the variable');
  Assert.IsFalse(Message.Contains('sqlite'), 'The message carries no value');
end;

procedure TServerSettingsTests.IssuerAndInternalUrlLoseTrailingSlash;
begin
  FVariables[AuthIssuerVariable]      := 'https://auth.example.test/';
  FVariables[AuthInternalUrlVariable] := 'http://127.0.0.1:8101/';

  const Settings = Load;

  Assert.AreEqual('https://auth.example.test', Settings.AuthIssuer);
  Assert.AreEqual('http://127.0.0.1:8101', Settings.AuthInternalUrl);
end;

end.
