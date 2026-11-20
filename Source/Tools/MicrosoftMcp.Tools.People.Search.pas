unit MicrosoftMcp.Tools.People.Search;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.People.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TPeopleSearchTool = class(TMicrosoftTool<TPeopleSearchParams, TPeopleResponse>)
  protected
    function Run(const Params: TPeopleSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPeopleResponse; override;

  public
    const ToolName = 'people_search';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Support,
  MSGraph.Graph.People.Interfaces,
  MSGraph.Graph.People,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support;

const
  DefaultTop = 10;
  MaximumTop = 50;

resourcestring
  ToolDescription = 'Searches the people around the account (colleagues and frequent contacts) by name or e-mail address. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  QueryMissing = 'Give a name or e-mail address in query.';

{ TPeopleSearchTool }

constructor TPeopleSearchTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TPeopleSearchTool.Run(const Params: TPeopleSearchParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPeopleResponse;
begin
  if Params.Query.Trim.IsEmpty then
    raise EToolArgumentError.Create(QueryMissing);

  var Top := Params.Top;
  if Top < 1 then
    Top := DefaultTop;

  if Top > MaximumTop then
    Top := MaximumTop;

  TAccountSupport.UseOwnAccount(Graph);
  const Client: IPeopleClient = TPeopleClient.Create(Graph, False);
  const People = Client.SearchPeople(TToolSupport.SearchPhrase(Params.Query), Top);

  Result := TPeopleResponse.From(People, TAccountSupport.Note(Mailbox));
end;

end.
