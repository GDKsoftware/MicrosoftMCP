unit MicrosoftMcp.Graph.ClientFactory.Interfaces;

interface

uses
  MSGraph.Graph.Http,
  MSGraph.Graph.Drive.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

type
  IGraphClientFactory = interface
    ['{4E8A2C6D-1B73-4F95-A0D8-5C2E7B9F3A16}']
    // The caller owns the client. MailboxAddress is only set for a shared mailbox, so an own mailbox uses /me.
    function Create(const Resolved: TResolvedMailbox): TGraphHttpClient;

    // The OneDrive (/me/drive) of the account behind the mailbox; a shared mailbox has no drive of its own here.
    function CreateDrive(const Resolved: TResolvedMailbox): IGraphDriveClient;
  end;

implementation

end.
