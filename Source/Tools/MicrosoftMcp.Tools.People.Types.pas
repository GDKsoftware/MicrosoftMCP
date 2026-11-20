unit MicrosoftMcp.Tools.People.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.People.Types,
  MicrosoftMcp.Tools.Base;

type
  TPersonItem = record
    Id: string;

    [SchemaName('display_name')]
    DisplayName: string;

    Email: string;

    [SchemaName('relevance_score')]
    RelevanceScore: Double;

    class function FromPerson(const Person: TPerson): TPersonItem; static;
  end;

  TPeopleResponse = class
  private
    FPeople: TArray<TPersonItem>;
    FNote: string;

  public
    property People: TArray<TPersonItem> read FPeople write FPeople;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const People: TArray<TPerson>; const Note: string): TPeopleResponse; static;
  end;

  TPeopleSearchParams = class(TMicrosoftToolParams)
  private
    FQuery: string;
    FTop: Integer;

  public
    [SchemaDescription('Name or e-mail address (part) of the person to look for')]
    property Query: string read FQuery write FQuery;

    [Optional]
    [SchemaDescription('Number of people to return, default 10, at most 50')]
    property Top: Integer read FTop write FTop;
  end;

  TPeopleRelevantParams = class(TMicrosoftToolParams)
  private
    FTop: Integer;

  public
    [Optional]
    [SchemaDescription('Number of people to return, default 20, at most 100')]
    property Top: Integer read FTop write FTop;
  end;

implementation

{ TPersonItem }

class function TPersonItem.FromPerson(const Person: TPerson): TPersonItem;
begin
  Result.Id             := Person.Id;
  Result.DisplayName    := Person.DisplayName;
  Result.Email          := Person.EmailAddress;
  Result.RelevanceScore := Person.RelevanceScore;
end;

{ TPeopleResponse }

class function TPeopleResponse.From(const People: TArray<TPerson>; const Note: string): TPeopleResponse;
begin
  Result := TPeopleResponse.Create;

  var Items: TArray<TPersonItem> := [];
  for var Person in People do
  begin
    Items := Items + [TPersonItem.FromPerson(Person)];
  end;

  Result.People := Items;
  Result.Note := Note;
end;

end.
