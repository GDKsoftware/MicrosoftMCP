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

    // A tool result with isError and a message for Claude.
    class function ErrorValue(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox): TValue; static;

    // Serializes the response as structured content and frees it.
    class function ResponseValue(const Response: TObject): TValue; static;

    // The hash of the arguments as the tool received them, without confirmation_token and with sorted keys.
    class function ArgumentsHash(const Params: TObject): string; static;

    class function ConfirmationValue(const Summary, Token: string; const IsEarlierTokenRejected: Boolean): TValue; static;

    // Sets readOnlyHint false and the given destructiveHint and openWorldHint; MCP assumes true for both when absent.
    class procedure MarkChanging(const Annotations: TJSONObject; const IsDestructive, IsOpenWorld: Boolean); static;
  end;

implementation

uses
  MCPServer.Errors,
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
  ReadOnlyHint = 'readOnlyHint';
  DestructiveHint = 'destructiveHint';
  OpenWorldHint = 'openWorldHint';

resourcestring
  NoUser = 'This tool needs a signed-in user, but the request carries none.';
  NextStep = 'Nothing has been done yet. Show the summary to the user and ask for approval. Only after the user agrees, ' +
             'call this tool again with exactly the same arguments plus confirmation_token. The token is valid for 10 minutes and works once.';
  TokenRejected = 'The confirmation_token that was passed is not valid (used, expired or issued for other arguments); this is a new one.';
  NoResponse = 'The tool returned no response.';

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

class function TToolSupport.ErrorValue(const Errors: TGraphErrorTranslator; const E: Exception; const Mailbox: TMailbox): TValue;
begin
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
