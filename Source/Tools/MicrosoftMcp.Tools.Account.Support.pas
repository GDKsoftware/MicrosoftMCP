unit MicrosoftMcp.Tools.Account.Support;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

type
  // For the tools whose data belongs to the account itself (people, SharePoint, OneDrive) and not to a mailbox: for those
  // tools the mailbox only selects the account. A shared mailbox has no such data of its own, so the account behind it is used.
  TAccountSupport = class
  public
    // Points the client at /me, also for a shared mailbox.
    class procedure UseOwnAccount(const Graph: TGraphHttpClient); static;

    // Says that the account behind a shared mailbox was used; empty for an own mailbox.
    class function Note(const Mailbox: TResolvedMailbox): string; static;
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Types;

resourcestring
  SharedMailboxNote = 'Mailbox "%s" is a shared mailbox. This tool does not work on the shared mailbox itself: it used the account behind it (%s).';

{ TAccountSupport }

class procedure TAccountSupport.UseOwnAccount(const Graph: TGraphHttpClient);
begin
  Graph.MailboxAddress := '';
end;

class function TAccountSupport.Note(const Mailbox: TResolvedMailbox): string;
begin
  Result := '';

  const IsShared = (Mailbox.Mailbox.Kind = TMailboxKind.Shared);
  if IsShared then
    Result := Format(SharedMailboxNote, [Mailbox.Mailbox.Slug, Mailbox.Account.UserName]);
end;

end.
