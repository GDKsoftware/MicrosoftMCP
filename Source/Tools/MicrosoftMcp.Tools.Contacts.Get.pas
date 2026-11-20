unit MicrosoftMcp.Tools.Contacts.Get;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Contacts.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TContactsGetTool = class(TMicrosoftTool<TContactIdParams, TContactDetailResponse>)
  protected
    function Run(const Params: TContactIdParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactDetailResponse; override;

  public
    const ToolName = 'contacts_get';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Contacts.Support;

resourcestring
  ToolDescription = 'Reads one contact of a mailbox with all its details.';

{ TContactsGetTool }

constructor TContactsGetTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TContactsGetTool.Run(const Params: TContactIdParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactDetailResponse;
begin
  const Contact = TContactsSupport.Client(Graph).GetContact(Params.ContactId);

  Result := TContactDetailResponse.From(Contact);
end;

end.
