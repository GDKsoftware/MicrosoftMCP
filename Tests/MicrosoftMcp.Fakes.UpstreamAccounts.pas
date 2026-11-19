unit MicrosoftMcp.Fakes.UpstreamAccounts;

interface

uses
  System.SysUtils,
  Spring.Collections,
  MCPAuth.Client.UpstreamAccounts.Interfaces;

type
  // Linked accounts and tokens per user, with the failure of each call switchable by a test.
  TFakeUpstreamAccounts = class(TInterfacedObject, IUpstreamAccounts)
  private
    FAccounts: IDictionary<string, TArray<TRemoteAccount>>;
    FTokens: IDictionary<string, string>;
    FListFailure: TFunc<Exception>;
    FTokenFailure: TFunc<Exception>;

    function TokenKey(const UserId, AccountKey: string): string;

  public
    constructor Create;

    procedure AddAccount(const UserId: string; const Account: TRemoteAccount; const AccessToken: string);
    procedure FailListWith(const Failure: TFunc<Exception>);
    procedure FailGetAccessTokenWith(const Failure: TFunc<Exception>);

    function ListForUser(const UserId: string): TArray<TRemoteAccount>;
    function GetAccessToken(const UserId, AccountKey: string): string;
  end;

implementation

{ TFakeUpstreamAccounts }

constructor TFakeUpstreamAccounts.Create;
begin
  inherited Create;

  FAccounts := TCollections.CreateDictionary<string, TArray<TRemoteAccount>>;
  FTokens := TCollections.CreateDictionary<string, string>;
end;

procedure TFakeUpstreamAccounts.AddAccount(const UserId: string; const Account: TRemoteAccount; const AccessToken: string);
begin
  var Accounts: TArray<TRemoteAccount> := [];
  FAccounts.TryGetValue(UserId, Accounts);

  FAccounts[UserId] := Accounts + [Account];
  FTokens[TokenKey(UserId, Account.Key)] := AccessToken;
end;

procedure TFakeUpstreamAccounts.FailListWith(const Failure: TFunc<Exception>);
begin
  FListFailure := Failure;
end;

procedure TFakeUpstreamAccounts.FailGetAccessTokenWith(const Failure: TFunc<Exception>);
begin
  FTokenFailure := Failure;
end;

function TFakeUpstreamAccounts.ListForUser(const UserId: string): TArray<TRemoteAccount>;
begin
  if Assigned(FListFailure) then
    raise FListFailure();

  Result := [];
  FAccounts.TryGetValue(UserId, Result);
end;

function TFakeUpstreamAccounts.GetAccessToken(const UserId, AccountKey: string): string;
begin
  if Assigned(FTokenFailure) then
    raise FTokenFailure();

  const IsLinked = FTokens.TryGetValue(TokenKey(UserId, AccountKey), Result);
  if not IsLinked then
    raise EAbort.Create('Fake upstream accounts: token requested for an account that was never added');
end;

function TFakeUpstreamAccounts.TokenKey(const UserId, AccountKey: string): string;
begin
  Result := Format('%s|%s', [UserId, AccountKey]);
end;

end.
