unit MicrosoftMcp.Tools.Contacts.Search;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Contacts.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TContactsSearchParams = class(TMicrosoftToolParams)
  private
    FQuery: string;
    FTop: Integer;

  public
    [Optional]
    [SchemaDescription('Text to search for in names, e-mail addresses and companies; empty lists the contacts by name')]
    property Query: string read FQuery write FQuery;

    [Optional]
    [SchemaDescription('Number of contacts to return, default 25, at most 100')]
    property Top: Integer read FTop write FTop;
  end;

  TContactsSearchTool = class(TMicrosoftTool<TContactsSearchParams, TContactsSearchResponse>)
  protected
    function Run(const Params: TContactsSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactsSearchResponse; override;

  public
    const ToolName = 'contacts_search';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Contacts.Support;

resourcestring
  ToolDescription = 'Searches the contacts of a mailbox by name, e-mail address or company.';

{ TContactsSearchTool }

constructor TContactsSearchTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TContactsSearchTool.Run(const Params: TContactsSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactsSearchResponse;
begin
  const Contacts = TContactsSupport.Client(Graph).SearchContacts(Params.Query, TMailSupport.ClampTop(Params.Top));

  Result := TContactsSearchResponse.From(Contacts);
end;

end.
