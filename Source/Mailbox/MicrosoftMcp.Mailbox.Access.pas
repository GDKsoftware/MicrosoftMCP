unit MicrosoftMcp.Mailbox.Access;

interface

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Access.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces,
  MicrosoftMcp.Graph.Errors;

type
  // GET /me/mailFolders/inbox for an own mailbox, /users/{address}/mailFolders/inbox for a shared one.
  TMailboxAccess = class(TInterfacedObject, IMailboxAccess)
  private
    FGraphClients: IGraphClientFactory;
    FErrors: TGraphErrorTranslator;

    function ReadInbox(const Mailbox: TMailbox; const AccessToken: string): TMailboxAccessResult;
    function Refused(const Message: string): TMailboxAccessResult;

  public
    // Errors is owned by the caller and must outlive this object.
    constructor Create(const GraphClients: IGraphClientFactory; const Errors: TGraphErrorTranslator);

    function Check(const Mailbox: TMailbox; const AccessToken: string): TMailboxAccessResult;
  end;

implementation

uses
  System.JSON,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

const
  InboxPathFormat = '%s/mailFolders/inbox';
  InboxQuery = '$select=id';

{ TMailboxAccess }

constructor TMailboxAccess.Create(const GraphClients: IGraphClientFactory; const Errors: TGraphErrorTranslator);
begin
  inherited Create;

  FGraphClients := GraphClients;
  FErrors := Errors;
end;

function TMailboxAccess.Check(const Mailbox: TMailbox; const AccessToken: string): TMailboxAccessResult;
begin
  try
    Result := ReadInbox(Mailbox, AccessToken);
  except
    on E: Exception do
    begin
      Result := Refused(FErrors.Translate(E, Mailbox));
    end;
  end;
end;

function TMailboxAccess.ReadInbox(const Mailbox: TMailbox; const AccessToken: string): TMailboxAccessResult;
begin
  var Resolved := Default(TResolvedMailbox);
  Resolved.Mailbox := Mailbox;
  Resolved.AccessToken := AccessToken;

  const Client = FGraphClients.Create(Resolved);
  try
    const InboxPath = Format(InboxPathFormat, [Client.GetUserPrefix]);
    const Inbox = Client.Get(InboxPath, InboxQuery);
    try
      var Message: string;
      const IsError = FErrors.TryTranslateErrorObject(Inbox, Mailbox, Message);
      if IsError then
        Exit(Refused(Message));
    finally
      Inbox.Free;
    end;
  finally
    Client.Free;
  end;

  Result := Default(TMailboxAccessResult);
  Result.IsAccessible := True;
end;

function TMailboxAccess.Refused(const Message: string): TMailboxAccessResult;
begin
  Result := Default(TMailboxAccessResult);
  Result.IsAccessible := False;
  Result.Message := Message;
end;

end.
