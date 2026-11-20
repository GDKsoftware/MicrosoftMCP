unit MicrosoftMcp.Confirm.Memory;

interface

uses
  System.SyncObjs,
  Spring.Collections,
  MCPAuth.Clock.Interfaces,
  MCPAuth.Secret.Interfaces,
  MicrosoftMcp.Confirm.Interfaces;

type
  TPendingConfirmation = record
    UserId: string;
    ToolName: string;
    ArgumentsHash: string;
    ExpiresAtUtc: TDateTime;
  end;

  // Thread-safe and in memory: the tokens live in this process only, so a restart cancels pending confirmations and
  // both calls of a confirmation must reach the same process. Only the SHA-256 of a token is kept.
  TConfirmationsMemory = class(TInterfacedObject, IConfirmations)
  private
    FLock: TCriticalSection;
    FPending: IDictionary<string, TPendingConfirmation>;
    FTokens: ITokenGenerator;
    FClock: IClock;

    function IsMatch(const Pending: TPendingConfirmation; const UserId, ToolName, ArgumentsHash: string): Boolean;
    function IsExpired(const Pending: TPendingConfirmation): Boolean;
    function DeleteExpiredLocked: Integer;

  public
    const LifetimeMinutes = 10;

    constructor Create(const Tokens: ITokenGenerator; const Clock: IClock);
    destructor Destroy; override;

    function Issue(const UserId, ToolName, ArgumentsHash, Summary: string): string;
    function TryRedeem(const UserId, ToolName, ArgumentsHash, Token: string): Boolean;
    function DeleteExpired: Integer;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  MCPAuth.Secret.Hash;

{ TConfirmationsMemory }

constructor TConfirmationsMemory.Create(const Tokens: ITokenGenerator; const Clock: IClock);
begin
  inherited Create;

  FLock := TCriticalSection.Create;
  FPending := TCollections.CreateDictionary<string, TPendingConfirmation>;
  FTokens := Tokens;
  FClock := Clock;
end;

destructor TConfirmationsMemory.Destroy;
begin
  FLock.Free;

  inherited Destroy;
end;

function TConfirmationsMemory.Issue(const UserId, ToolName, ArgumentsHash, Summary: string): string;
begin
  // The summary goes back to Claude together with the token; it is not stored, because it can name addresses or subjects.
  Result := FTokens.NewToken;

  var Pending := Default(TPendingConfirmation);
  Pending.UserId        := UserId;
  Pending.ToolName      := ToolName;
  Pending.ArgumentsHash := ArgumentsHash;
  Pending.ExpiresAtUtc  := IncMinute(FClock.NowUtc, LifetimeMinutes);

  const TokenHash = TTokenHash.Of(Result);

  FLock.Acquire;
  try
    DeleteExpiredLocked;
    FPending[TokenHash] := Pending;
  finally
    FLock.Release;
  end;
end;

function TConfirmationsMemory.TryRedeem(const UserId, ToolName, ArgumentsHash, Token: string): Boolean;
begin
  if Token.IsEmpty then
    Exit(False);

  const TokenHash = TTokenHash.Of(Token);

  FLock.Acquire;
  try
    var Pending: TPendingConfirmation;
    const IsKnown = FPending.TryGetValue(TokenHash, Pending);
    if not IsKnown then
      Exit(False);

    if IsExpired(Pending) then
    begin
      FPending.Remove(TokenHash);
      Exit(False);
    end;

    // A token shown with other arguments, by another user or for another tool stays valid for its own call.
    if not IsMatch(Pending, UserId, ToolName, ArgumentsHash) then
      Exit(False);

    FPending.Remove(TokenHash);
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TConfirmationsMemory.IsMatch(const Pending: TPendingConfirmation; const UserId, ToolName, ArgumentsHash: string): Boolean;
begin
  Result := ((Pending.UserId = UserId) and
             (Pending.ToolName = ToolName) and
             TTokenHash.SameHash(Pending.ArgumentsHash, ArgumentsHash));
end;

function TConfirmationsMemory.DeleteExpired: Integer;
begin
  FLock.Acquire;
  try
    Result := DeleteExpiredLocked;
  finally
    FLock.Release;
  end;
end;

function TConfirmationsMemory.DeleteExpiredLocked: Integer;
begin
  var ExpiredHashes: TArray<string> := [];
  for var Pair in FPending do
  begin
    if IsExpired(Pair.Value) then
      ExpiredHashes := ExpiredHashes + [Pair.Key];
  end;

  for var TokenHash in ExpiredHashes do
  begin
    FPending.Remove(TokenHash);
  end;

  Result := Length(ExpiredHashes);
end;

function TConfirmationsMemory.IsExpired(const Pending: TPendingConfirmation): Boolean;
begin
  Result := (FClock.NowUtc >= Pending.ExpiresAtUtc);
end;

end.
