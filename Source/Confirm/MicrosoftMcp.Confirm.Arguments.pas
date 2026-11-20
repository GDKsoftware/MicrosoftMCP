unit MicrosoftMcp.Confirm.Arguments;

interface

uses
  System.SysUtils,
  System.JSON;

type
  // The hash that ties a confirmation token to the arguments of a tool call: SHA-256 (via TTokenHash) over canonical
  // JSON, with the keys of every object sorted and the confirmation token (a top-level argument) left out.
  TConfirmationArguments = class
  private
    class procedure WriteValue(const Value: TJSONValue; const Builder: TStringBuilder); static;
    class procedure WriteObject(const JsonObject: TJSONObject; const Builder: TStringBuilder; const IsTopLevel: Boolean); static;
    class procedure WriteKey(const Key: string; const Builder: TStringBuilder); static;
    class procedure WriteArray(const JsonArray: TJSONArray; const Builder: TStringBuilder); static;
    class function SortedKeys(const JsonObject: TJSONObject): TArray<string>; static;

  public
    const TokenKey = 'confirmation_token';

    class function Hash(const Arguments: TJSONObject): string; static;
    class function Canonical(const Arguments: TJSONObject): string; static;
  end;

implementation

uses
  System.Generics.Defaults,
  Spring.Collections,
  MCPAuth.Secret.Hash;

const
  ObjectStart = '{';
  ObjectEnd = '}';
  ArrayStart = '[';
  ArrayEnd = ']';
  Separator = ',';
  KeyValueSeparator = ':';

{ TConfirmationArguments }

class function TConfirmationArguments.Hash(const Arguments: TJSONObject): string;
begin
  Result := TTokenHash.Of(Canonical(Arguments));
end;

class function TConfirmationArguments.Canonical(const Arguments: TJSONObject): string;
begin
  const Builder = TStringBuilder.Create;
  try
    WriteObject(Arguments, Builder, True);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class procedure TConfirmationArguments.WriteValue(const Value: TJSONValue; const Builder: TStringBuilder);
begin
  if Value is TJSONObject then
  begin
    WriteObject(TJSONObject(Value), Builder, False);
  end
  else if Value is TJSONArray then
  begin
    WriteArray(TJSONArray(Value), Builder);
  end
  else
  begin
    Builder.Append(Value.ToJSON);
  end;
end;

class procedure TConfirmationArguments.WriteObject(const JsonObject: TJSONObject; const Builder: TStringBuilder; const IsTopLevel: Boolean);
begin
  Builder.Append(ObjectStart);

  var IsFirst := True;
  for var Key in SortedKeys(JsonObject) do
  begin
    const IsToken = (IsTopLevel and (Key = TokenKey));
    if IsToken then
      Continue;

    if not IsFirst then
      Builder.Append(Separator);
    IsFirst := False;

    WriteKey(Key, Builder);
    WriteValue(JsonObject.GetValue(Key), Builder);
  end;

  Builder.Append(ObjectEnd);
end;

class procedure TConfirmationArguments.WriteKey(const Key: string; const Builder: TStringBuilder);
begin
  const KeyJson = TJSONString.Create(Key);
  try
    Builder.Append(KeyJson.ToJSON);
  finally
    KeyJson.Free;
  end;

  Builder.Append(KeyValueSeparator);
end;

class procedure TConfirmationArguments.WriteArray(const JsonArray: TJSONArray; const Builder: TStringBuilder);
begin
  Builder.Append(ArrayStart);

  var IsFirst := True;
  for var Item in JsonArray do
  begin
    if not IsFirst then
      Builder.Append(Separator);
    IsFirst := False;

    WriteValue(Item, Builder);
  end;

  Builder.Append(ArrayEnd);
end;

class function TConfirmationArguments.SortedKeys(const JsonObject: TJSONObject): TArray<string>;
begin
  const Keys = TCollections.CreateList<string>(TComparer<string>.Construct(CompareStr));
  for var Pair in JsonObject do
  begin
    Keys.Add(Pair.JsonString.Value);
  end;

  Keys.Sort;
  Result := Keys.ToArray;
end;

end.
