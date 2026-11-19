unit MicrosoftMcp.Tools.Services;

interface

uses
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Mailbox.Service.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces,
  MicrosoftMcp.Graph.Errors,
  MicrosoftMcp.Confirm.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  // Wires resolver, mailbox service and access check on one repository, account source and Graph client factory.
  TToolServices = class(TInterfacedObject, IToolServices)
  private
    FErrors: TGraphErrorTranslator;
    FResolver: IMailboxResolver;
    FGraphClients: IGraphClientFactory;
    FConfirmations: IConfirmations;
    FMailboxes: IMailboxService;
    FAccounts: IUpstreamAccounts;
    FAccountPageUrl: string;

  public
    constructor Create(const MailboxRepository: IMailboxRepository;
                       const Accounts: IUpstreamAccounts;
                       const GraphClients: IGraphClientFactory;
                       const Confirmations: IConfirmations;
                       const AccountPageUrl: string);
    destructor Destroy; override;

    function Resolver: IMailboxResolver;
    function GraphClients: IGraphClientFactory;
    function Confirmations: IConfirmations;
    function Mailboxes: IMailboxService;
    function Accounts: IUpstreamAccounts;
    function AccountPageUrl: string;
    function Errors: TGraphErrorTranslator;
  end;

implementation

uses
  MicrosoftMcp.Mailbox.Resolver,
  MicrosoftMcp.Mailbox.Access.Interfaces,
  MicrosoftMcp.Mailbox.Access,
  MicrosoftMcp.Mailbox.Service;

{ TToolServices }

constructor TToolServices.Create(const MailboxRepository: IMailboxRepository;
                                 const Accounts: IUpstreamAccounts;
                                 const GraphClients: IGraphClientFactory;
                                 const Confirmations: IConfirmations;
                                 const AccountPageUrl: string);
begin
  inherited Create;

  FErrors         := TGraphErrorTranslator.Create(AccountPageUrl);
  FResolver       := TMailboxResolver.Create(MailboxRepository, Accounts, AccountPageUrl);
  FGraphClients   := GraphClients;
  FConfirmations  := Confirmations;
  FAccounts       := Accounts;
  FAccountPageUrl := AccountPageUrl;

  const Access: IMailboxAccess = TMailboxAccess.Create(GraphClients, FErrors);
  FMailboxes := TMailboxService.Create(MailboxRepository, Accounts, Access, AccountPageUrl);
end;

destructor TToolServices.Destroy;
begin
  // The mailbox service holds the access check, which uses FErrors.
  FMailboxes := nil;
  FErrors.Free;

  inherited Destroy;
end;

function TToolServices.Resolver: IMailboxResolver;
begin
  Result := FResolver;
end;

function TToolServices.GraphClients: IGraphClientFactory;
begin
  Result := FGraphClients;
end;

function TToolServices.Confirmations: IConfirmations;
begin
  Result := FConfirmations;
end;

function TToolServices.Mailboxes: IMailboxService;
begin
  Result := FMailboxes;
end;

function TToolServices.Accounts: IUpstreamAccounts;
begin
  Result := FAccounts;
end;

function TToolServices.AccountPageUrl: string;
begin
  Result := FAccountPageUrl;
end;

function TToolServices.Errors: TGraphErrorTranslator;
begin
  Result := FErrors;
end;

end.
