unit MicrosoftMcp.Mailbox.Store.FireDAC;

interface

uses
  Spring.Collections,
  MCPAuth.Store.FireDAC.Interfaces,
  MCPAuth.Store.FireDAC.Command,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces;

type
  // Mailboxes on PostgreSQL. Apply migrations/postgres with TFireDACMigrations before the first use.
  // The primary key (user_id, slug) decides a race between two saves of the same short name.
  TMailboxStoreFireDAC = class(TInterfacedObject, IMailboxRepository)
  private
    FFactory: IFireDACConnectionFactory;

    procedure SetMailboxParams(const Command: TFireDACCommand; const Mailbox: TMailbox);
    function ReadMailbox(const Command: TFireDACCommand): TMailbox;

  public
    constructor Create(const Factory: IFireDACConnectionFactory);

    function TryGet(const UserId, Slug: string; out Mailbox: TMailbox): Boolean;
    function ListForUser(const UserId: string): IReadOnlyList<TMailbox>;

    procedure Save(const Mailbox: TMailbox);
    procedure Rename(const UserId, OldSlug, NewSlug, DisplayName: string);
    procedure Delete(const UserId, Slug: string);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Exceptions;

const
  SelectColumns = 'SELECT user_id, slug, display_name, address, account_key, kind, created_at FROM microsoftmcp_mailboxes ';
  SelectOne = SelectColumns + 'WHERE user_id = :user_id AND slug = :slug';
  SelectByUser = SelectColumns + 'WHERE user_id = :user_id ORDER BY created_at, slug';
  InsertMailbox = 'INSERT INTO microsoftmcp_mailboxes (user_id, slug, display_name, address, account_key, kind, created_at) ' +
                  'VALUES (:user_id, :slug, :display_name, :address, :account_key, :kind, :created_at)';
  RenameMailbox = 'UPDATE microsoftmcp_mailboxes SET slug = :new_slug, display_name = :display_name ' +
                  'WHERE user_id = :user_id AND slug = :old_slug';
  DeleteMailbox = 'DELETE FROM microsoftmcp_mailboxes WHERE user_id = :user_id AND slug = :slug';

resourcestring
  SlugTakenFormat = 'Mailbox short name "%s" is already in use';
  MailboxNotFoundFormat = 'Mailbox "%s" does not exist';

{ TMailboxStoreFireDAC }

constructor TMailboxStoreFireDAC.Create(const Factory: IFireDACConnectionFactory);
begin
  inherited Create;

  FFactory := Factory;
end;

function TMailboxStoreFireDAC.TryGet(const UserId, Slug: string; out Mailbox: TMailbox): Boolean;
begin
  Mailbox := Default(TMailbox);

  const Command = TFireDACCommand.Create(FFactory, SelectOne);
  try
    Command.SetText('user_id', UserId);
    Command.SetText('slug', Slug);
    Command.Open;

    Result := not Command.Eof;
    if Result then
    begin
      Mailbox := ReadMailbox(Command);
    end;
  finally
    Command.Free;
  end;
end;

function TMailboxStoreFireDAC.ListForUser(const UserId: string): IReadOnlyList<TMailbox>;
begin
  const Mailboxes = TCollections.CreateList<TMailbox>;

  const Command = TFireDACCommand.Create(FFactory, SelectByUser);
  try
    Command.SetText('user_id', UserId);
    Command.Open;

    while not Command.Eof do
    begin
      Mailboxes.Add(ReadMailbox(Command));
      Command.Next;
    end;
  finally
    Command.Free;
  end;

  Result := Mailboxes.AsReadOnly;
end;

procedure TMailboxStoreFireDAC.Save(const Mailbox: TMailbox);
begin
  const Command = TFireDACCommand.Create(FFactory, InsertMailbox);
  try
    SetMailboxParams(Command, Mailbox);
    try
      Command.Execute;
    except
      on Error: Exception do
      begin
        if TFireDACCommand.IsUniqueViolation(Error) then
        begin
          raise EMailboxSlugTaken.CreateFmt(SlugTakenFormat, [Mailbox.Slug]);
        end;
        raise;
      end;
    end;
  finally
    Command.Free;
  end;
end;

procedure TMailboxStoreFireDAC.Rename(const UserId, OldSlug, NewSlug, DisplayName: string);
begin
  const Command = TFireDACCommand.Create(FFactory, RenameMailbox);
  try
    Command.SetText('user_id', UserId);
    Command.SetText('old_slug', OldSlug);
    Command.SetText('new_slug', NewSlug);
    Command.SetLongText('display_name', DisplayName);

    var AffectedRows: Integer;
    try
      AffectedRows := Command.Execute;
    except
      on Error: Exception do
      begin
        if TFireDACCommand.IsUniqueViolation(Error) then
        begin
          raise EMailboxSlugTaken.CreateFmt(SlugTakenFormat, [NewSlug]);
        end;
        raise;
      end;
    end;

    const IsUnknown = (AffectedRows = 0);
    if IsUnknown then
    begin
      raise EMailboxNotFound.CreateFmt(MailboxNotFoundFormat, [OldSlug]);
    end;
  finally
    Command.Free;
  end;
end;

procedure TMailboxStoreFireDAC.Delete(const UserId, Slug: string);
begin
  const Command = TFireDACCommand.Create(FFactory, DeleteMailbox);
  try
    Command.SetText('user_id', UserId);
    Command.SetText('slug', Slug);
    Command.Execute;
  finally
    Command.Free;
  end;
end;

// The display name goes through SetLongText (here and in Rename): as a string parameter an accented letter reaches PostgreSQL as UTF-16 on Linux.
procedure TMailboxStoreFireDAC.SetMailboxParams(const Command: TFireDACCommand; const Mailbox: TMailbox);
begin
  Command.SetText('user_id', Mailbox.UserId);
  Command.SetText('slug', Mailbox.Slug);
  Command.SetLongText('display_name', Mailbox.DisplayName);
  Command.SetText('address', Mailbox.Address);
  Command.SetText('account_key', Mailbox.AccountKey);
  Command.SetText('kind', Mailbox.Kind.Code);
  Command.SetUtc('created_at', Mailbox.CreatedAtUtc);
end;

function TMailboxStoreFireDAC.ReadMailbox(const Command: TFireDACCommand): TMailbox;
begin
  Result.UserId := Command.Text('user_id');
  Result.Slug := Command.Text('slug');
  Result.DisplayName := Command.Text('display_name');
  Result.Address := Command.Text('address');
  Result.AccountKey := Command.Text('account_key');
  Result.Kind := TMailboxKind.Parse(Command.Text('kind'));
  Result.CreatedAtUtc := Command.Utc('created_at');
end;

end.
