unit MicrosoftMcp.Tests.Postgres;

interface

uses
  MCPAuth.Store.FireDAC.Interfaces;

type
  // Access to the test database named by MICROSOFTMCP_TEST_PG, a FireDAC connection string such as
  // 'DriverID=PG;Server=127.0.0.1;Port=55432;Database=microsoftmcp_test;User_Name=microsoftmcp_test;Password=microsoftmcp_test'.
  // MICROSOFTMCP_PG_VENDORLIB optionally names the libpq library to load.
  TTestPostgres = class
  public
    class function UnavailableReason: string; static;
    class function ConnectionString: string; static;
    class function VendorLib: string; static;
    class function MigrationsPath: string; static;
    class procedure Execute(const Factory: IFireDACConnectionFactory; const Sql: string); static;
    class function QueryText(const Factory: IFireDACConnectionFactory; const Sql: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Variants;

const
  ConnectionStringVariable = 'MICROSOFTMCP_TEST_PG';
  VendorLibVariable = 'MICROSOFTMCP_PG_VENDORLIB';
  MigrationsFolder = 'migrations';
  // Without it libpq takes the client encoding from the locale of the machine, which breaks accented text on Linux.
  Utf8CharacterSet = 'CharacterSet=UTF8';

{ TTestPostgres }

class function TTestPostgres.UnavailableReason: string;
begin
  if ConnectionString.IsEmpty then
  begin
    Result := Format('%s not set', [ConnectionStringVariable]);
  end
  else
  begin
    Result := '';
  end;
end;

class function TTestPostgres.ConnectionString: string;
begin
  Result := GetEnvironmentVariable(ConnectionStringVariable).Trim;
  const HasConnection = not Result.IsEmpty;
  if HasConnection then
  begin
    Result := Result + ';' + Utf8CharacterSet;
  end;
end;

class function TTestPostgres.VendorLib: string;
begin
  Result := GetEnvironmentVariable(VendorLibVariable).Trim;
end;

class function TTestPostgres.MigrationsPath: string;
begin
  var Folder := TPath.GetDirectoryName(ParamStr(0));
  while not Folder.IsEmpty do
  begin
    const Candidate = TPath.Combine(Folder, MigrationsFolder);
    if TDirectory.Exists(Candidate) then
    begin
      Exit(Candidate);
    end;

    const Parent = TPath.GetDirectoryName(Folder);
    if Parent = Folder then
    begin
      Break;
    end;
    Folder := Parent;
  end;

  raise Exception.CreateFmt('Folder "%s" not found above %s', [MigrationsFolder, ParamStr(0)]);
end;

class procedure TTestPostgres.Execute(const Factory: IFireDACConnectionFactory; const Sql: string);
begin
  const Connection = Factory.NewConnection;
  try
    Connection.ExecSQL(Sql);
  finally
    Connection.Free;
  end;
end;

class function TTestPostgres.QueryText(const Factory: IFireDACConnectionFactory; const Sql: string): string;
begin
  const Connection = Factory.NewConnection;
  try
    Result := VarToStr(Connection.ExecSQLScalar(Sql));
  finally
    Connection.Free;
  end;
end;

end.
