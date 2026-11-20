unit MicrosoftMcp.Tools.Contacts.Update;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Contacts.Types,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TContactsUpdateParams = class(TContactFieldsParams)
  private
    FContactId: string;

  public
    [GraphId]
    [SchemaName('contact_id')]
    [SchemaDescription('Id of the contact, from contacts_search')]
    property ContactId: string read FContactId write FContactId;
  end;

  TContactsUpdateTool = class(TMicrosoftTool<TContactsUpdateParams, TContactActionResponse>)
  private
    procedure GuardChanges(const Params: TContactsUpdateParams);
    class function FirstFilled(const Given, Fallback: string): string; static;

  protected
    function Run(const Params: TContactsUpdateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse; override;

  public
    const ToolName = 'contacts_update';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Contacts.Support;

resourcestring
  ToolDescription = 'Changes fields of a contact. Only the fields that are given change; the others stay as they are.';
  NothingToChange = 'Give at least one field to change: given_name, surname, email, phone, company or job_title.';
  UpdatedStatus = 'updated';

{ TContactsUpdateTool }

constructor TContactsUpdateTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TContactsUpdateTool.Run(const Params: TContactsUpdateParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse;
begin
  GuardChanges(Params);

  const Client = TContactsSupport.Client(Graph);

  var GivenName := Params.GivenName;
  var Surname := Params.Surname;

  // The library names an e-mail address "<given name> <surname>", so a new address without the names would blank that name.
  const HasNewEmail = not Params.Email.Trim.IsEmpty;
  if HasNewEmail then
  begin
    const Current = Client.GetContact(Params.ContactId);
    GivenName := FirstFilled(Params.GivenName, Current.GivenName);
    Surname := FirstFilled(Params.Surname, Current.Surname);
  end;

  const Updated = Client.UpdateContact(Params.ContactId, GivenName, Surname, Params.Email, Params.Phone, Params.Company, Params.JobTitle);

  Result := TContactActionResponse.Done(UpdatedStatus, Params.ContactId, Updated.DisplayName);
end;

procedure TContactsUpdateTool.GuardChanges(const Params: TContactsUpdateParams);
begin
  const Fields: TArray<string> = [Params.GivenName, Params.Surname, Params.Email, Params.Phone, Params.Company, Params.JobTitle];

  for var Field in Fields do
  begin
    if not Field.Trim.IsEmpty then
      Exit;
  end;

  raise EToolArgumentError.Create(NothingToChange);
end;

class function TContactsUpdateTool.FirstFilled(const Given, Fallback: string): string;
begin
  if Given.IsEmpty then
    Result := Fallback
  else
    Result := Given;
end;

end.
