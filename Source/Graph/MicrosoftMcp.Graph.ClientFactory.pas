unit MicrosoftMcp.Graph.ClientFactory;

interface

uses
  MSGraph.Graph.Http,
  MSGraph.Graph.Http.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces;

type
  // Every client gets a TRaisingGraphTransport, so an HTTP error of Graph raises EGraphHttpError.
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
  MSGraph.Graph.Http.Transport,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Graph.Transport.Raising;

{ TGraphClientFactory }

constructor TGraphClientFactory.Create;
begin
  Create(TNetHttpTransport.Create);
end;

constructor TGraphClientFactory.Create(const Transport: IGraphHttpTransport);
begin
  inherited Create;

  FTransport := TRaisingGraphTransport.Create(Transport);
end;

function TGraphClientFactory.CreateClient(const Resolved: TResolvedMailbox): TGraphHttpClient;
begin
  Result := TGraphHttpClient.Create(Resolved.AccessToken, FTransport);

  const IsShared = (Resolved.Mailbox.Kind = TMailboxKind.Shared);
  if IsShared then
    Result.MailboxAddress := Resolved.Mailbox.Address;
end;

end.
