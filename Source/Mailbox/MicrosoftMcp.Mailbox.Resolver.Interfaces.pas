unit MicrosoftMcp.Mailbox.Resolver.Interfaces;

interface

uses
  MCPAuth.Client.UpstreamAccounts.Interfaces,
  MicrosoftMcp.Mailbox.Types;

type
  TResolvedMailbox = record
    Mailbox: TMailbox;
    Account: TRemoteAccount;
    AccessToken: string;
  end;

  IMailboxResolver = interface
    ['{B2D6F4A1-7C39-4E58-8A0D-1F3E5C7B9D24}']
    // Raises EMailboxUnknown, EMailboxAccountUnlinked, EMailboxNeedsReconnect or EMailboxAccessForbidden.
    function Resolve(const UserId, Slug: string): TResolvedMailbox;
  end;

implementation

end.
