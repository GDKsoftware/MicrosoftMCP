unit MicrosoftMcp.Mailbox.Access.Interfaces;

interface

uses
  MicrosoftMcp.Mailbox.Types;

type
  TMailboxAccessResult = record
    IsAccessible: Boolean;
    // Empty when accessible; otherwise the reason, written for Claude.
    Message: string;
  end;

  IMailboxAccess = interface
    ['{8C2E4A71-5F39-4D06-B1A8-3E7D9C5B2F14}']
    // Reads the inbox of the mailbox with the access token of its account.
    function Check(const Mailbox: TMailbox; const AccessToken: string): TMailboxAccessResult;
  end;

implementation

end.
