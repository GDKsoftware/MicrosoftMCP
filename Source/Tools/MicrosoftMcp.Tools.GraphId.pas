unit MicrosoftMcp.Tools.GraphId;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo;

type
  // Marks a string parameter that ends up in the path of a Graph URL. Some Microsoft365-4D clients put these ids into
  // the path unescaped, so a value such as "x/../../messages/1/send" could address another resource than the tool's.
  GraphIdAttribute = class(TCustomAttribute)
  end;

  // Checks every [GraphId] parameter before a tool does anything with it.
  TGraphIdGuard = class
  private
    class function IsGuarded(const Prop: TRttiProperty): Boolean; static;
    class function ParameterName(const Prop: TRttiProperty): string; static;
    class function IsAllowedCharacter(const Character: Char): Boolean; static;

  public
    // Graph ids (messages, events, contacts, folders, drive items, sites, pages) consist of letters, digits and
    // - _ = + . , !; a value of dots only would be a path segment of its own.
    class function IsValid(const Value: string): Boolean; static;

    // Raises EToolArgumentError for the first [GraphId] property whose value is not empty and not a valid id.
    class procedure Check(const Params: TObject); static;
  end;

implementation

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Exceptions;

const
  AllowedPunctuation = '-_=+.,!';
  Dot = '.';

resourcestring
  InvalidIdFormat = 'The value of %s is not a valid Microsoft Graph id. Use an id exactly as another tool returned it.';

{ TGraphIdGuard }

class procedure TGraphIdGuard.Check(const Params: TObject);
begin
  if not Assigned(Params) then
    Exit;

  const Context = TRttiContext.Create;
  for var Prop in Context.GetType(Params.ClassType).GetProperties do
  begin
    if not IsGuarded(Prop) then
      Continue;

    const Value = Prop.GetValue(Params).AsString;
    if not IsValid(Value) then
      raise EToolArgumentError.CreateFmt(InvalidIdFormat, [ParameterName(Prop)]);
  end;
end;

class function TGraphIdGuard.IsGuarded(const Prop: TRttiProperty): Boolean;
begin
  const IsStringProperty = (Prop.IsReadable and (Prop.PropertyType.TypeKind = tkUString));
  Result := (IsStringProperty and (Prop.GetAttribute<GraphIdAttribute> <> nil));
end;

class function TGraphIdGuard.IsValid(const Value: string): Boolean;
begin
  if Value.IsEmpty then
    Exit(True);

  for var Character in Value do
  begin
    if not IsAllowedCharacter(Character) then
      Exit(False);
  end;

  const IsDotsOnly = Value.Replace(Dot, '').IsEmpty;
  Result := not IsDotsOnly;
end;

class function TGraphIdGuard.IsAllowedCharacter(const Character: Char): Boolean;
begin
  Result := (CharInSet(Character, ['A'..'Z', 'a'..'z', '0'..'9']) or AllowedPunctuation.Contains(Character));
end;

class function TGraphIdGuard.ParameterName(const Prop: TRttiProperty): string;
begin
  const SchemaName = Prop.GetAttribute<SchemaNameAttribute>;
  if Assigned(SchemaName) then
    Result := SchemaName.Name
  else
    Result := Prop.Name;
end;

end.
