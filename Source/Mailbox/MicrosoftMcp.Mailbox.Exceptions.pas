unit MicrosoftMcp.Mailbox.Exceptions;

interface

uses
  System.SysUtils;

type
  EMailboxError = class(Exception);
  EMailboxSlugTaken = class(EMailboxError);
  EMailboxNotFound = class(EMailboxError);

implementation

end.
