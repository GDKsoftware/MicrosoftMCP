unit MicrosoftMcp.Mailbox.Store.FireDAC.Tests;

interface

uses
  DUnitX.TestFramework,
  MCPAuth.Store.FireDAC.Interfaces,
  MCPAuth.Store.FireDAC.PgDriver,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Store.Contract.Tests;

type
  // Runs the mailbox store contract against PostgreSQL. Without MICROSOFTMCP_TEST_PG every test passes without a database.
  [TestFixture]
  TMailboxStoreFireDACTests = class(TMailboxStoreContractTests)
  private
    FDriver: TFireDACPgDriver;
    FFactory: IFireDACConnectionFactory;

    procedure RecreateSchema;
    procedure ClearTables;
    procedure AssertStoredAsUtc(const Factory: IFireDACConnectionFactory);

  protected
    function CreateRepository: IMailboxRepository; override;
    function UnavailableReason: string; override;

  public
    [SetupFixture]
    procedure SetupFixture;

    [TearDownFixture]
    procedure TearDownFixture;

    [Test]
    procedure TimesAreStoredAsUtc;

    [Test]
    procedure TimesStayUtcInAnotherSessionTimeZone;
  end;

implementation

uses
  System.SysUtils,
  MCPAuth.Store.FireDAC.ConnectionFactory,
  MCPAuth.Store.FireDAC.Migrations,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Store.FireDAC,
  MicrosoftMcp.Tests.Postgres;

const
  MailboxTable = 'microsoftmcp_mailboxes';
  VersionTable = 'microsoftmcp_schema_version';
  PostgresDialect = 'postgres';
  StoredUtcQuery = 'SELECT to_char(created_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD HH24:MI:SS'') FROM microsoftmcp_mailboxes WHERE slug = ''utc''';

{ TMailboxStoreFireDACTests }

procedure TMailboxStoreFireDACTests.SetupFixture;
begin
  if not UnavailableReason.IsEmpty then
  begin
    Exit;
  end;

  FDriver := TFireDACPgDriver.Create(TTestPostgres.VendorLib);
  try
    FFactory := TFireDACConnectionFactory.Create(TTestPostgres.ConnectionString);
    RecreateSchema;
  except
    // DUnitX skips the fixture teardown when its setup fails.
    TearDownFixture;
    raise;
  end;
end;

procedure TMailboxStoreFireDACTests.TearDownFixture;
begin
  FFactory := nil;
  FreeAndNil(FDriver);
end;

function TMailboxStoreFireDACTests.UnavailableReason: string;
begin
  Result := TTestPostgres.UnavailableReason;
end;

function TMailboxStoreFireDACTests.CreateRepository: IMailboxRepository;
begin
  ClearTables;
  Result := TMailboxStoreFireDAC.Create(FFactory);
end;

procedure TMailboxStoreFireDACTests.RecreateSchema;
begin
  TTestPostgres.Execute(FFactory, Format('DROP TABLE IF EXISTS %s', [MailboxTable]));
  TTestPostgres.Execute(FFactory, Format('DROP TABLE IF EXISTS %s', [VersionTable]));
  TFireDACMigrations.Apply(FFactory, PostgresDialect, TTestPostgres.MigrationsPath, VersionTable);
end;

procedure TMailboxStoreFireDACTests.ClearTables;
begin
  TTestPostgres.Execute(FFactory, Format('DELETE FROM %s', [MailboxTable]));
end;

procedure TMailboxStoreFireDACTests.TimesAreStoredAsUtc;
begin
  RequireStore;

  ClearTables;
  AssertStoredAsUtc(FFactory);
end;

procedure TMailboxStoreFireDACTests.TimesStayUtcInAnotherSessionTimeZone;
begin
  RequireStore;

  ClearTables;
  const OtherZone = TTestPostgres.ConnectionString + ';PGAdvanced=options=-c TimeZone=Asia/Kathmandu';
  const Factory: IFireDACConnectionFactory = TFireDACConnectionFactory.Create(OtherZone);

  AssertStoredAsUtc(Factory);
end;

procedure TMailboxStoreFireDACTests.AssertStoredAsUtc(const Factory: IFireDACConnectionFactory);
begin
  const CreatedAtUtc = EncodeDate(2026, 6, 1) + EncodeTime(12, 0, 0, 0);
  const Repository: IMailboxRepository = TMailboxStoreFireDAC.Create(Factory);
  var Mailbox := Default(TMailbox);
  Mailbox.UserId := 'user-utc';
  Mailbox.Slug := 'utc';
  Mailbox.CreatedAtUtc := CreatedAtUtc;
  Repository.Save(Mailbox);

  var Read: TMailbox;
  const IsFound = Repository.TryGet('user-utc', 'utc', Read);
  const StoredUtc = TTestPostgres.QueryText(Factory, StoredUtcQuery);

  Assert.IsTrue(IsFound);
  Assert.AreEqual<TDateTime>(CreatedAtUtc, Read.CreatedAtUtc);
  Assert.AreEqual('2026-06-01 12:00:00', StoredUtc);
end;

end.
