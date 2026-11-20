unit MicrosoftMcp.Mailbox.Store.Contract.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Interfaces;

type
  // Shared behaviour every mailbox store must show. A concrete fixture derives from it, carries [TestFixture]
  // and supplies the store under test.
  TMailboxStoreContractTests = class
  private
    FRepository: IMailboxRepository;

    function NewMailbox(const UserId, Slug, DisplayName: string): TMailbox;
    function SlugsOf(const UserId: string): string;

  protected
    // Passes the running test when UnavailableReason is not empty.
    procedure RequireStore;

    function CreateRepository: IMailboxRepository; virtual; abstract;

    // A non-empty reason makes every test pass without touching a store, for stores that need an external server.
    function UnavailableReason: string; virtual;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure SavedMailboxRoundTrips;

    [Test]
    procedure SharedMailboxRoundTrips;

    [Test]
    procedure UnknownMailboxIsNotFound;

    [Test]
    procedure DuplicateSlugForSameUserRaises;

    [Test]
    procedure SameSlugForOtherUserIsAllowed;

    [Test]
    procedure ListForUserReturnsOnlyOwn;

    [Test]
    procedure ListForUserIsOrderedOldestFirst;

    [Test]
    procedure RenameChangesSlugAndDisplayName;

    [Test]
    procedure RenameKeepsDisplayNameChangeForSameSlug;

    [Test]
    procedure RenameToTakenSlugRaises;

    [Test]
    procedure RenameUnknownMailboxRaises;

    [Test]
    procedure RenameDoesNotTouchOtherUser;

    [Test]
    procedure DeleteRemovesOnlyThatMailbox;

    [Test]
    procedure DeleteOfUnknownMailboxDoesNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  MicrosoftMcp.Mailbox.Exceptions;

const
  Kees = 'user-kees';
  Anna = 'user-anna';
  AccentedName = 'Priv' + #$00E9 + ' Kees';

{ TMailboxStoreContractTests }

procedure TMailboxStoreContractTests.Setup;
begin
  const IsStoreAvailable = UnavailableReason.IsEmpty;
  if IsStoreAvailable then
  begin
    FRepository := CreateRepository;
  end;
end;

procedure TMailboxStoreContractTests.TearDown;
begin
  FRepository := nil;
end;

procedure TMailboxStoreContractTests.RequireStore;
begin
  const Reason = UnavailableReason;
  if not Reason.IsEmpty then
  begin
    Assert.Pass(Reason);
  end;
end;

function TMailboxStoreContractTests.UnavailableReason: string;
begin
  Result := '';
end;

function TMailboxStoreContractTests.NewMailbox(const UserId, Slug, DisplayName: string): TMailbox;
begin
  Result.UserId := UserId;
  Result.Slug := Slug;
  Result.DisplayName := DisplayName;
  Result.Address := '';
  Result.AccountKey := 'microsoft:tenant:object';
  Result.Kind := TMailboxKind.Own;
  Result.CreatedAtUtc := EncodeDateTime(2026, 11, 19, 10, 30, 15, 0);
end;

function TMailboxStoreContractTests.SlugsOf(const UserId: string): string;
begin
  const Slugs = TStringList.Create;
  try
    for var Mailbox in FRepository.ListForUser(UserId) do
    begin
      Slugs.Add(Mailbox.Slug);
    end;
    Slugs.Delimiter := ',';
    Slugs.StrictDelimiter := True;
    Result := Slugs.DelimitedText;
  finally
    Slugs.Free;
  end;
end;

procedure TMailboxStoreContractTests.SavedMailboxRoundTrips;
begin
  RequireStore;
  const Saved = NewMailbox(Kees, 'prive', AccentedName);

  FRepository.Save(Saved);

  var Read: TMailbox;
  Assert.IsTrue(FRepository.TryGet(Kees, 'prive', Read));
  Assert.AreEqual(Saved.UserId, Read.UserId);
  Assert.AreEqual(Saved.Slug, Read.Slug);
  Assert.AreEqual(Saved.DisplayName, Read.DisplayName);
  Assert.AreEqual(Saved.Address, Read.Address);
  Assert.AreEqual(Saved.AccountKey, Read.AccountKey);
  Assert.AreEqual<TMailboxKind>(Saved.Kind, Read.Kind);
  Assert.AreEqual<TDateTime>(Saved.CreatedAtUtc, Read.CreatedAtUtc);
end;

procedure TMailboxStoreContractTests.SharedMailboxRoundTrips;
begin
  RequireStore;
  var Saved := NewMailbox(Kees, 'projects', 'Projects');
  Saved.Kind := TMailboxKind.Shared;
  Saved.Address := 'projects@example.test';

  FRepository.Save(Saved);

  var Read: TMailbox;
  Assert.IsTrue(FRepository.TryGet(Kees, 'projects', Read));
  Assert.AreEqual<TMailboxKind>(TMailboxKind.Shared, Read.Kind);
  Assert.AreEqual('projects@example.test', Read.Address);
end;

procedure TMailboxStoreContractTests.UnknownMailboxIsNotFound;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));

  var Read: TMailbox;
  Assert.IsFalse(FRepository.TryGet(Kees, 'other', Read), 'unknown slug');
  Assert.IsFalse(FRepository.TryGet(Anna, 'gdk', Read), 'slug of another user');
end;

procedure TMailboxStoreContractTests.DuplicateSlugForSameUserRaises;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));

  Assert.WillRaise(
    procedure
    begin
      FRepository.Save(NewMailbox(Kees, 'gdk', 'Second'));
    end,
    EMailboxSlugTaken);

  var Read: TMailbox;
  FRepository.TryGet(Kees, 'gdk', Read);
  Assert.AreEqual('GDK', Read.DisplayName, 'the first mailbox stays untouched');
end;

procedure TMailboxStoreContractTests.SameSlugForOtherUserIsAllowed;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'Kees GDK'));

  FRepository.Save(NewMailbox(Anna, 'gdk', 'Anna GDK'));

  var Read: TMailbox;
  FRepository.TryGet(Anna, 'gdk', Read);
  Assert.AreEqual('Anna GDK', Read.DisplayName);
end;

procedure TMailboxStoreContractTests.ListForUserReturnsOnlyOwn;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));
  FRepository.Save(NewMailbox(Kees, 'prive', AccentedName));
  FRepository.Save(NewMailbox(Anna, 'work', 'Work'));

  Assert.AreEqual('gdk,prive', SlugsOf(Kees));
  Assert.AreEqual('work', SlugsOf(Anna));
  Assert.AreEqual('', SlugsOf('nobody'));
end;

procedure TMailboxStoreContractTests.ListForUserIsOrderedOldestFirst;
begin
  RequireStore;
  var Newer := NewMailbox(Kees, 'aaa', 'Newer');
  Newer.CreatedAtUtc := IncHour(Newer.CreatedAtUtc, 1);
  FRepository.Save(Newer);
  FRepository.Save(NewMailbox(Kees, 'zzz', 'Older'));

  Assert.AreEqual('zzz,aaa', SlugsOf(Kees));
end;

procedure TMailboxStoreContractTests.RenameChangesSlugAndDisplayName;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'old', 'Old name'));

  FRepository.Rename(Kees, 'old', 'new', AccentedName);

  var Read: TMailbox;
  Assert.IsFalse(FRepository.TryGet(Kees, 'old', Read), 'old slug is gone');
  Assert.IsTrue(FRepository.TryGet(Kees, 'new', Read));
  Assert.AreEqual(AccentedName, Read.DisplayName);
  Assert.AreEqual('microsoft:tenant:object', Read.AccountKey, 'other fields stay');
end;

procedure TMailboxStoreContractTests.RenameKeepsDisplayNameChangeForSameSlug;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));

  FRepository.Rename(Kees, 'gdk', 'gdk', 'GDK Software');

  var Read: TMailbox;
  Assert.IsTrue(FRepository.TryGet(Kees, 'gdk', Read));
  Assert.AreEqual('GDK Software', Read.DisplayName);
end;

procedure TMailboxStoreContractTests.RenameToTakenSlugRaises;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'one', 'One'));
  FRepository.Save(NewMailbox(Kees, 'two', 'Two'));

  Assert.WillRaise(
    procedure
    begin
      FRepository.Rename(Kees, 'one', 'two', 'Renamed');
    end,
    EMailboxSlugTaken);

  var Read: TMailbox;
  FRepository.TryGet(Kees, 'one', Read);
  Assert.AreEqual('One', Read.DisplayName, 'the mailbox keeps its name');
end;

procedure TMailboxStoreContractTests.RenameUnknownMailboxRaises;
begin
  RequireStore;

  Assert.WillRaise(
    procedure
    begin
      FRepository.Rename(Kees, 'missing', 'other', 'Other');
    end,
    EMailboxNotFound);
end;

procedure TMailboxStoreContractTests.RenameDoesNotTouchOtherUser;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'Kees GDK'));
  FRepository.Save(NewMailbox(Anna, 'gdk', 'Anna GDK'));

  FRepository.Rename(Kees, 'gdk', 'work', 'Kees work');

  var Read: TMailbox;
  Assert.IsTrue(FRepository.TryGet(Anna, 'gdk', Read));
  Assert.AreEqual('Anna GDK', Read.DisplayName);
end;

procedure TMailboxStoreContractTests.DeleteRemovesOnlyThatMailbox;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));
  FRepository.Save(NewMailbox(Kees, 'prive', AccentedName));
  FRepository.Save(NewMailbox(Anna, 'gdk', 'Anna GDK'));

  FRepository.Delete(Kees, 'gdk');

  Assert.AreEqual('prive', SlugsOf(Kees));
  Assert.AreEqual('gdk', SlugsOf(Anna));
end;

procedure TMailboxStoreContractTests.DeleteOfUnknownMailboxDoesNothing;
begin
  RequireStore;
  FRepository.Save(NewMailbox(Kees, 'gdk', 'GDK'));

  FRepository.Delete(Kees, 'missing');

  Assert.AreEqual('gdk', SlugsOf(Kees));
end;

end.
