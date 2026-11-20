unit MicrosoftMcp.Tools.Mail.Support;

interface

uses
  System.SysUtils,
  MSGraph.Graph.Http,
  MSGraph.Graph.Mail.Types,
  MSGraph.Graph.Mail.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Graph.ClientFactory.Interfaces;

type
  // Helpers the mail tools share: the Microsoft365-4D client, folder names, and the texts of the confirmation summaries.
  TMailSupport = class
  private
    class function WellKnownFolder(const Name: string; out GraphName: string): Boolean; static;
    class function Join(const Values: TArray<string>): string; static;

  public
    const HtmlBodyType = 'html';

    class function Client(const Graph: TGraphHttpClient): IMailClient; static;

    // inbox, archive, deleteditems, junkemail, drafts and sentitems are Graph's well-known names; anything else is a folder id.
    class function FolderId(const Folder: string): string; static;

    // A value of the top parameter, kept between 1 and 100; 0 (not given) becomes the default of 25.
    class function ClampTop(const Top: Integer): Integer; static;

    class function FormatAddress(const Address: TEmailAddress): string; static;
    class function FormatAddresses(const Addresses: TArray<TEmailAddress>): string; static;
    class function AddressesOf(const Addresses: TArray<TEmailAddress>): TArray<string>; static;

    // Removes blanks and empty entries.
    class function CleanRecipients(const Recipients: TArray<string>): TArray<string>; static;
    class function RequireRecipients(const Recipients: TArray<string>): TArray<string>; static;

    // For the summaries of confirmed tools: reads the message the confirmation is about.
    class function LoadMessage(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const MessageId: string): TMailMessage; static;

    class function MailboxLabel(const Resolved: TResolvedMailbox): string; static;
    class function RecipientsText(const ToRecipients, CcRecipients, BccRecipients: TArray<string>): string; static;
  end;

implementation

uses
  MSGraph.Graph.Mail,
  MicrosoftMcp.Tools.Exceptions;

const
  DefaultTop = 25;
  MaximumTop = 100;

resourcestring
  NoRecipients = 'At least one recipient is needed.';
  MailboxLabelFormat = '"%s" (%s)';
  NoRecipientsText = '(no recipients)';
  CcText = ', cc %s';
  BccText = ', bcc %s';
  AddressFormat = '%s <%s>';

{ TMailSupport }

class function TMailSupport.Client(const Graph: TGraphHttpClient): IMailClient;
begin
  Result := TMailClient.Create(Graph, False);
end;

class function TMailSupport.FolderId(const Folder: string): string;
begin
  const Trimmed = Folder.Trim;

  var GraphName: string;
  if WellKnownFolder(Trimmed, GraphName) then
    Result := GraphName
  else
    Result := Trimmed;
end;

class function TMailSupport.WellKnownFolder(const Name: string; out GraphName: string): Boolean;
begin
  const Names: TArray<string> = ['inbox', 'archive', 'deleteditems', 'junkemail', 'drafts', 'sentitems'];

  GraphName := '';
  for var KnownName in Names do
  begin
    if SameText(Name, KnownName) then
    begin
      GraphName := KnownName;
      Exit(True);
    end;
  end;

  Result := False;
end;

class function TMailSupport.ClampTop(const Top: Integer): Integer;
begin
  if Top < 1 then
    Exit(DefaultTop);

  Result := Top;
  if Result > MaximumTop then
    Result := MaximumTop;
end;

class function TMailSupport.FormatAddress(const Address: TEmailAddress): string;
begin
  const HasName = ((not Address.Name.IsEmpty) and (not SameText(Address.Name, Address.Address)));
  if HasName then
    Result := Format(AddressFormat, [Address.Name, Address.Address])
  else
    Result := Address.Address;
end;

class function TMailSupport.FormatAddresses(const Addresses: TArray<TEmailAddress>): string;
begin
  var Formatted: TArray<string> := [];
  for var Address in Addresses do
  begin
    Formatted := Formatted + [FormatAddress(Address)];
  end;

  Result := Join(Formatted);
end;

class function TMailSupport.AddressesOf(const Addresses: TArray<TEmailAddress>): TArray<string>;
begin
  Result := [];
  for var Address in Addresses do
  begin
    Result := Result + [Address.Address];
  end;
end;

class function TMailSupport.CleanRecipients(const Recipients: TArray<string>): TArray<string>;
begin
  Result := [];
  for var Recipient in Recipients do
  begin
    const Trimmed = Recipient.Trim;
    if not Trimmed.IsEmpty then
      Result := Result + [Trimmed];
  end;
end;

class function TMailSupport.RequireRecipients(const Recipients: TArray<string>): TArray<string>;
begin
  Result := CleanRecipients(Recipients);
  if Length(Result) = 0 then
    raise EToolArgumentError.Create(NoRecipients);
end;

class function TMailSupport.LoadMessage(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const MessageId: string): TMailMessage;
begin
  const Graph = GraphClients.Create(Mailbox);
  try
    Result := Client(Graph).GetMessage(MessageId, TMailBodyFormat.Text);
  finally
    Graph.Free;
  end;
end;

class function TMailSupport.MailboxLabel(const Resolved: TResolvedMailbox): string;
begin
  var Address := Resolved.Mailbox.Address;
  if Address.IsEmpty then
    Address := Resolved.Account.UserName;

  Result := Format(MailboxLabelFormat, [Resolved.Mailbox.Slug, Address]);
end;

class function TMailSupport.RecipientsText(const ToRecipients, CcRecipients, BccRecipients: TArray<string>): string;
begin
  Result := Join(CleanRecipients(ToRecipients));
  if Result.IsEmpty then
    Result := NoRecipientsText;

  const Cc = Join(CleanRecipients(CcRecipients));
  if not Cc.IsEmpty then
    Result := Result + Format(CcText, [Cc]);

  const Bcc = Join(CleanRecipients(BccRecipients));
  if not Bcc.IsEmpty then
    Result := Result + Format(BccText, [Bcc]);
end;

class function TMailSupport.Join(const Values: TArray<string>): string;
begin
  Result := string.Join(', ', Values);
end;

end.
