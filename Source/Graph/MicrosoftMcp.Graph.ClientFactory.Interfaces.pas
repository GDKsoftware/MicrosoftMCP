unit MicrosoftMcp.Graph.ClientFactory.Interfaces;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

type
  IGraphClientFactory = interface
    ['{4E8A2C6D-1B73-4F95-A0D8-5C2E7B9F3A16}']
    // The caller owns the client. MailboxAddress is only set for a shared mailbox, so an own mailbox uses /me.
    function Create(const Resolved: TResolvedMailbox): TGraphHttpClient;
  end;

implementation

end.
