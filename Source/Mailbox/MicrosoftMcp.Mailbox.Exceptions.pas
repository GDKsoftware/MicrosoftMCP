unit MicrosoftMcp.Mailbox.Exceptions;

interface

uses
  System.SysUtils;

type
  EMailboxError = class(Exception);
  EMailboxSlugTaken = class(EMailboxError);
  EMailboxNotFound = class(EMailboxError);

  // The messages of the exceptions below are written for Claude: they say what to do next and never carry tokens or mail content.
  EMailboxUnknown = class(EMailboxError);
  EMailboxAccountUnlinked = class(EMailboxError);
  EMailboxNeedsReconnect = class(EMailboxError);
  EMailboxAccessForbidden = class(EMailboxError);
  EMailboxNotAccessible = class(EMailboxError);
  EMailboxAccountUnknown = class(EMailboxError);
  EMailboxInvalidInput = class(EMailboxError);

implementation

end.
