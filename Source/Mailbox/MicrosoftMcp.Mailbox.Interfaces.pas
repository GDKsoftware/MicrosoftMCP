unit MicrosoftMcp.Mailbox.Interfaces;

interface

uses
  Spring.Collections,
  MicrosoftMcp.Mailbox.Types;

type
  // Every operation is scoped to one user: a short name of another user never matches.
  IMailboxRepository = interface
    ['{3D5B7A19-84C2-4E60-9F1A-6B2C0D8E7F43}']
    function TryGet(const UserId, Slug: string; out Mailbox: TMailbox): Boolean;

    // Oldest first.
    function ListForUser(const UserId: string): IReadOnlyList<TMailbox>;

    // Raises EMailboxSlugTaken when the user already has a mailbox under that short name.
    procedure Save(const Mailbox: TMailbox);

    // Raises EMailboxNotFound for an unknown OldSlug and EMailboxSlugTaken when NewSlug belongs to another mailbox of the user.
    procedure Rename(const UserId, OldSlug, NewSlug, DisplayName: string);

    // Removing an unknown mailbox does nothing.
    procedure Delete(const UserId, Slug: string);
  end;

implementation

end.
