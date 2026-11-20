unit MicrosoftMcp.Tools.Contacts.Create;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Contacts.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TContactsCreateTool = class(TMicrosoftTool<TContactFieldsParams, TContactActionResponse>)
  protected
    function Run(const Params: TContactFieldsParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse; override;

  public
    const ToolName = 'contacts_create';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Contacts.Support;

resourcestring
  ToolDescription = 'Creates a contact in a mailbox. Give at least a given name, a surname or an e-mail address.';
  NothingToCreate = 'Give at least given_name, surname or email to create a contact.';
  CreatedStatus = 'created';

{ TContactsCreateTool }

constructor TContactsCreateTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TContactsCreateTool.Run(const Params: TContactFieldsParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse;
begin
  const HasIdentity = not (Params.GivenName.Trim.IsEmpty and Params.Surname.Trim.IsEmpty and Params.Email.Trim.IsEmpty);
  if not HasIdentity then
    raise EToolArgumentError.Create(NothingToCreate);

  const Created = TContactsSupport.Client(Graph).CreateContact(Params.GivenName, Params.Surname, Params.Email, Params.Phone, Params.Company, Params.JobTitle);

  Result := TContactActionResponse.Done(CreatedStatus, Created.Id, Created.DisplayName);
end;

end.
