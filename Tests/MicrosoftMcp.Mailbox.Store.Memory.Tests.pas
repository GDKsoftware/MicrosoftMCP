unit MicrosoftMcp.Mailbox.Store.Memory.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Mailbox.Interfaces,
  MicrosoftMcp.Mailbox.Store.Contract.Tests;

type
  [TestFixture]
  TMailboxStoreMemoryTests = class(TMailboxStoreContractTests)
  protected
    function CreateRepository: IMailboxRepository; override;

  public
    [Test]
    procedure ConcurrentSavesOfDifferentSlugsAreAllKept;

    [Test]
    procedure ConcurrentSavesOfOneSlugSucceedOnce;
  end;

implementation

uses
  System.SysUtils,
  System.SyncObjs,
  System.Threading,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Exceptions,
  MicrosoftMcp.Mailbox.Store.Memory;

const
  WorkerCount = 8;
  SavesPerWorker = 50;

{ TMailboxStoreMemoryTests }

function TMailboxStoreMemoryTests.CreateRepository: IMailboxRepository;
begin
  Result := TMailboxStoreMemory.Create;
end;

procedure TMailboxStoreMemoryTests.ConcurrentSavesOfDifferentSlugsAreAllKept;
begin
  const Repository = CreateRepository;

  TParallel.For(0, WorkerCount - 1,
    procedure(Worker: Integer)
    begin
      for var Index := 1 to SavesPerWorker do
      begin
        var Mailbox := Default(TMailbox);
        Mailbox.UserId := 'user';
        Mailbox.Slug := Format('box-%d-%d', [Worker, Index]);
        Mailbox.DisplayName := Mailbox.Slug;
        Repository.Save(Mailbox);
      end;
    end);

  Assert.AreEqual(WorkerCount * SavesPerWorker, Repository.ListForUser('user').Count);
end;

procedure TMailboxStoreMemoryTests.ConcurrentSavesOfOneSlugSucceedOnce;
begin
  const Repository = CreateRepository;
  var Successes := 0;
  var Conflicts := 0;

  TParallel.For(0, WorkerCount - 1,
    procedure(Worker: Integer)
    begin
      var Mailbox := Default(TMailbox);
      Mailbox.UserId := 'user';
      Mailbox.Slug := 'same';
      try
        Repository.Save(Mailbox);
        TInterlocked.Increment(Successes);
      except
        on EMailboxSlugTaken do
        begin
          TInterlocked.Increment(Conflicts);
        end;
      end;
    end);

  Assert.AreEqual(1, Successes);
  Assert.AreEqual(WorkerCount - 1, Conflicts);
end;

end.
