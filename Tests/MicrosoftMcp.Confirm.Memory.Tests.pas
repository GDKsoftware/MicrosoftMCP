unit MicrosoftMcp.Confirm.Memory.Tests;

interface

uses
  DUnitX.TestFramework,
  MicrosoftMcp.Confirm.Interfaces,
  MicrosoftMcp.Fakes.Clock;

type
  [TestFixture]
  TConfirmationsMemoryTests = class
  private
    FClock: TFakeClock;
    FClockInterface: IInterface;
    FConfirmations: IConfirmations;

    function HashOf(const ArgumentsJson: string): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TokenIsRedeemableOnce;

    [Test]
    procedure TokenWithOtherArgumentsIsRejected;

    [Test]
    procedure TokenOfOtherUserIsRejected;

    [Test]
    procedure TokenForOtherToolIsRejected;

    [Test]
    procedure ExpiredTokenIsRejected;

    [Test]
    procedure UnknownOrEmptyTokenIsRejected;

    [Test]
    procedure RejectedAttemptLeavesTokenForItsOwnCall;

    [Test]
    procedure DeleteExpiredRemovesOnlyExpiredTokens;

    [Test]
    procedure ArgumentOrderDoesNotChangeHash;

    [Test]
    procedure ConfirmationTokenIsLeftOutOfHash;

    [Test]
    procedure OtherValueChangesHash;

    [Test]
    procedure NestedConfirmationTokenIsPartOfHash;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  MCPAuth.Secret.Token,
  MicrosoftMcp.Confirm.Memory,
  MicrosoftMcp.Confirm.Arguments;

const
  Kees = 'user-kees';
  Anna = 'user-anna';
  DeleteTool = 'mail_delete';
  SendTool = 'mail_send';
  Summary = 'Delete message "Quarterly report"';
  ArgumentsJson = '{"mailbox":"work","message_id":"AAMk1"}';
  OtherArgumentsJson = '{"mailbox":"work","message_id":"AAMk2"}';

{ TConfirmationsMemoryTests }

procedure TConfirmationsMemoryTests.Setup;
begin
  FClock := TFakeClock.Create(EncodeDateTime(2026, 11, 20, 9, 0, 0, 0));
  FClockInterface := FClock;
  FConfirmations := TConfirmationsMemory.Create(TTokenGenerator.Create, FClock);
end;

procedure TConfirmationsMemoryTests.TearDown;
begin
  FConfirmations := nil;
  FClock := nil;
  FClockInterface := nil;
end;

function TConfirmationsMemoryTests.HashOf(const ArgumentsJson: string): string;
begin
  const Arguments = TJSONObject.ParseJSONValue(ArgumentsJson) as TJSONObject;
  try
    Result := TConfirmationArguments.Hash(Arguments);
  finally
    Arguments.Free;
  end;
end;

procedure TConfirmationsMemoryTests.TokenIsRedeemableOnce;
begin
  const Hash = HashOf(ArgumentsJson);
  const Token = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  const IsFirstRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, Token);
  const IsSecondRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, Token);

  Assert.IsFalse(Token.IsEmpty);
  Assert.IsTrue(IsFirstRedeemed, 'A fresh token with the same user, tool and arguments must be accepted');
  Assert.IsFalse(IsSecondRedeemed, 'A token must work only once');
end;

procedure TConfirmationsMemoryTests.TokenWithOtherArgumentsIsRejected;
begin
  const Token = FConfirmations.Issue(Kees, DeleteTool, HashOf(ArgumentsJson), Summary);

  const IsRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, HashOf(OtherArgumentsJson), Token);

  Assert.IsFalse(IsRedeemed);
end;

procedure TConfirmationsMemoryTests.TokenOfOtherUserIsRejected;
begin
  const Hash = HashOf(ArgumentsJson);
  const Token = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  const IsRedeemed = FConfirmations.TryRedeem(Anna, DeleteTool, Hash, Token);

  Assert.IsFalse(IsRedeemed);
end;

procedure TConfirmationsMemoryTests.TokenForOtherToolIsRejected;
begin
  const Hash = HashOf(ArgumentsJson);
  const Token = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  const IsRedeemed = FConfirmations.TryRedeem(Kees, SendTool, Hash, Token);

  Assert.IsFalse(IsRedeemed);
end;

procedure TConfirmationsMemoryTests.ExpiredTokenIsRejected;
begin
  const Hash = HashOf(ArgumentsJson);
  const Token = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  FClock.AdvanceMinutes(TConfirmationsMemory.LifetimeMinutes);
  const IsRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, Token);

  Assert.IsFalse(IsRedeemed);
end;

procedure TConfirmationsMemoryTests.UnknownOrEmptyTokenIsRejected;
begin
  const Hash = HashOf(ArgumentsJson);
  FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  const IsUnknownRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, 'made-up-token');
  const IsEmptyRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, '');

  Assert.IsFalse(IsUnknownRedeemed);
  Assert.IsFalse(IsEmptyRedeemed);
end;

procedure TConfirmationsMemoryTests.RejectedAttemptLeavesTokenForItsOwnCall;
begin
  const Hash = HashOf(ArgumentsJson);
  const Token = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);

  FConfirmations.TryRedeem(Anna, DeleteTool, Hash, Token);
  const IsRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, Token);

  Assert.IsTrue(IsRedeemed);
end;

procedure TConfirmationsMemoryTests.DeleteExpiredRemovesOnlyExpiredTokens;
begin
  const Hash = HashOf(ArgumentsJson);
  FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);
  FClock.AdvanceMinutes(TConfirmationsMemory.LifetimeMinutes - 1);
  const RecentToken = FConfirmations.Issue(Kees, DeleteTool, Hash, Summary);
  FClock.AdvanceMinutes(1);

  const DeletedCount = FConfirmations.DeleteExpired;
  const IsRecentRedeemed = FConfirmations.TryRedeem(Kees, DeleteTool, Hash, RecentToken);

  Assert.AreEqual(1, DeletedCount);
  Assert.IsTrue(IsRecentRedeemed);
end;

procedure TConfirmationsMemoryTests.ArgumentOrderDoesNotChangeHash;
begin
  const Hash = HashOf('{"mailbox":"work","options":{"b":2,"a":[1,{"y":true,"x":null}]},"message_id":"AAMk1"}');
  const ReorderedHash = HashOf('{"message_id":"AAMk1","options":{"a":[1,{"x":null,"y":true}],"b":2},"mailbox":"work"}');

  Assert.AreEqual(Hash, ReorderedHash);
end;

procedure TConfirmationsMemoryTests.ConfirmationTokenIsLeftOutOfHash;
begin
  const Hash = HashOf(ArgumentsJson);
  const HashWithToken = HashOf('{"confirmation_token":"abc","mailbox":"work","message_id":"AAMk1"}');

  Assert.AreEqual(Hash, HashWithToken);
end;

procedure TConfirmationsMemoryTests.OtherValueChangesHash;
begin
  const Hash = HashOf(ArgumentsJson);
  const OtherHash = HashOf(OtherArgumentsJson);

  Assert.AreNotEqual(Hash, OtherHash);
end;

procedure TConfirmationsMemoryTests.NestedConfirmationTokenIsPartOfHash;
begin
  const Hash = HashOf('{"mailbox":"work","options":{"confirmation_token":"a"}}');
  const OtherHash = HashOf('{"mailbox":"work","options":{"confirmation_token":"b"}}');

  Assert.AreNotEqual(Hash, OtherHash);
end;

end.
