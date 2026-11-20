unit MicrosoftMcp.Tools.Base;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.Support,
  MicrosoftMcp.Tools.GraphId;

// The parameter classes and the generic tool bases belong together: each tool derives from one base and one
// parameter class, so they share this unit.

type
  // For a tool without parameters.
  TNoToolParams = class
  end;

  TMicrosoftToolParams = class
  private
    FMailbox: string;

  public
    [SchemaDescription('Short name of the mailbox, see list_mailboxes')]
    property Mailbox: string read FMailbox write FMailbox;
  end;

  TConfirmableToolParams = class(TMicrosoftToolParams)
  private
    FConfirmationToken: string;

  public
    [Optional]
    [SchemaName('confirmation_token')]
    [SchemaDescription('Leave empty on the first call. The answer then holds a summary and a confirmation_token; after the user approved, ' +
                       'call again with the same arguments plus that token')]
    property ConfirmationToken: string read FConfirmationToken write FConfirmationToken;
  end;

  // Takes the user from the request and turns every failure into a tool error (isError) with a message for Claude.
  TMicrosoftToolBase<TParams, TResponse: class, constructor> = class(TMCPToolBase<TParams, TResponse>)
  protected
    FServices: IToolServices;

    function ExecuteWithContext(const Params: TParams; const Context: IMCPRequestContext): TValue; override;
    function Perform(const Params: TParams; const UserId: string): TValue; virtual; abstract;

    // For tools that change something; MCP treats a tool without hints as destructive and open-world.
    procedure MarkChanging(const IsDestructive, IsOpenWorld: Boolean);

  public
    constructor Create(const Services: IToolServices); reintroduce;
  end;

  // A tool without a mailbox parameter, such as list_mailboxes and mailbox_add.
  TMicrosoftUserTool<TParams, TResponse: class, constructor> = class(TMicrosoftToolBase<TParams, TResponse>)
  protected
    function Perform(const Params: TParams; const UserId: string): TValue; override;
    function Run(const Params: TParams; const UserId: string): TResponse; virtual; abstract;
  end;

  // A tool on one mailbox of the user: resolves the short name and hands Run a Graph client for that mailbox.
  TMicrosoftTool<TParams: TMicrosoftToolParams, constructor; TResponse: class, constructor> = class(TMicrosoftToolBase<TParams, TResponse>)
  protected
    function Perform(const Params: TParams; const UserId: string): TValue; override;
    function PerformOnMailbox(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue; virtual;
    function RunWithClient(const Params: TParams; const Mailbox: TResolvedMailbox): TValue;

    // The client is owned by the base and freed after Run. A tool derives from this one or overrides RunValue.
    function Run(const Params: TParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TResponse; virtual;

    // For a tool whose answer is not just structured content, such as one that returns an embedded resource.
    function RunValue(const Params: TParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue; virtual;
  end;

  // A mailbox tool that changes or sends something. Without a valid confirmation_token it only answers
  // {"confirmation_required":true,"summary":...,"confirmation_token":...}; with the token and the same arguments it runs.
  //
  // Its answer has two shapes, so it publishes no output schema: a client checks structured content against it.
  //
  // The token is bound to the user, the tool, the arguments, the mailbox behind the short name and the
  // ConfirmationState, so it does not carry over to another mailbox or to content that changed after the summary.
  TConfirmedMicrosoftTool<TParams: TConfirmableToolParams, constructor; TResponse: class, constructor> = class(TMicrosoftTool<TParams, TResponse>, IMCPTool)
  private
    function ConfirmOrRun(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue;

  protected
    function PerformOnMailbox(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue; override;
    function NeedsConfirmation(const Params: TParams): Boolean; virtual;
    // For a tool that must look at the mailbox to decide, such as calendar_update (does the event have attendees?).
    function NeedsConfirmationIn(const Params: TParams; const Mailbox: TResolvedMailbox): Boolean; virtual;
    function Summarize(const Params: TParams; const Mailbox: TResolvedMailbox): string; virtual; abstract;

    // The state of the object the summary describes, such as the changeKey of a draft. It is read before the summary
    // and again before the action runs; when it differs, the token no longer applies. Empty by default.
    function ConfirmationState(const Params: TParams; const Mailbox: TResolvedMailbox): string; virtual;

  public
    function GetOutputSchema: TJSONObject;
  end;

  // The same two-step confirmation for a tool that must work without resolving the mailbox, such as mailbox_remove.
  TConfirmedMicrosoftUserTool<TParams: TConfirmableToolParams, constructor; TResponse: class, constructor> = class(TMicrosoftUserTool<TParams, TResponse>, IMCPTool)
  protected
    function Perform(const Params: TParams; const UserId: string): TValue; override;
    function NeedsConfirmation(const Params: TParams): Boolean; virtual;
    function Summarize(const Params: TParams; const UserId: string): string; virtual; abstract;

  public
    function GetOutputSchema: TJSONObject;
  end;

implementation

{ TMicrosoftToolBase<TParams, TResponse> }

constructor TMicrosoftToolBase<TParams, TResponse>.Create(const Services: IToolServices);
begin
  inherited Create;

  FServices := Services;
end;

function TMicrosoftToolBase<TParams, TResponse>.ExecuteWithContext(const Params: TParams; const Context: IMCPRequestContext): TValue;
begin
  try
    const UserId = TToolSupport.UserIdOf(Context);
    TGraphIdGuard.Check(Params);
    Result := Perform(Params, UserId);
  except
    on E: Exception do
    begin
      if TToolSupport.IsServerHandled(E) then
        raise;

      Result := TToolSupport.ErrorValue(FServices.Errors, E, Default(TMailbox));
    end;
  end;
end;

procedure TMicrosoftToolBase<TParams, TResponse>.MarkChanging(const IsDestructive, IsOpenWorld: Boolean);
begin
  if not Assigned(FAnnotations) then
    FAnnotations := TJSONObject.Create;

  TToolSupport.MarkChanging(FAnnotations, IsDestructive, IsOpenWorld);
end;

{ TMicrosoftUserTool<TParams, TResponse> }

function TMicrosoftUserTool<TParams, TResponse>.Perform(const Params: TParams; const UserId: string): TValue;
begin
  Result := TToolSupport.ResponseValue(Run(Params, UserId));
end;

{ TMicrosoftTool<TParams, TResponse> }

function TMicrosoftTool<TParams, TResponse>.Perform(const Params: TParams; const UserId: string): TValue;
begin
  const Mailbox = FServices.Resolver.Resolve(UserId, Params.Mailbox);
  Result := PerformOnMailbox(Params, Mailbox, UserId);
end;

function TMicrosoftTool<TParams, TResponse>.PerformOnMailbox(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue;
begin
  try
    Result := RunWithClient(Params, Mailbox);
  except
    on E: Exception do
    begin
      if TToolSupport.IsServerHandled(E) then
        raise;

      Result := TToolSupport.ErrorValue(FServices.Errors, E, Mailbox.Mailbox);
    end;
  end;
end;

function TMicrosoftTool<TParams, TResponse>.RunWithClient(const Params: TParams; const Mailbox: TResolvedMailbox): TValue;
begin
  const Graph = FServices.GraphClients.Create(Mailbox);
  try
    Result := RunValue(Params, Mailbox, Graph);
  finally
    Graph.Free;
  end;
end;

function TMicrosoftTool<TParams, TResponse>.Run(const Params: TParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TResponse;
begin
  Result := nil;
end;

function TMicrosoftTool<TParams, TResponse>.RunValue(const Params: TParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue;
begin
  Result := TToolSupport.ResponseValue(Run(Params, Mailbox, Graph));
end;

{ TConfirmedMicrosoftTool<TParams, TResponse> }

function TConfirmedMicrosoftTool<TParams, TResponse>.PerformOnMailbox(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue;
begin
  // The reads before the confirmation fail like the action itself, with the context of this mailbox.
  try
    Result := ConfirmOrRun(Params, Mailbox, UserId);
  except
    on E: Exception do
    begin
      if TToolSupport.IsServerHandled(E) then
        raise;

      Result := TToolSupport.ErrorValue(FServices.Errors, E, Mailbox.Mailbox);
    end;
  end;
end;

function TConfirmedMicrosoftTool<TParams, TResponse>.ConfirmOrRun(const Params: TParams; const Mailbox: TResolvedMailbox; const UserId: string): TValue;
begin
  const State = ConfirmationState(Params, Mailbox);
  const BindingHash = TToolSupport.ConfirmationHash(Params, Mailbox.Mailbox, State);

  // A token is only ever issued for a call that needed confirmation, so a valid one makes the check below unnecessary.
  const HasToken = not Params.ConfirmationToken.IsEmpty;
  if HasToken and FServices.Confirmations.TryRedeem(UserId, FName, BindingHash, Params.ConfirmationToken) then
    Exit(inherited PerformOnMailbox(Params, Mailbox, UserId));

  if not NeedsConfirmationIn(Params, Mailbox) then
    Exit(inherited PerformOnMailbox(Params, Mailbox, UserId));

  const Summary = Summarize(Params, Mailbox);
  const Token = FServices.Confirmations.Issue(UserId, FName, BindingHash, Summary);

  Result := TToolSupport.ConfirmationValue(Summary, Token, HasToken);
end;

function TConfirmedMicrosoftTool<TParams, TResponse>.NeedsConfirmation(const Params: TParams): Boolean;
begin
  Result := True;
end;

function TConfirmedMicrosoftTool<TParams, TResponse>.NeedsConfirmationIn(const Params: TParams; const Mailbox: TResolvedMailbox): Boolean;
begin
  Result := NeedsConfirmation(Params);
end;

function TConfirmedMicrosoftTool<TParams, TResponse>.ConfirmationState(const Params: TParams; const Mailbox: TResolvedMailbox): string;
begin
  Result := '';
end;

function TConfirmedMicrosoftTool<TParams, TResponse>.GetOutputSchema: TJSONObject;
begin
  Result := nil;
end;

{ TConfirmedMicrosoftUserTool<TParams, TResponse> }

function TConfirmedMicrosoftUserTool<TParams, TResponse>.Perform(const Params: TParams; const UserId: string): TValue;
begin
  if not NeedsConfirmation(Params) then
    Exit(inherited Perform(Params, UserId));

  const ArgumentsHash = TToolSupport.ArgumentsHash(Params);
  const IsConfirmed = FServices.Confirmations.TryRedeem(UserId, FName, ArgumentsHash, Params.ConfirmationToken);
  if IsConfirmed then
    Exit(inherited Perform(Params, UserId));

  const Summary = Summarize(Params, UserId);
  const Token = FServices.Confirmations.Issue(UserId, FName, ArgumentsHash, Summary);
  const HadToken = not Params.ConfirmationToken.IsEmpty;

  Result := TToolSupport.ConfirmationValue(Summary, Token, HadToken);
end;

function TConfirmedMicrosoftUserTool<TParams, TResponse>.NeedsConfirmation(const Params: TParams): Boolean;
begin
  Result := True;
end;

function TConfirmedMicrosoftUserTool<TParams, TResponse>.GetOutputSchema: TJSONObject;
begin
  Result := nil;
end;

end.
