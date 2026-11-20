unit MicrosoftMcp.Tools.Contacts.Delete;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Contacts.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TContactsDeleteTool = class(TConfirmedMicrosoftTool<TConfirmedContactIdParams, TContactActionResponse>)
  protected
    function Summarize(const Params: TConfirmedContactIdParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TConfirmedContactIdParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse; override;

  public
    const ToolName = 'contacts_delete';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support,
  MicrosoftMcp.Tools.Contacts.Support;

resourcestring
  ToolDescription = 'Deletes a contact from a mailbox. It needs confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Delete the contact %s from mailbox %s.';
  DeletedStatus = 'deleted';

{ TContactsDeleteTool }

constructor TContactsDeleteTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TContactsDeleteTool.Summarize(const Params: TConfirmedContactIdParams; const Mailbox: TResolvedMailbox): string;
begin
  const Contact = TContactsSupport.LoadContact(FServices.GraphClients, Mailbox, Params.ContactId);

  Result := Format(SummaryFormat, [TContactsSupport.ContactText(Contact), TMailSupport.MailboxLabel(Mailbox)]);
end;

function TContactsDeleteTool.Run(const Params: TConfirmedContactIdParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TContactActionResponse;
begin
  TContactsSupport.Client(Graph).DeleteContact(Params.ContactId);

  Result := TContactActionResponse.Done(DeletedStatus, Params.ContactId, '');
end;

end.
