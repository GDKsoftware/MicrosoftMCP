unit MicrosoftMcp.Server.Settings;

interface

type
  {$SCOPEDENUMS ON}
  TServerStoreKind = (Memory, Postgres);
  {$SCOPEDENUMS OFF}

  TEnvironmentReader = reference to function(const Name: string): string;

  // The settings of the MicrosoftMCP program, read from MICROSOFTMCP_* environment variables.
  // A missing or invalid variable raises EServerConfiguration that names the variable, never its value.
  TServerSettings = record
  private
    class function ReadRequired(const ReadVariable: TEnvironmentReader; const Name: string): string; static;
    class function ReadOptional(const ReadVariable: TEnvironmentReader; const Name, DefaultValue: string): string; static;
    class function ReadPort(const ReadVariable: TEnvironmentReader): Word; static;
    class function ReadStore(const ReadVariable: TEnvironmentReader): TServerStoreKind; static;
    class function ReadMigrationsPath(const ReadVariable: TEnvironmentReader; const ExecutableFolder: string): string; static;
    class function FindMigrationsFolder(const ExecutableFolder: string): string; static;
    class function WithoutTrailingSlash(const Url: string): string; static;

  public
    ResourceUri: string;
    AuthIssuer: string;
    AuthInternalUrl: string;
    ServiceId: string;
    ServiceSecret: string;
    Port: Word;
    Store: TServerStoreKind;
    DatabaseConnection: string;
    MigrationsPath: string;

    class function FromEnvironment: TServerSettings; static;

    // ExecutableFolder is the base of the default migrations folder.
    class function FromVariables(const ReadVariable: TEnvironmentReader; const ExecutableFolder: string): TServerSettings; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  MicrosoftMcp.Server.Exceptions;

const
  ResourceUriVariable = 'MICROSOFTMCP_RESOURCE_URI';
  AuthIssuerVariable = 'MICROSOFTMCP_AUTH_ISSUER';
  AuthInternalUrlVariable = 'MICROSOFTMCP_AUTH_INTERNAL_URL';
  ServiceIdVariable = 'MICROSOFTMCP_SERVICE_ID';
  ServiceSecretVariable = 'MICROSOFTMCP_SERVICE_SECRET';
  PortVariable = 'MICROSOFTMCP_PORT';
  StoreVariable = 'MICROSOFTMCP_STORE';
  DatabaseVariable = 'MICROSOFTMCP_DB';
  MigrationsVariable = 'MICROSOFTMCP_MIGRATIONS';

  DefaultAuthInternalUrl = 'http://127.0.0.1:8101';
  DefaultPort = 8090;
  MemoryStoreName = 'memory';
  PostgresStoreName = 'postgres';
  MigrationsFolder = 'migrations';
  MigrationsMarker = 'postgres';
  SlashChar = '/';

resourcestring
  MissingVariable = 'Missing environment variable %s';
  InvalidVariable = 'Invalid value in environment variable %s';

{ TServerSettings }

class function TServerSettings.FromEnvironment: TServerSettings;
begin
  // ParamStr(0) can be relative on Linux (./MicrosoftMcp); the folder search needs the full path.
  const ExecutablePath = TPath.GetFullPath(ParamStr(0));
  const ExecutableFolder = TPath.GetDirectoryName(ExecutablePath);

  Result := FromVariables(
    function(const Name: string): string
    begin
      Result := GetEnvironmentVariable(Name);
    end,
    ExecutableFolder);
end;

class function TServerSettings.FromVariables(const ReadVariable: TEnvironmentReader; const ExecutableFolder: string): TServerSettings;
begin
  Result := Default(TServerSettings);

  const AuthIssuer      = ReadRequired(ReadVariable, AuthIssuerVariable);
  const AuthInternalUrl = ReadOptional(ReadVariable, AuthInternalUrlVariable, DefaultAuthInternalUrl);

  Result.ResourceUri     := ReadRequired(ReadVariable, ResourceUriVariable);
  Result.AuthIssuer      := WithoutTrailingSlash(AuthIssuer);
  Result.AuthInternalUrl := WithoutTrailingSlash(AuthInternalUrl);
  Result.ServiceId       := ReadRequired(ReadVariable, ServiceIdVariable);
  Result.ServiceSecret   := ReadRequired(ReadVariable, ServiceSecretVariable);
  Result.Port            := ReadPort(ReadVariable);
  Result.Store           := ReadStore(ReadVariable);

  const UsesPostgres = (Result.Store = TServerStoreKind.Postgres);
  if UsesPostgres then
    Result.DatabaseConnection := ReadRequired(ReadVariable, DatabaseVariable);

  Result.MigrationsPath := ReadMigrationsPath(ReadVariable, ExecutableFolder);
end;

class function TServerSettings.ReadRequired(const ReadVariable: TEnvironmentReader; const Name: string): string;
begin
  Result := ReadVariable(Name).Trim;
  if Result.IsEmpty then
    raise EServerConfiguration.CreateFmt(MissingVariable, [Name]);
end;

class function TServerSettings.ReadOptional(const ReadVariable: TEnvironmentReader; const Name, DefaultValue: string): string;
begin
  Result := ReadVariable(Name).Trim;
  if Result.IsEmpty then
    Result := DefaultValue;
end;

class function TServerSettings.ReadPort(const ReadVariable: TEnvironmentReader): Word;
begin
  const Value = ReadVariable(PortVariable).Trim;
  if Value.IsEmpty then
    Exit(DefaultPort);

  var Port: Integer;
  const IsValidPort = (TryStrToInt(Value, Port) and (Port >= Low(Word)) and (Port <= High(Word)));
  if not IsValidPort then
    raise EServerConfiguration.CreateFmt(InvalidVariable, [PortVariable]);

  Result := Port;
end;

class function TServerSettings.ReadStore(const ReadVariable: TEnvironmentReader): TServerStoreKind;
begin
  const Value = ReadOptional(ReadVariable, StoreVariable, MemoryStoreName).ToLower;

  const IsMemory = (Value = MemoryStoreName);
  const IsPostgres = (Value = PostgresStoreName);
  if IsMemory then
  begin
    Result := TServerStoreKind.Memory;
  end
  else if IsPostgres then
  begin
    Result := TServerStoreKind.Postgres;
  end
  else
  begin
    raise EServerConfiguration.CreateFmt(InvalidVariable, [StoreVariable]);
  end;
end;

class function TServerSettings.ReadMigrationsPath(const ReadVariable: TEnvironmentReader; const ExecutableFolder: string): string;
begin
  Result := ReadVariable(MigrationsVariable).Trim;
  if Result.IsEmpty then
    Result := FindMigrationsFolder(ExecutableFolder);
end;

class function TServerSettings.FindMigrationsFolder(const ExecutableFolder: string): string;
begin
  // Next to the executable in a deployment. A program started from the build output (bin/<platform>/<config>)
  // finds the folder of the repository higher up instead.
  var Folder := ExecutableFolder;
  while not Folder.IsEmpty do
  begin
    const Candidate = TPath.Combine(Folder, MigrationsFolder);
    const MarkerPath = TPath.Combine(Candidate, MigrationsMarker);
    const HasMarker = TDirectory.Exists(MarkerPath);
    if HasMarker then
      Exit(Candidate);

    const Parent = TPath.GetDirectoryName(Folder);
    const IsRoot = (Parent = Folder);
    if IsRoot then
      Break;

    Folder := Parent;
  end;

  Result := TPath.Combine(ExecutableFolder, MigrationsFolder);
end;

class function TServerSettings.WithoutTrailingSlash(const Url: string): string;
begin
  Result := Url.TrimRight([SlashChar]);
end;

end.
