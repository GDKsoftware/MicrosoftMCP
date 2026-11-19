unit MicrosoftMcp.Graph.ClientFactory;

interface

uses
  MSGraph.Graph.Http,
  MSGraph.Graph.Http.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces;

type
  TGraphClientFactory = class(TInterfacedObject, IGraphClientFactory)
  private
    FTransport: IGraphHttpTransport;

  public
    constructor Create; overload;
    constructor Create(const Transport: IGraphHttpTransport); overload;

    function CreateClient(const Resolved: TResolvedMailbox): TGraphHttpClient;
    function IGraphClientFactory.Create = CreateClient;
  end;

implementation

uses
  MicrosoftMcp.Mailbox.Types;

{ TGraphClientFactory }

constructor TGraphClientFactory.Create;
begin
  inherited Create;
end;

constructor TGraphClientFactory.Create(const Transport: IGraphHttpTransport);
begin
  inherited Create;

  FTransport := Transport;
end;

function TGraphClientFactory.CreateClient(const Resolved: TResolvedMailbox): TGraphHttpClient;
begin
  const HasTransport = Assigned(FTransport);
  if HasTransport then
    Result := TGraphHttpClient.Create(Resolved.AccessToken, FTransport)
  else
    Result := TGraphHttpClient.Create(Resolved.AccessToken);

  const IsShared = (Resolved.Mailbox.Kind = TMailboxKind.Shared);
  if IsShared then
    Result.MailboxAddress := Resolved.Mailbox.Address;
end;

end.
