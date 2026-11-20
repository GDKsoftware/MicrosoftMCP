unit MicrosoftMcp.Server.Composition;

interface

uses
  MCPServer.Host,
  MCPAuth.Store.FireDAC.Interfaces,
  MCPAuth.Store.FireDAC.PgDriver,
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Confirm.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Server.Settings,
  MicrosoftMcp.Server.Maintenance;

type
  // The composition root of the MicrosoftMCP program: builds the database, the linked accounts of the central auth
  // server, the tool registrations and the MCP endpoint, and owns them all. The endpoint listens on 127.0.0.1 only;
  // a reverse proxy publishes it under the resource URI.
  TServerComposition = class
  private
    FSettings: TServerSettings;
    FPgDriver: TFireDACPgDriver;
    FConnectionFactory: IFireDACConnectionFactory;
    FMailboxes: IMailboxRepository;
    FAccounts: IUpstreamAccounts;
    FToolServices: IToolServices;
    FConfirmations: IConfirmations;
    FHost: TMCPServerHost;
    FMaintenance: TServerMaintenance;
    FIsRunning: Boolean;

    class function WithDatabaseTimeouts(const ConnectionString: string): string; static;
    class function WithUtf8(const ConnectionString: string): string; static;

    procedure BuildDatabase;
    procedure BuildPostgresDatabase;
    procedure BuildMailboxStore;
    procedure BuildAccounts;
    procedure BuildToolServices;
    procedure RegisterTools;
    procedure RegisterMailboxTools;
    procedure RegisterMailTools;
    procedure RegisterCalendarTools;
    procedure RegisterContactsTools;
    procedure RegisterFilesTools;
    function RequestStateKey: string;
    procedure BuildHost;
    procedure LogStarted;

  public
    constructor Create(const Settings: TServerSettings);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;

    // The port the endpoint actually uses; it differs from the settings when those were 0.
    function BoundPort: Word;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  MCPServer.Logger,
  MCPServer.Tool.Base,
  MCPServer.Registration,
  MCPAuth.Clock,
  MCPAuth.Secret.Interfaces,
  MCPAuth.Secret.Token,
  MCPAuth.Client,
  MCPAuth.Client.UpstreamAccounts,
  MCPAuth.Store.FireDAC.ConnectionFactory,
  MCPAuth.Store.FireDAC.Migrations,
  MicrosoftMcp.Mailbox.Store.Memory,
  MicrosoftMcp.Mailbox.Store.FireDAC,
  MicrosoftMcp.Graph.ClientFactory,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Tools.Services,
  MicrosoftMcp.Tools.Mailbox.ListAccounts,
  MicrosoftMcp.Tools.Mailbox.List,
  MicrosoftMcp.Tools.Mailbox.Add,
  MicrosoftMcp.Tools.Mailbox.Rename,
  MicrosoftMcp.Tools.Mailbox.Remove,
  MicrosoftMcp.Tools.Mail.Search,
  MicrosoftMcp.Tools.Mail.List,
  MicrosoftMcp.Tools.Mail.Read,
  MicrosoftMcp.Tools.Mail.ListFolders,
  MicrosoftMcp.Tools.Mail.ListAttachments,
  MicrosoftMcp.Tools.Mail.GetAttachment,
  MicrosoftMcp.Tools.Mail.CreateDraft,
  MicrosoftMcp.Tools.Mail.UpdateDraft,
  MicrosoftMcp.Tools.Mail.CreateReplyDraft,
  MicrosoftMcp.Tools.Mail.CreateForwardDraft,
  MicrosoftMcp.Tools.Mail.DeleteDraft,
  MicrosoftMcp.Tools.Mail.SendDraft,
  MicrosoftMcp.Tools.Mail.Send,
  MicrosoftMcp.Tools.Mail.Forward,
  MicrosoftMcp.Tools.Mail.Move,
  MicrosoftMcp.Tools.Mail.MarkRead,
  MicrosoftMcp.Tools.Mail.Delete,
  MicrosoftMcp.Tools.Mail.GetSignature,
  MicrosoftMcp.Tools.Calendar.List,
  MicrosoftMcp.Tools.Calendar.Search,
  MicrosoftMcp.Tools.Calendar.Get,
  MicrosoftMcp.Tools.Calendar.Create,
  MicrosoftMcp.Tools.Calendar.Update,
  MicrosoftMcp.Tools.Calendar.Delete,
  MicrosoftMcp.Tools.Calendar.Respond,
  MicrosoftMcp.Tools.Calendar.ProposeTime,
  MicrosoftMcp.Tools.Calendar.Availability,
  MicrosoftMcp.Tools.Contacts.Search,
  MicrosoftMcp.Tools.Contacts.Get,
  MicrosoftMcp.Tools.Contacts.Create,
  MicrosoftMcp.Tools.Contacts.Update,
  MicrosoftMcp.Tools.Contacts.Delete,
  MicrosoftMcp.Tools.People.Search,
  MicrosoftMcp.Tools.People.Relevant,
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
  MicrosoftMcp.Tools.OneDrive.Delete;

const
  LoopbackAddress = '127.0.0.1';
  McpEndpoint = '/mcp';
  ServerName = 'microsoftmcp';
  PostgresDialect = 'postgres';
  SchemaVersionTable = 'microsoftmcp_schema_version';
  PgAdvancedParameter = 'PGAdvanced=';
  // Without these a query that waits on a lock or a stuck connection would hold a request thread forever.
  DatabaseTimeouts = 'PGAdvanced=options=-c statement_timeout=30000 -c lock_timeout=10000';
  ParamSeparator = ';';
  CharacterSetParameter = 'CharacterSet=';
  Utf8CharacterSet = 'CharacterSet=UTF8';

resourcestring
  StartedFormat = 'MicrosoftMCP started: resource %s on %s:%d, tokens from %s, store %s';
  MemoryStoreName = 'memory';
  PostgresStoreName = 'postgres';

{ TServerComposition }

class function TServerComposition.WithDatabaseTimeouts(const ConnectionString: string): string;
begin
  const HasOwnAdvancedOptions = ContainsText(ConnectionString, PgAdvancedParameter);
  if HasOwnAdvancedOptions then
    Exit(ConnectionString);

  const TrimmedConnectionString = ConnectionString.TrimRight([ParamSeparator]);
  Result := Format('%s%s%s', [TrimmedConnectionString, ParamSeparator, DatabaseTimeouts]);
end;

class function TServerComposition.WithUtf8(const ConnectionString: string): string;
begin
  const HasOwnCharacterSet = ContainsText(ConnectionString, CharacterSetParameter);
  if HasOwnCharacterSet then
    Exit(ConnectionString);

  const TrimmedConnectionString = ConnectionString.TrimRight([ParamSeparator]);
  Result := Format('%s%s%s', [TrimmedConnectionString, ParamSeparator, Utf8CharacterSet]);
end;

constructor TServerComposition.Create(const Settings: TServerSettings);
begin
  inherited Create;

  FSettings := Settings;
end;

destructor TServerComposition.Destroy;
begin
  Stop;

  FMaintenance.Free;
  FHost.Free;
  FToolServices := nil;
  FConfirmations := nil;
  FAccounts := nil;
  FMailboxes := nil;
  FConnectionFactory := nil;
  FPgDriver.Free;

  inherited Destroy;
end;

procedure TServerComposition.Start;
begin
  if FIsRunning then
    Exit;

  if not Assigned(FHost) then
  begin
    BuildDatabase;
    BuildMailboxStore;
    BuildAccounts;
    BuildToolServices;
    RegisterTools;
    BuildHost;
    FMaintenance := TServerMaintenance.Create(FConfirmations);
  end;

  FHost.StartHttp;
  FMaintenance.Start;
  FIsRunning := True;
  LogStarted;
end;

procedure TServerComposition.BuildDatabase;
begin
  const UsesPostgres = (FSettings.Store = TServerStoreKind.Postgres);
  if UsesPostgres then
    BuildPostgresDatabase;
end;

procedure TServerComposition.BuildPostgresDatabase;
begin
  FPgDriver := TFireDACPgDriver.Create;

  const ConnectionString = WithUtf8(WithDatabaseTimeouts(FSettings.DatabaseConnection));
  FConnectionFactory := TFireDACConnectionFactory.Create(ConnectionString);
  TFireDACMigrations.Apply(FConnectionFactory, PostgresDialect, FSettings.MigrationsPath, SchemaVersionTable);
end;

procedure TServerComposition.BuildMailboxStore;
begin
  const UsesPostgres = (FSettings.Store = TServerStoreKind.Postgres);
  if UsesPostgres then
    FMailboxes := TMailboxStoreFireDAC.Create(FConnectionFactory)
  else
    FMailboxes := TMailboxStoreMemory.Create;
end;

procedure TServerComposition.BuildAccounts;
begin
  FAccounts := TRemoteUpstreamAccounts.Create(FSettings.AuthInternalUrl, FSettings.ServiceId, FSettings.ServiceSecret);
end;

procedure TServerComposition.BuildToolServices;
begin
  const AccountPageUrl = TMCPAuthClient.AccountPageUrl(FSettings.AuthIssuer);
  FConfirmations := TConfirmationsMemory.Create(TTokenGenerator.Create, TSystemClock.Create);

  FToolServices := TToolServices.Create(FMailboxes, FAccounts, TGraphClientFactory.Create, FConfirmations, AccountPageUrl);
end;

procedure TServerComposition.RegisterTools;
begin
  // The host copies the tools of the global registry when it builds its managers, so every
  // TMCPRegistry.RegisterTool call belongs here, before BuildHost.
  RegisterMailboxTools;
  RegisterMailTools;
  RegisterCalendarTools;
  RegisterContactsTools;
  RegisterFilesTools;
end;

procedure TServerComposition.RegisterMailboxTools;
begin
  // The closures capture the services, never Self: the global registry outlives this composition.
  const Services = FToolServices;

  TMCPRegistry.RegisterTool(TListAccountsTool.ToolName,
    function: IMCPTool
    begin
      Result := TListAccountsTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TListMailboxesTool.ToolName,
    function: IMCPTool
    begin
      Result := TListMailboxesTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailboxAddTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailboxAddTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailboxRenameTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailboxRenameTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailboxRemoveTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailboxRemoveTool.Create(Services);
    end);
end;

procedure TServerComposition.RegisterMailTools;
begin
  const Services = FToolServices;

  TMCPRegistry.RegisterTool(TMailSearchTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailSearchTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailListTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailListTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailReadTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailReadTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailListFoldersTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailListFoldersTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailListAttachmentsTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailListAttachmentsTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailGetAttachmentTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailGetAttachmentTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailCreateDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailCreateDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailUpdateDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailUpdateDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailCreateReplyDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailCreateReplyDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailCreateForwardDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailCreateForwardDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailDeleteDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailDeleteDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailSendDraftTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailSendDraftTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailSendTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailSendTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailForwardTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailForwardTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailMoveTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailMoveTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailMarkReadTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailMarkReadTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailDeleteTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailDeleteTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TMailGetSignatureTool.ToolName,
    function: IMCPTool
    begin
      Result := TMailGetSignatureTool.Create(Services);
    end);
end;

procedure TServerComposition.RegisterCalendarTools;
begin
  const Services = FToolServices;

  TMCPRegistry.RegisterTool(TCalendarListTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarListTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarSearchTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarSearchTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarGetTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarGetTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarCreateTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarCreateTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarUpdateTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarUpdateTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarDeleteTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarDeleteTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarRespondTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarRespondTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarProposeTimeTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarProposeTimeTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TCalendarAvailabilityTool.ToolName,
    function: IMCPTool
    begin
      Result := TCalendarAvailabilityTool.Create(Services);
    end);
end;

procedure TServerComposition.RegisterContactsTools;
begin
  const Services = FToolServices;

  TMCPRegistry.RegisterTool(TContactsSearchTool.ToolName,
    function: IMCPTool
    begin
      Result := TContactsSearchTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TContactsGetTool.ToolName,
    function: IMCPTool
    begin
      Result := TContactsGetTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TContactsCreateTool.ToolName,
    function: IMCPTool
    begin
      Result := TContactsCreateTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TContactsUpdateTool.ToolName,
    function: IMCPTool
    begin
      Result := TContactsUpdateTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TContactsDeleteTool.ToolName,
    function: IMCPTool
    begin
      Result := TContactsDeleteTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TPeopleSearchTool.ToolName,
    function: IMCPTool
    begin
      Result := TPeopleSearchTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TPeopleRelevantTool.ToolName,
    function: IMCPTool
    begin
      Result := TPeopleRelevantTool.Create(Services);
    end);
end;

procedure TServerComposition.RegisterFilesTools;
begin
  const Services = FToolServices;

  TMCPRegistry.RegisterTool(TSharePointSearchSitesTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointSearchSitesTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TSharePointListFilesTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointListFilesTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TSharePointSearchFilesTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointSearchFilesTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TSharePointReadFileTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointReadFileTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TSharePointListPagesTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointListPagesTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TSharePointReadPageTool.ToolName,
    function: IMCPTool
    begin
      Result := TSharePointReadPageTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveListTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveListTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveReadTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveReadTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveUploadTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveUploadTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveCreateFolderTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveCreateFolderTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveMoveTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveMoveTool.Create(Services);
    end);

  TMCPRegistry.RegisterTool(TOneDriveDeleteTool.ToolName,
    function: IMCPTool
    begin
      Result := TOneDriveDeleteTool.Create(Services);
    end);
end;

function TServerComposition.RequestStateKey: string;
begin
  // No tool of this server uses requestState, but the library warns about a missing key. Without a configured key
  // each process signs with its own random key, which is what the library would do and fine for a single instance.
  Result := FSettings.RequestStateKey;
  if Result.IsEmpty then
  begin
    const Tokens: ITokenGenerator = TTokenGenerator.Create;
    Result := Tokens.NewToken;
  end;
end;

procedure TServerComposition.BuildHost;
begin
  FHost := TMCPServerHost.Create;
  FHost.SeedFromGlobalRegistry := True;

  FHost.Settings.Host                 := LoopbackAddress;
  FHost.Settings.BindAddress          := LoopbackAddress;
  FHost.Settings.Port                 := FSettings.Port;
  FHost.Settings.Endpoint             := McpEndpoint;
  FHost.Settings.ServerName           := ServerName;
  FHost.Settings.AuthorizationServers := FSettings.AuthIssuer;
  FHost.Settings.ResourceUri          := FSettings.ResourceUri;
  FHost.Settings.RequestStateKey      := RequestStateKey;

  FHost.Authorizer := TMCPAuthClient.CreateAuthorizer(FSettings.ResourceUri,
                                                      FSettings.AuthInternalUrl,
                                                      FSettings.ServiceId,
                                                      FSettings.ServiceSecret);
end;

procedure TServerComposition.LogStarted;
begin
  const UsesPostgres = (FSettings.Store = TServerStoreKind.Postgres);
  const StoreName = IfThen(UsesPostgres, PostgresStoreName, MemoryStoreName);

  TLogger.Info(StartedFormat, [FSettings.ResourceUri, LoopbackAddress, BoundPort, FSettings.AuthIssuer, StoreName]);
end;

procedure TServerComposition.Stop;
begin
  if not FIsRunning then
    Exit;

  FIsRunning := False;
  FMaintenance.Stop;
  FHost.Stop;
end;

function TServerComposition.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TServerComposition.BoundPort: Word;
begin
  if Assigned(FHost) then
    Result := FHost.BoundPort
  else
    Result := FSettings.Port;
end;

end.
