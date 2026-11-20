unit MicrosoftMcp.Tools.People.Relevant;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.People.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TPeopleRelevantTool = class(TMicrosoftTool<TPeopleRelevantParams, TPeopleResponse>)
  protected
    function Run(const Params: TPeopleRelevantParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPeopleResponse; override;

  public
    const ToolName = 'people_relevant';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MSGraph.Graph.People.Interfaces,
  MSGraph.Graph.People,
  MicrosoftMcp.Tools.Account.Support;

const
  DefaultTop = 20;
  MaximumTop = 100;

resourcestring
  ToolDescription = 'Lists the people the account works with most, most relevant first. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TPeopleRelevantTool }

constructor TPeopleRelevantTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TPeopleRelevantTool.Run(const Params: TPeopleRelevantParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TPeopleResponse;
begin
  var Top := Params.Top;
  if Top < 1 then
    Top := DefaultTop;

  if Top > MaximumTop then
    Top := MaximumTop;

  TAccountSupport.UseOwnAccount(Graph);
  const Client: IPeopleClient = TPeopleClient.Create(Graph, False);
  const People = Client.GetRelevantPeople(Top);

  Result := TPeopleResponse.From(People, TAccountSupport.Note(Mailbox));
end;

end.
