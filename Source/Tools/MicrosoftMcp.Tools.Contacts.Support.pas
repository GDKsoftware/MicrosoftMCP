unit MicrosoftMcp.Tools.Contacts.Support;

interface

uses
  MSGraph.Graph.Http,
  MSGraph.Graph.Contacts.Types,
  MSGraph.Graph.Contacts.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces;

type
  // Helpers the contact tools share: the Microsoft365-4D client and the contact the confirmation summaries talk about.
  TContactsSupport = class
  public
    class function Client(const Graph: TGraphHttpClient): IContactsClient; static;

    class function LoadContact(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const ContactId: string): TContact; static;

    // A name and e-mail address for a summary.
    class function ContactText(const Contact: TContact): string; static;
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Contacts;

resourcestring
  ContactWithEmailFormat = '"%s" <%s>';
  ContactFormat = '"%s"';

{ TContactsSupport }

class function TContactsSupport.Client(const Graph: TGraphHttpClient): IContactsClient;
begin
  Result := TContactsClient.Create(Graph, False);
end;

class function TContactsSupport.LoadContact(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const ContactId: string): TContact;
begin
  const Graph = GraphClients.Create(Mailbox);
  try
    Result := Client(Graph).GetContact(ContactId);
  finally
    Graph.Free;
  end;
end;

class function TContactsSupport.ContactText(const Contact: TContact): string;
begin
  if Contact.Email.IsEmpty then
    Result := Format(ContactFormat, [Contact.DisplayName])
  else
    Result := Format(ContactWithEmailFormat, [Contact.DisplayName, Contact.Email]);
end;

end.
