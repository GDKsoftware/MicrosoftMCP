unit MicrosoftMcp.Tools.Services.Interfaces;

interface

uses
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Mailbox.Service.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces,
  MicrosoftMcp.Graph.Errors,
  MicrosoftMcp.Confirm.Interfaces;

type
  // Everything a tool needs, handed to each tool by the factory closure of its registration.
  IToolServices = interface
    ['{1F8C5D3A-7B42-4E96-A0C1-6D2E9B4F7A58}']
    function Resolver: IMailboxResolver;
    function GraphClients: IGraphClientFactory;
    function Confirmations: IConfirmations;
    function Mailboxes: IMailboxService;
    function Accounts: IUpstreamAccounts;
    function AccountPageUrl: string;

    // Owned by the services object.
    function Errors: TGraphErrorTranslator;
  end;

implementation

end.
