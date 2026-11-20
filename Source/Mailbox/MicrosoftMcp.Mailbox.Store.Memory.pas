unit MicrosoftMcp.Mailbox.Store.Memory;

interface

uses
  System.SyncObjs,
  Spring.Collections,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces;

type
  // Thread-safe; one lock guards all operations.
  TMailboxStoreMemory = class(TInterfacedObject, IMailboxRepository)
  private
    FLock: TCriticalSection;
    FMailboxes: IDictionary<string, TMailbox>;

    class function KeyOf(const UserId, Slug: string): string; static;

  public
    constructor Create;
    destructor Destroy; override;

    function TryGet(const UserId, Slug: string; out Mailbox: TMailbox): Boolean;
    function ListForUser(const UserId: string): IReadOnlyList<TMailbox>;

    procedure Save(const Mailbox: TMailbox);
    procedure Rename(const UserId, OldSlug, NewSlug, DisplayName: string);
    procedure Delete(const UserId, Slug: string);
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  MicrosoftMcp.Mailbox.Exceptions;

const
  KeySeparator = #1;

resourcestring
  SlugTakenFormat = 'Mailbox short name "%s" is already in use';
  MailboxNotFoundFormat = 'Mailbox "%s" does not exist';

{ TMailboxStoreMemory }

class function TMailboxStoreMemory.KeyOf(const UserId, Slug: string): string;
begin
  Result := Format('%s%s%s', [UserId, KeySeparator, Slug]);
end;

constructor TMailboxStoreMemory.Create;
begin
  inherited Create;

  FLock := TCriticalSection.Create;
  FMailboxes := TCollections.CreateDictionary<string, TMailbox>;
end;

destructor TMailboxStoreMemory.Destroy;
begin
  FLock.Free;

  inherited Destroy;
end;

function TMailboxStoreMemory.TryGet(const UserId, Slug: string; out Mailbox: TMailbox): Boolean;
begin
  FLock.Enter;
  try
    Result := FMailboxes.TryGetValue(KeyOf(UserId, Slug), Mailbox);
  finally
    FLock.Leave;
  end;
end;

function TMailboxStoreMemory.ListForUser(const UserId: string): IReadOnlyList<TMailbox>;
begin
  const Mailboxes = TCollections.CreateList<TMailbox>;

  FLock.Enter;
  try
    for var Mailbox in FMailboxes.Values do
    begin
      const IsOwnMailbox = (Mailbox.UserId = UserId);
      if IsOwnMailbox then
      begin
        Mailboxes.Add(Mailbox);
      end;
    end;
  finally
    FLock.Leave;
  end;

  const OldestFirst = TComparer<TMailbox>.Construct(
    function(const Left, Right: TMailbox): Integer
    begin
      Result := TComparer<TDateTime>.Default.Compare(Left.CreatedAtUtc, Right.CreatedAtUtc);
      if Result = 0 then
      begin
        Result := CompareStr(Left.Slug, Right.Slug);
      end;
    end);
  Mailboxes.Sort(OldestFirst);

  Result := Mailboxes.AsReadOnly;
end;

procedure TMailboxStoreMemory.Save(const Mailbox: TMailbox);
begin
  FLock.Enter;
  try
    const Key = KeyOf(Mailbox.UserId, Mailbox.Slug);
    const IsTaken = FMailboxes.ContainsKey(Key);
    if IsTaken then
    begin
      raise EMailboxSlugTaken.CreateFmt(SlugTakenFormat, [Mailbox.Slug]);
    end;

    FMailboxes[Key] := Mailbox;
  finally
    FLock.Leave;
  end;
end;

procedure TMailboxStoreMemory.Rename(const UserId, OldSlug, NewSlug, DisplayName: string);
begin
  FLock.Enter;
  try
    var Mailbox: TMailbox;
    const IsKnown = FMailboxes.TryGetValue(KeyOf(UserId, OldSlug), Mailbox);
    if not IsKnown then
    begin
      raise EMailboxNotFound.CreateFmt(MailboxNotFoundFormat, [OldSlug]);
    end;

    const IsOtherMailboxWithNewSlug = ((NewSlug <> OldSlug) and FMailboxes.ContainsKey(KeyOf(UserId, NewSlug)));
    if IsOtherMailboxWithNewSlug then
    begin
      raise EMailboxSlugTaken.CreateFmt(SlugTakenFormat, [NewSlug]);
    end;

    FMailboxes.Remove(KeyOf(UserId, OldSlug));
    Mailbox.Slug := NewSlug;
    Mailbox.DisplayName := DisplayName;
    FMailboxes[KeyOf(UserId, NewSlug)] := Mailbox;
  finally
    FLock.Leave;
  end;
end;

procedure TMailboxStoreMemory.Delete(const UserId, Slug: string);
begin
  FLock.Enter;
  try
    FMailboxes.Remove(KeyOf(UserId, Slug));
  finally
    FLock.Leave;
  end;
end;

end.
