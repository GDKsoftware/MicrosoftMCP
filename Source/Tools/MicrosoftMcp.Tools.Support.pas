unit MicrosoftMcp.Tools.Support;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.JSON,
  MCPServer.Types,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Graph.Errors;

type
  // The non-generic work of the tool base classes. A method of a generic class may not use symbols from the
  // implementation section of its own unit, so this logic lives in a class of its own.
  TToolSupport = class
  private
    class function ErrorMessage(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox): string; static;
    class procedure SetHint(const Annotations: TJSONObject; const Name: string; const Value: Boolean); static;

  public
    // The user comes from the principal of the request (the sub of the introspected token), never from a parameter.
    class function UserIdOf(const Context: IMCPRequestContext): string; static;

    // Exceptions the MCP server handles itself: protocol errors, cancellation, input requests and invalid arguments.
    class function IsServerHandled(const E: Exception): Boolean; static;

    // A tool result with isError and a message for Claude. An unexpected failure is logged with the tool and the
    // exception class only, never its message, which may hold mail content.
    class function ErrorValue(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox; const ToolName: string): TValue; static;

    // Serializes the response as structured content and frees it.
    class function ResponseValue(const Response: TObject): TValue; static;

    // The hash of the arguments as the tool received them, without confirmation_token and with sorted keys.
    class function ArgumentsHash(const Params: TObject): string; static;

    // The arguments hash extended with the mailbox behind the short name (account and address) and a state of the
    // object that the confirmation is about.
    class function ConfirmationHash(const Params: TObject; const Mailbox: TMailbox; const State: string): string; static;

    class function ConfirmationValue(const Summary, Token: string; const IsEarlierTokenRejected: Boolean): TValue; static;

    // A query for $search="...": Microsoft365-4D puts it between double quotes without escaping, so a quote in the
    // query would end the phrase early and Graph answers 400.
    class function SearchPhrase(const Query: string): string; static;

    // A value for an OData string literal ('...'), such as search(q='...'): a single quote is written twice.
    class function ODataString(const Value: string): string; static;

    // Sets readOnlyHint false and the given destructiveHint and openWorldHint; MCP assumes true for both when absent.
    class procedure MarkChanging(const Annotations: TJSONObject; const IsDestructive, IsOpenWorld: Boolean); static;
  end;

implementation

uses
  MCPServer.Errors,
  MCPServer.Logger,
  MCPServer.Mrtr,
  MCPServer.Serializer,
  MCPServer.Tool.Result,
  MicrosoftMcp.Confirm.Arguments,
  MicrosoftMcp.Tools.Exceptions;

const
  ConfirmationRequiredMember = 'confirmation_required';
  SummaryMember = 'summary';
  ConfirmationTokenMember = 'confirmation_token';
  NextStepMember = 'next_step';
  NoteMember = 'note';
  // Starts with characters a parameter name cannot have, so it never collides with an argument.
  BindingMember = '$binding';
  AccountKeyMember = 'account_key';
  AddressMember = 'address';
  StateMember = 'state';
  ReadOnlyHint = 'readOnlyHint';
  DestructiveHint = 'destructiveHint';
  OpenWorldHint = 'openWorldHint';
  Backslash = '\';
  EscapedBackslash = '\\';
  DoubleQuote = '"';
  EscapedDoubleQuote = '\"';
  SingleQuote = '''';
  DoubledSingleQuote = '''''';

resourcestring
  NoUser = 'This tool needs a signed-in user, but the request carries none.';
  NextStep = 'Nothing has been done yet. Show the summary to the user and ask for approval. Only after the user agrees, ' +
             'call this tool again with exactly the same arguments plus confirmation_token. The token is valid for 10 minutes and works once.';
  TokenRejected = 'The confirmation_token that was passed is not valid: it was used before (also when that attempt failed), ' +
                  'expired, or was issued for other arguments or for an item that changed since. This is a new one.';
  NoResponse = 'The tool returned no response.';
  ToolFailedFormat = 'Tool %s failed: %s';

{ TToolSupport }

class function TToolSupport.UserIdOf(const Context: IMCPRequestContext): string;
begin
  Result := '';
  if Assigned(Context) then
    Result := Context.GetPrincipal;

  if Result.IsEmpty then
    raise EToolNoUser.Create(NoUser);
end;

class function TToolSupport.IsServerHandled(const E: Exception): Boolean;
begin
  Result := ((E is EMCPError) or
             (E is EMCPRequestCancelled) or
             (E is EMCPInputRequired) or
             (E is EArgumentException));
end;

class function TToolSupport.ErrorValue(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox; const ToolName: string): TValue;
begin
  const IsUnexpected = ((not (E is EToolError)) and Errors.IsUnexpected(E));
  if IsUnexpected then
    TLogger.Warning(ToolFailedFormat, [ToolName, E.ClassName]);

  const ToolResult = TMCPToolResult.Error(ErrorMessage(Errors, E, Mailbox));
  Result := TValue.From<TMCPToolResult>(ToolResult);
end;

class function TToolSupport.ErrorMessage(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox): string;
begin
  if E is EToolError then
    Result := E.Message
  else
    Result := Errors.Translate(E, Mailbox);
end;

class function TToolSupport.ResponseValue(const Response: TObject): TValue;
begin
  if not Assigned(Response) then
    raise EToolError.Create(NoResponse);

  try
    const Json = TJSONObject.Create;
    try
      TMCPSerializer.Serialize(Response, Json);
    except
      Json.Free;
      raise;
    end;

    Result := TValue.From<TJSONObject>(Json);
  finally
    Response.Free;
  end;
end;

class function TToolSupport.ArgumentsHash(const Params: TObject): string;
begin
  const Arguments = TJSONObject.Create;
  try
    TMCPSerializer.Serialize(Params, Arguments);
    Result := TConfirmationArguments.Hash(Arguments);
  finally
    Arguments.Free;
  end;
end;

class function TToolSupport.ConfirmationHash(const Params: TObject; const Mailbox: TMailbox; const State: string): string;
begin
  const Arguments = TJSONObject.Create;
  try
    TMCPSerializer.Serialize(Params, Arguments);

    const Binding = TJSONObject.Create;
    Arguments.AddPair(BindingMember, Binding);
    Binding.AddPair(AccountKeyMember, Mailbox.AccountKey);
    Binding.AddPair(AddressMember, Mailbox.Address.ToLower);
    Binding.AddPair(StateMember, State);

    Result := TConfirmationArguments.Hash(Arguments);
  finally
    Arguments.Free;
  end;
end;

class function TToolSupport.ConfirmationValue(const Summary, Token: string; const IsEarlierTokenRejected: Boolean): TValue;
begin
  const Json = TJSONObject.Create;
  Json.AddPair(ConfirmationRequiredMember, TJSONBool.Create(True));
  Json.AddPair(SummaryMember, Summary);
  Json.AddPair(ConfirmationTokenMember, Token);
  Json.AddPair(NextStepMember, NextStep);

  if IsEarlierTokenRejected then
    Json.AddPair(NoteMember, TokenRejected);

  Result := TValue.From<TJSONObject>(Json);
end;

class function TToolSupport.SearchPhrase(const Query: string): string;
begin
  Result := Query.Replace(Backslash, EscapedBackslash, [rfReplaceAll]).Replace(DoubleQuote, EscapedDoubleQuote, [rfReplaceAll]);
end;

class function TToolSupport.ODataString(const Value: string): string;
begin
  Result := Value.Replace(SingleQuote, DoubledSingleQuote, [rfReplaceAll]);
end;

class procedure TToolSupport.MarkChanging(const Annotations: TJSONObject; const IsDestructive, IsOpenWorld: Boolean);
begin
  SetHint(Annotations, ReadOnlyHint, False);
  SetHint(Annotations, DestructiveHint, IsDestructive);
  SetHint(Annotations, OpenWorldHint, IsOpenWorld);
end;

class procedure TToolSupport.SetHint(const Annotations: TJSONObject; const Name: string; const Value: Boolean);
begin
  Annotations.RemovePair(Name).Free;
  Annotations.AddPair(Name, TJSONBool.Create(Value));
end;

end.
