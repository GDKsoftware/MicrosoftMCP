unit MicrosoftMcp.Tools.Mail.Support;

interface

uses
  System.SysUtils,
  System.JSON,
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
    class function AddressOf(const Recipient: TJSONValue): TEmailAddress; static;

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

    // Reads the given fields of a message ($select) straight from Graph, for fields that TMailMessage lacks
    // (isDraft, bccRecipients, changeKey). The caller frees the result.
    class function ReadMessageFields(const Graph: TGraphHttpClient; const MessageId, Fields: string): TJSONObject; overload; static;
    class function ReadMessageFields(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const MessageId, Fields: string): TJSONObject; overload; static;

    // The recipients in a recipients array member of a Graph message (toRecipients, ccRecipients, bccRecipients).
    class function RecipientsIn(const Message: TJSONObject; const Member: string): TArray<string>; static;

    class function MailboxLabel(const Resolved: TResolvedMailbox): string; static;
    class function RecipientsText(const ToRecipients, CcRecipients, BccRecipients: TArray<string>): string; static;
  end;

implementation

uses
  System.NetEncoding,
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

const
  MessageEndpointFormat = '%s/messages/%s';
  SelectFormat = '$select=%s';
  EmailAddressMember = 'emailAddress';
  NameMember = 'name';
  AddressMember = 'address';

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

class function TMailSupport.ReadMessageFields(const GraphClients: IGraphClientFactory; const Mailbox: TResolvedMailbox; const MessageId, Fields: string): TJSONObject;
begin
  const Graph = GraphClients.Create(Mailbox);
  try
    Result := ReadMessageFields(Graph, MessageId, Fields);
  finally
    Graph.Free;
  end;
end;

class function TMailSupport.ReadMessageFields(const Graph: TGraphHttpClient; const MessageId, Fields: string): TJSONObject;
begin
  const Endpoint = Format(MessageEndpointFormat, [Graph.GetUserPrefix, TNetEncoding.URL.Encode(MessageId)]);
  Result := Graph.Get(Endpoint, Format(SelectFormat, [Fields]));
end;

class function TMailSupport.RecipientsIn(const Message: TJSONObject; const Member: string): TArray<string>;
begin
  Result := [];

  var Recipients: TJSONArray;
  if not Message.TryGetValue<TJSONArray>(Member, Recipients) then
    Exit;

  for var Recipient in Recipients do
  begin
    Result := Result + [FormatAddress(AddressOf(Recipient))];
  end;
end;

class function TMailSupport.AddressOf(const Recipient: TJSONValue): TEmailAddress;
begin
  Result := Default(TEmailAddress);

  var EmailAddress: TJSONObject;
  if not Recipient.TryGetValue<TJSONObject>(EmailAddressMember, EmailAddress) then
    Exit;

  Result.Name    := EmailAddress.GetValue<string>(NameMember, '');
  Result.Address := EmailAddress.GetValue<string>(AddressMember, '');
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
